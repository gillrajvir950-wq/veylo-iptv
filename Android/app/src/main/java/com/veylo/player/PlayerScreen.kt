package com.veylo.player

import android.app.Activity
import android.content.pm.ActivityInfo
import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import kotlinx.coroutines.delay
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.util.VLCVideoLayout
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private val clock = SimpleDateFormat("HH:mm", Locale.getDefault())
private fun hm(t: Long) = clock.format(Date(t))

/** Live player. Phone upright: video on top, details, controls and the channel list below
 *  (like the iPhone app). Landscape, full screen and TV: video fills the screen with an overlay.
 *  The VLC view keeps its place in the layout, so switching never restarts the stream. */
@Composable
fun PlayerScreen(app: AppState, request: PlayerRequest) {
    val lineup = request.lineup
    var index by remember(request) { mutableStateOf(request.index.coerceIn(0, lineup.size - 1)) }
    var previous by remember(request) { mutableStateOf(-1) }
    val channel = lineup[index]
    val current = rememberUpdatedState(channel)
    val tv = isTv(app)

    var status by remember { mutableStateOf("loading") }       // loading | playing | error
    var usingAlt by remember { mutableStateOf(false) }
    var drops by remember { mutableStateOf(0) }
    var restart by remember { mutableStateOf(0) }
    var paused by remember { mutableStateOf(false) }
    var overlay by remember { mutableStateOf(true) }
    var panel by remember { mutableStateOf(false) }
    var touch by remember { mutableStateOf(0) }
    var scale by remember { mutableStateOf(0) }
    var full by remember { mutableStateOf(false) }
    val rootFocus = remember { FocusRequester() }
    val layoutRef = remember { arrayOfNulls<VLCVideoLayout>(1) }
    val favorites = remember(app.listsVersion) { app.store.favorites().toHashSet() }
    val isFavorite = favorites.contains(channel.key)
    val programmes = rememberProgrammes(app, channel, 300)

    val view = LocalView.current
    val activity = LocalContext.current as? Activity
    DisposableEffect(Unit) {
        view.keepScreenOn = true
        onDispose {
            view.keepScreenOn = false
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            activity?.window?.let { WindowCompat.getInsetsController(it, view).show(WindowInsetsCompat.Type.systemBars()) }
            app.vlc.setListener(null)
            app.vlc.stop()
            layoutRef[0]?.let { app.vlc.detach(it) }
        }
    }

    fun failed() {
        val ch = current.value
        if (status == "playing" && drops < 3) {
            drops += 1        // was playing and dropped: reconnect
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
                MediaPlayer.Event.Playing -> { status = "playing"; paused = false }
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
    fun togglePause() { paused = app.vlc.togglePause(); overlay = true; touch += 1 }
    fun setFull(on: Boolean) {
        full = on
        overlay = true
        activity?.requestedOrientation = if (on) ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    }

    BackHandler {
        when {
            panel -> panel = false
            full && !tv -> setFull(false)
            else -> app.closePlayer()
        }
    }

    BoxWithConstraints(
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
                    KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_SPACE -> { togglePause(); true }
                    else -> false
                }
            }
            .focusable()
    ) {
        val immersive = tv || full || maxWidth > maxHeight
        LaunchedEffect(immersive) {
            val window = activity?.window ?: return@LaunchedEffect
            val controller = WindowCompat.getInsetsController(window, view)
            if (immersive) {
                controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                controller.hide(WindowInsetsCompat.Type.systemBars())
            } else controller.show(WindowInsetsCompat.Type.systemBars())
        }

        Column(Modifier.fillMaxSize()) {
            // The video keeps the first place in this column in both layouts.
            Box(
                (if (immersive) Modifier.fillMaxSize() else Modifier.statusBarsPadding().fillMaxWidth().aspectRatio(16f / 9f))
                    .background(Color.Black)
            ) {
                AndroidView(
                    factory = { ctx -> VLCVideoLayout(ctx).also { layoutRef[0] = it; app.vlc.attach(it) } },
                    modifier = Modifier.fillMaxSize()
                )
                // Touch: tap shows / hides the controls; swipe sideways changes channel (full screen).
                Box(
                    Modifier.fillMaxSize()
                        .pointerInput(immersive) {
                            var dx = 0f
                            detectHorizontalDragGestures(
                                onDragStart = { dx = 0f },
                                onDragEnd = { if (immersive && kotlin.math.abs(dx) > 120f) tune(if (dx < 0) index + 1 else index - 1) },
                                onHorizontalDrag = { _, amount -> dx += amount }
                            )
                        }
                        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                            if (panel) panel = false else { overlay = !overlay; touch += 1 }
                        }
                )
                StatusLayer(status, drops > 0, usingAlt, Modifier.align(Alignment.Center)) { drops = 0; restart += 1 }
                if (!immersive && (overlay || status != "playing")) {
                    Row(Modifier.fillMaxWidth().padding(10.dp)) {
                        RoundButton(36.dp, { app.closePlayer() }) { GlyphIcon(Glyph.Back, size = 18.dp) }
                        Spacer(Modifier.weight(1f))
                        RoundButton(36.dp, { setFull(true) }) { GlyphIcon(Glyph.Full, size = 16.dp) }
                    }
                }
            }
            if (!immersive) {
                PortraitPanel(
                    app, request, lineup, index, channel, programmes, status, paused, isFavorite,
                    onTune = { tune(it) }, onPause = { togglePause() }, onFull = { setFull(true) },
                    onReload = { drops = 0; restart += 1 }
                )
            }
        }

        if (immersive && (overlay || status != "playing") && !panel) {
            FullOverlay(
                request, index, channel, programmes, paused, isFavorite, tv, full && !tv, scale,
                onBack = { if (full && !tv) setFull(false) else app.closePlayer() },
                onTune = { tune(it) }, onPause = { togglePause() }, onList = { panel = true },
                onFavorite = { app.toggleFavorite(channel); touch += 1 },
                onScale = { scale = (scale + 1) % 3; app.vlc.setScale(scale); app.showToast(listOf("Fit", "Fill", "Stretch")[scale]); touch += 1 }
            )
        }
        if (panel) ChannelPanel(lineup, index, request.title, onPick = { panel = false; tune(it) }, onClose = { panel = false })

        app.toast?.let {
            Text(it, color = Color.White, fontSize = 15.sp, modifier = Modifier.align(Alignment.TopCenter).padding(top = 30.dp)
                .clip(RoundedCornerShape(30.dp)).background(Color(0xEE1E1B26)).padding(horizontal = 22.dp, vertical = 11.dp))
        }
    }
}

