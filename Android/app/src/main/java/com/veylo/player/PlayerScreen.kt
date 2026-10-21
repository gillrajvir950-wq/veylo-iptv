package com.veylo.player

import android.app.Activity
import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.util.VLCVideoLayout
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private val clock = SimpleDateFormat("HH:mm", Locale.getDefault())
private fun hm(t: Long) = clock.format(Date(t))

@Composable
fun PlayerScreen(app: AppState, request: PlayerRequest) {
    val lineup = request.lineup
    var index by remember(request) { mutableStateOf(request.index.coerceIn(0, lineup.size - 1)) }
    var previous by remember(request) { mutableStateOf(-1) }
    val channel = lineup[index]
    val current = rememberUpdatedState(channel)

    var status by remember { mutableStateOf("loading") }       // loading | playing | error
    var usingAlt by remember { mutableStateOf(false) }
    var drops by remember { mutableStateOf(0) }
    var restart by remember { mutableStateOf(0) }
    var paused by remember { mutableStateOf(false) }
    var overlay by remember { mutableStateOf(true) }
    var panel by remember { mutableStateOf(false) }
    var touch by remember { mutableStateOf(0) }
    var scale by remember { mutableStateOf(0) }
    var epg by remember { mutableStateOf<List<Programme>>(emptyList()) }
    var startedAt by remember { mutableStateOf(0L) }
    val rootFocus = remember { FocusRequester() }
    val layoutRef = remember { arrayOfNulls<VLCVideoLayout>(1) }

    // Full screen, screen stays on.
    val view = LocalView.current
    val activity = LocalContext.current as? Activity
    DisposableEffect(Unit) {
        view.keepScreenOn = true
        val window = activity?.window
        val controller = if (window != null) WindowCompat.getInsetsController(window, view) else null
        controller?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller?.hide(WindowInsetsCompat.Type.systemBars())
        onDispose {
            view.keepScreenOn = false
            controller?.show(WindowInsetsCompat.Type.systemBars())
            app.vlc.setListener(null)
            app.vlc.stop()
            layoutRef[0]?.let { app.vlc.detach(it) }
        }
    }

    fun failed() {
        val ch = current.value
        if (status == "playing" && drops < 3) {
            // Was playing and dropped: reconnect.
            drops += 1
            status = "loading"
            restart += 1
        } else if (!usingAlt && ch.altUrl.isNotEmpty()) {
            usingAlt = true
            app.vlc.play(ch.altUrl)
        } else {
            status = "error"
            overlay = true
        }
    }
    val onFailed = rememberUpdatedState({ failed() })

    DisposableEffect(Unit) {
        app.vlc.setListener { e ->
            when (e.type) {
                MediaPlayer.Event.Playing -> { status = "playing"; paused = false; startedAt = System.currentTimeMillis() }
                MediaPlayer.Event.Vout -> if (e.voutCount > 0) status = "playing"
                MediaPlayer.Event.Paused -> paused = true
                MediaPlayer.Event.EncounteredError, MediaPlayer.Event.EndReached -> onFailed.value()
            }
        }
        onDispose { }
    }

    // Tune: the old stream stops at once; the new one opens after a short rest (fast zapping).
    LaunchedEffect(channel.key, restart, app.resumeTick) {
        status = "loading"
        usingAlt = false
        paused = false
        app.vlc.stop()
        delay(if (restart > 0) 2000 else 350)
        app.vlc.play(channel.url)
        app.watched(channel)
        delay(20000)
        if (status == "loading") onFailed.value()
    }
    LaunchedEffect(channel.key) { drops = 0 }

    // Now / next (Xtream).
    LaunchedEffect(channel.key) {
        epg = emptyList()
        val x = app.session?.xtream ?: return@LaunchedEffect
        val id = channel.streamId ?: return@LaunchedEffect
        delay(600)
        epg = withContext(Dispatchers.IO) { runCatching { x.shortEpg(id) }.getOrDefault(emptyList()) }
    }

    // Overlay hides 5 s after the picture starts / the last key press.
    LaunchedEffect(overlay, touch, status, panel) {
        if (overlay && status == "playing" && !panel) { delay(5000); overlay = false }
    }
    LaunchedEffect(panel) { if (!panel) { delay(60); runCatching { rootFocus.requestFocus() } } }

    fun tune(to: Int) {
        if (lineup.isEmpty()) return
        val next = ((to % lineup.size) + lineup.size) % lineup.size
        if (next == index) return
        previous = index
        index = next
        overlay = true
        touch += 1
    }

    BackHandler { if (panel) panel = false else app.closePlayer() }

    Box(
        Modifier.fillMaxSize().background(Color.Black)
            .focusRequester(rootFocus)
            .onPreviewKeyEvent { e ->
                if (panel || e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                when (e.nativeKeyEvent.keyCode) {
                    KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_CHANNEL_UP -> { tune(index - 1); true }
                    KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_CHANNEL_DOWN -> { tune(index + 1); true }
                    KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> {
                        if (status == "error") { drops = 0; restart += 1 } else panel = true
                        true
                    }
                    KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_INFO -> { overlay = !overlay; touch += 1; true }
                    KeyEvent.KEYCODE_PROG_YELLOW, KeyEvent.KEYCODE_MENU -> { app.toggleFavorite(current.value); true }
                    KeyEvent.KEYCODE_PROG_BLUE, KeyEvent.KEYCODE_LAST_CHANNEL -> { if (previous >= 0) tune(previous); true }
                    KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_SPACE -> {
                        paused = app.vlc.togglePause(); overlay = true; touch += 1; true
                    }
                    else -> false
                }
            }
            .focusable()
    ) {
        AndroidView(
            factory = { ctx -> VLCVideoLayout(ctx).also { layoutRef[0] = it; app.vlc.attach(it) } },
            modifier = Modifier.fillMaxSize()
        )
        // Touch: tap shows / hides the controls.
        Box(Modifier.fillMaxSize().clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
            overlay = !overlay; touch += 1
        })

        if (status != "playing") {
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                if (status == "loading") {
                    CircularProgressIndicator(color = Color.White, strokeWidth = 3.dp)
                    Spacer(Modifier.height(16.dp))
                    Text(if (drops > 0) "Reconnecting…" else if (usingAlt) "Trying HLS…" else "Loading…", color = Color.White, fontSize = 18.sp)
                } else {
                    Text("This channel isn’t playing right now.", color = Color.White, fontSize = 20.sp)
                    Spacer(Modifier.height(8.dp))
                    Text("Press OK to retry · ▲▼ for another channel", color = VColor.Faint, fontSize = 15.sp)
                    Spacer(Modifier.height(14.dp))
                    Pill("Retry", { drops = 0; restart += 1 }, primary = true)
                }
            }
        }

        if (overlay || status != "playing") {
            Column(Modifier.fillMaxWidth().align(Alignment.BottomStart)
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color(0xE6000000))))
                .padding(horizontal = 32.dp, vertical = 22.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ChannelLogo(channel, 120.dp, 68.dp)
                    Spacer(Modifier.width(18.dp))
                    Column(Modifier.weight(1f)) {
                        Text("${index + 1} · ${request.title}", color = VColor.Faint, fontSize = 14.sp, maxLines = 1)
                        Text(channel.title, color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        val now = System.currentTimeMillis()
                        val cur = epg.firstOrNull { it.start <= now && it.end > now }
                        val next = epg.firstOrNull { it.start > now }
                        if (cur != null) Text("NOW  ${cur.title}  ·  ${hm(cur.start)}–${hm(cur.end)}", color = VColor.Text, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (next != null) Text("NEXT  ${next.title}  ·  ${hm(next.start)}", color = VColor.Faint, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    if (paused) Text("PAUSED", color = VColor.Yellow, fontSize = 14.sp, fontWeight = FontWeight.Black)
                }
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.horizontalScroll(rememberScrollState())) {
                    Pill("‹ Back", { app.closePlayer() })
                    Pill("▲ Prev", { tune(index - 1) })
                    Pill(if (paused) "▶ Play" else "❚❚ Pause", { paused = app.vlc.togglePause(); touch += 1 })
                    Pill("Next ▼", { tune(index + 1) })
                    Pill("☰ List", { panel = true })
                    Pill(if (app.store.favorites().contains(channel.key)) "♥ Saved" else "♡ Favorite", { app.toggleFavorite(channel); touch += 1 })
                    Pill(listOf("Fit", "Fill", "Stretch")[scale], { scale = (scale + 1) % 3; app.vlc.setScale(scale); touch += 1 })
                }
            }
        }

        if (panel) ChannelPanel(lineup, index, request.title, onPick = { panel = false; tune(it) })

        app.toast?.let {
            Text(it, color = Color.White, fontSize = 16.sp, modifier = Modifier.align(Alignment.TopCenter).padding(top = 30.dp)
                .background(Color(0xEE1E1B26), androidx.compose.foundation.shape.RoundedCornerShape(30.dp)).padding(horizontal = 22.dp, vertical = 12.dp))
        }
    }
}

@Composable
private fun ChannelPanel(lineup: List<Channel>, index: Int, title: String, onPick: (Int) -> Unit) {
    val state = rememberLazyListState()
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        state.scrollToItem((index - 3).coerceAtLeast(0))
        delay(80)
        runCatching { focus.requestFocus() }
    }
    Column(Modifier.fillMaxHeight().widthIn(max = 460.dp).fillMaxWidth().background(Color(0xF0101016)).padding(16.dp)) {
        Text(title, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(8.dp))
        LazyColumn(state = state, contentPadding = PaddingValues(bottom = 24.dp)) {
            itemsIndexed(lineup, key = { i, c -> c.key + "#" + i }) { i, c ->
                FocusRow(onClick = { onPick(i) }, selected = i == index, focusRequester = if (i == index) focus else null,
                    modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp), padding = PaddingValues(horizontal = 10.dp, vertical = 6.dp)) { f ->
                    Text((i + 1).toString(), color = if (f) Color.DarkGray else VColor.Faint, fontSize = 13.sp, modifier = Modifier.width(40.dp))
                    ChannelLogo(c, 64.dp, 36.dp, f)
                    Spacer(Modifier.width(12.dp))
                    Text(c.title, color = if (f) Color.Black else VColor.Text, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}