@Composable
private fun StatusLayer(status: String, reconnecting: Boolean, hls: Boolean, modifier: Modifier, onRetry: () -> Unit) {
    if (status == "playing") return
    Column(modifier.padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        if (status == "loading") {
            CircularProgressIndicator(color = Color.White, strokeWidth = 3.dp, modifier = Modifier.size(42.dp))
            Spacer(Modifier.height(12.dp))
            Text(if (reconnecting) "Connection lost — reconnecting…" else if (hls) "Trying HLS…" else "Loading…", color = Color.White, fontSize = 15.sp)
        } else {
            Text("⚠", color = VColor.Yellow, fontSize = 26.sp)
            Text("This channel isn’t playing right now", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(10.dp))
            Row(
                Modifier.clip(RoundedCornerShape(30.dp)).background(Color.White)
                    .clickable(onClick = onRetry).padding(horizontal = 18.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Filled.Refresh, contentDescription = null, tint = Color.Black, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("Retry", color = Color.Black, fontSize = 14.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun RoundButton(size: Dp, onClick: () -> Unit, filled: Boolean = false, content: @Composable () -> Unit) {
    Box(
        Modifier.size(size).clip(CircleShape)
            .background(if (filled) Color.White else Color(0x40000000))
            .border(1.dp, if (filled) Color.Transparent else Color(0x33FFFFFF), CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) { content() }
}

@Composable
private fun NowNext(programmes: List<Programme>?, modifier: Modifier = Modifier) {
    val now = Epg.now(programmes) ?: return
    val next = Epg.next(programmes)
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Color(0x14FFFFFF)).padding(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("NOW", color = Color.Black, fontSize = 10.sp, fontWeight = FontWeight.Black,
                modifier = Modifier.clip(RoundedCornerShape(4.dp)).background(Color.White).padding(horizontal = 6.dp, vertical = 1.dp))
            Spacer(Modifier.width(8.dp))
            Text(now.title, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            Text("${hm(now.start)} – ${hm(now.end)}", color = VColor.Faint, fontSize = 12.sp)
        }
        Spacer(Modifier.height(8.dp))
        ProgressLine(now)
        if (next != null) {
            Spacer(Modifier.height(8.dp))
            Row {
                Text("NEXT", color = VColor.Faint, fontSize = 10.sp, fontWeight = FontWeight.Black)
                Spacer(Modifier.width(8.dp))
                Text(next.title, color = VColor.Faint, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Text(hm(next.start), color = VColor.Faint, fontSize = 12.sp)
            }
        }
    }
}

@Composable
private fun PortraitPanel(
    app: AppState, request: PlayerRequest, lineup: List<Channel>, index: Int, channel: Channel,
    programmes: List<Programme>?, status: String, paused: Boolean, isFavorite: Boolean,
    onTune: (Int) -> Unit, onPause: () -> Unit, onFull: () -> Unit, onReload: () -> Unit
) {
    val list = rememberLazyListState()
    LazyColumn(state = list, modifier = Modifier.fillMaxSize().navigationBarsPadding(), contentPadding = PaddingValues(bottom = 20.dp)) {
        item {
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                ChannelLogo(channel, 64.dp, 38.dp)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        when {
                            paused -> Text("Paused", color = VColor.Faint, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                            status == "playing" -> LiveBadge()
                            status == "error" -> Text("Not playing", color = VColor.Yellow, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                            else -> Text("Loading…", color = VColor.Faint, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                        }
                        if (channel.quality.isNotEmpty()) {
                            Spacer(Modifier.width(6.dp))
                            Text(channel.quality, color = Color.Black, fontSize = 9.sp, fontWeight = FontWeight.Black,
                                modifier = Modifier.clip(RoundedCornerShape(4.dp)).background(Color(0xE6FFFFFF)).padding(horizontal = 5.dp, vertical = 1.dp))
                        }
                    }
                    Text(channel.title, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(Names.title(channel.category), color = VColor.Faint, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Box(Modifier.size(48.dp).clip(CircleShape).clickable { app.toggleFavorite(channel) }, contentAlignment = Alignment.Center) {
                    Icon(if (isFavorite) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder, contentDescription = "Favorite",
                        tint = if (isFavorite) Color(0xFFFF2D55) else Color.White)
                }
            }
        }
        item { NowNext(programmes, Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) }
        item {
            Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                RoundButton(48.dp, onReload) { Icon(Icons.Filled.Refresh, contentDescription = "Reload", tint = Color.White) }
                RoundButton(50.dp, { onTune(index - 1) }) { GlyphIcon(Glyph.Prev, size = 20.dp) }
                RoundButton(66.dp, onPause, filled = true) { GlyphIcon(if (paused) Glyph.Play else Glyph.Pause, Color.Black, 26.dp) }
                RoundButton(50.dp, { onTune(index + 1) }) { GlyphIcon(Glyph.Next, size = 20.dp) }
                RoundButton(48.dp, onFull) { GlyphIcon(Glyph.Full, size = 18.dp) }
            }
        }
        item {
            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.Bottom) {
                Text("More in ${request.title}", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Text("${lineup.size}", color = VColor.Faint, fontSize = 13.sp)
            }
        }
        itemsIndexed(lineup, key = { i, c -> "$i:" + c.key }) { i, c ->
            val currentRow = i == index
            Row(
                Modifier.fillMaxWidth().background(if (currentRow) Color(0x14FFFFFF) else Color.Transparent)
                    .clickable { onTune(i) }.padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                ChannelLogo(c, 80.dp, 45.dp)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(c.title, color = Color.White.copy(alpha = if (currentRow) 1f else 0.85f), fontSize = 15.sp,
                        fontWeight = if (currentRow) FontWeight.Bold else FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (currentRow) Text("Now playing", color = VColor.Red, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    else if (c.quality.isNotEmpty()) Text(c.quality, color = VColor.Faint, fontSize = 12.sp)
                }
            }
        }
    }
}

@Composable
private fun FullOverlay(
    request: PlayerRequest, index: Int, channel: Channel, programmes: List<Programme>?, paused: Boolean,
    isFavorite: Boolean, tv: Boolean, canExitFull: Boolean, scale: Int,
    onBack: () -> Unit, onTune: (Int) -> Unit, onPause: () -> Unit, onList: () -> Unit, onFavorite: () -> Unit, onScale: () -> Unit
) {
    val now = Epg.now(programmes)
    val next = Epg.next(programmes)
    Box(Modifier.fillMaxSize()) {
        // Top: back, channel, actions.
        Row(
            Modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(Color(0xCC000000), Color.Transparent)))
                .padding(horizontal = 24.dp, vertical = 18.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (!tv) {
                RoundButton(42.dp, onBack) { GlyphIcon(if (canExitFull) Glyph.ExitFull else Glyph.Back, size = 18.dp) }
                Spacer(Modifier.width(14.dp))
            }
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (paused) Text("PAUSED", color = VColor.Yellow, fontSize = 12.sp, fontWeight = FontWeight.Black) else LiveBadge()
                    Spacer(Modifier.width(8.dp))
                    Text("${index + 1} · ${request.title}", color = Color(0xB3FFFFFF), fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Text(channel.title, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (!tv) {
                RoundButton(42.dp, onFavorite) {
                    Icon(if (isFavorite) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder, contentDescription = "Favorite",
                        tint = if (isFavorite) Color(0xFFFF2D55) else Color.White, modifier = Modifier.size(20.dp))
                }
                Spacer(Modifier.width(10.dp))
                RoundButton(42.dp, onScale) { GlyphIcon(Glyph.Aspect, size = 18.dp) }
                Spacer(Modifier.width(10.dp))
                RoundButton(42.dp, onList) { GlyphIcon(Glyph.List, size = 18.dp) }
            }
        }
        // Centre (touch): previous / play-pause / next.
        if (!tv) {
            Row(Modifier.align(Alignment.Center), horizontalArrangement = Arrangement.spacedBy(44.dp), verticalAlignment = Alignment.CenterVertically) {
                RoundButton(56.dp, { onTune(index - 1) }) { GlyphIcon(Glyph.Prev, size = 22.dp) }
                RoundButton(76.dp, onPause) { GlyphIcon(if (paused) Glyph.Play else Glyph.Pause, size = 30.dp) }
                RoundButton(56.dp, { onTune(index + 1) }) { GlyphIcon(Glyph.Next, size = 22.dp) }
            }
        }
        // Bottom: logo, what's on, hints.
        Column(
            Modifier.align(Alignment.BottomStart).fillMaxWidth()
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color(0xE6000000))))
                .padding(horizontal = 32.dp, vertical = 22.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (tv) {
                    ChannelLogo(channel, 120.dp, 68.dp)
                    Spacer(Modifier.width(18.dp))
                }
                Column(Modifier.weight(1f)) {
                    if (now != null) {
                        Text("NOW  ${now.title}", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Spacer(Modifier.height(6.dp))
                        Box(Modifier.widthIn(max = 420.dp)) { ProgressLine(now) }
                        if (next != null) {
                            Spacer(Modifier.height(6.dp))
                            Text("NEXT  ${next.title}  ·  ${hm(next.start)}", color = VColor.Faint, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
            Spacer(Modifier.height(10.dp))
            Text(
                if (tv) "▲▼ channel   ·   OK channel list   ·   ◀▶ info   ·   yellow favorite   ·   blue previous"
                else "Swipe ← → to change channel",
                color = Color(0x80FFFFFF), fontSize = 12.sp
            )
        }
    }
}

@Composable
private fun ChannelPanel(lineup: List<Channel>, index: Int, title: String, onPick: (Int) -> Unit, onClose: () -> Unit) {
    val state = rememberLazyListState()
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        state.scrollToItem((index - 3).coerceAtLeast(0))
        delay(80)
        runCatching { focus.requestFocus() }
    }
    Row(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxHeight().widthIn(max = 440.dp).fillMaxWidth(0.85f).background(Color(0xF2101016)).statusBarsPadding().padding(14.dp)) {
            Text(title, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(8.dp))
            LazyColumn(state = state, contentPadding = PaddingValues(bottom = 24.dp)) {
                itemsIndexed(lineup, key = { i, c -> "$i:" + c.key }) { i, c ->
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
        Box(Modifier.weight(1f).fillMaxHeight().background(Color(0x55000000))
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClose))
    }
}
