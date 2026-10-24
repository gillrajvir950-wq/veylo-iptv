package com.veylo.player

import android.app.Activity
import android.content.pm.ActivityInfo
import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
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

private fun clockOf(ms: Long): String {
    val total = (ms / 1000).coerceAtLeast(0)
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) String.format("%d:%02d:%02d", h, m, s) else String.format("%d:%02d", m, s)
}

/** Movie / episode player: seek bar, ±10 s, audio & subtitles, resume, next episode. */
@Composable
fun VodPlayerScreen(app: AppState, start: VodRequest) {
    var request by remember(start) { mutableStateOf(start) }
    val current = rememberUpdatedState(request)
    var status by remember { mutableStateOf("loading") }   // loading | playing | paused | ended | error
    var time by remember { mutableStateOf(0L) }
    var length by remember { mutableStateOf(0L) }
    var overlay by remember { mutableStateOf(true) }
    var touch by remember { mutableStateOf(0) }
    var scrub by remember { mutableStateOf<Float?>(null) }
    var tracksOpen by remember { mutableStateOf(false) }
    var nextIn by remember { mutableStateOf(-1) }
    val rootFocus = remember { FocusRequester() }
    val layoutRef = remember { arrayOfNulls<VLCVideoLayout>(1) }
    val tv = isTv(app)
    val view = LocalView.current
    val activity = LocalContext.current as? Activity

    val hasNext = request.episodeIndex >= 0 && request.episodeIndex + 1 < request.episodes.size

    fun save() {
        val r = current.value
        val pos = app.vlc.time / 1000
        val dur = app.vlc.length / 1000
        if (dur <= 0) return
        if (pos < 15 || pos >= dur * 0.95) {
            app.store.setProgress(r.key, null)
        } else {
            val label = if (r.kind == "episode") r.subtitle else ""
            app.store.setProgress(r.key, pos, dur, if (r.kind == "episode") (r.series?.title ?: r.title) else r.title,
                r.poster, r.kind, r.id, r.ext, r.series?.id ?: "", label)
        }
    }

    fun playNext() {
        val r = current.value
        val x = app.session?.xtream ?: return
        if (r.episodeIndex < 0 || r.episodeIndex + 1 >= r.episodes.size) return
        save()
        val ep = r.episodes[r.episodeIndex + 1]
        val p = app.store.progress(ep.key)
        request = VodRequest(
            url = Vod.episodeUrl(x, ep), title = r.title, subtitle = "S${ep.season} · E${ep.number}  ${ep.title}",
            key = ep.key, startAt = p?.pos ?: 0, poster = r.poster, kind = "episode", id = ep.id, ext = ep.ext,
            series = r.series, episodes = r.episodes, episodeIndex = r.episodeIndex + 1
        )
    }

    fun close() {
        save()
        app.closeVod()
    }

    DisposableEffect(Unit) {
        view.keepScreenOn = true
        if (!tv) activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        val window = activity?.window
        val controller = if (window != null) WindowCompat.getInsetsController(window, view) else null
        controller?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller?.hide(WindowInsetsCompat.Type.systemBars())
        app.vlc.setListener { e ->
            when (e.type) {
                MediaPlayer.Event.Playing -> status = "playing"
                MediaPlayer.Event.Paused -> status = "paused"
                MediaPlayer.Event.Buffering -> if (e.buffering < 100f && status == "loading") status = "loading"
                MediaPlayer.Event.EncounteredError -> { status = "error"; overlay = true }
                MediaPlayer.Event.EndReached -> {
                    app.store.setProgress(current.value.key, null)
                    status = "ended"
                    overlay = true
                }
            }
        }
        onDispose {
            save()
            view.keepScreenOn = false
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            controller?.show(WindowInsetsCompat.Type.systemBars())
            app.vlc.setListener(null)
            app.vlc.stop()
            layoutRef[0]?.let { app.vlc.detach(it) }
        }
    }

    LaunchedEffect(request) {
        status = "loading"
        time = request.startAt * 1000
        length = 0
        nextIn = -1
        app.vlc.stop()
        delay(150)
        app.vlc.playVod(request.url, request.startAt)
    }
    // Clock + resume point every 10 s.
    LaunchedEffect(request) {
        var ticks = 0
        while (true) {
            delay(500)
            val t = app.vlc.time
            val l = app.vlc.length
            if (t > 0) time = t
            if (l > 0) length = l
            if (t > 0 && status == "loading") status = "playing"
            ticks += 1
            if (ticks % 20 == 0 && status == "playing") save()
        }
    }
    // Next episode countdown.
    LaunchedEffect(status, hasNext) {
        if (status == "ended") {
            if (hasNext) {
                for (s in 8 downTo 1) { nextIn = s; delay(1000) }
                nextIn = -1
                playNext()
            } else {
                delay(1500)
                app.closeVod()
            }
        }
    }
    LaunchedEffect(overlay, touch, status, tracksOpen, scrub) {
        if (overlay && status == "playing" && !tracksOpen && scrub == null) { delay(4000); overlay = false }
    }
    LaunchedEffect(Unit) { delay(80); runCatching { rootFocus.requestFocus() } }

    fun skip(seconds: Int) {
        app.vlc.seekTo(app.vlc.time + seconds * 1000L)
        time = (time + seconds * 1000L).coerceAtLeast(0)
        overlay = true
        touch += 1
    }
    fun pause() {
        if (status == "ended" || status == "error") return
        val paused = app.vlc.togglePause()
        status = if (paused) "paused" else "playing"
        if (paused) save()
        overlay = true
        touch += 1
    }

    BackHandler { if (tracksOpen) tracksOpen = false else close() }

    Box(
        Modifier.fillMaxSize().background(Color.Black)
            .focusRequester(rootFocus)
            .onPreviewKeyEvent { e ->
                if (tracksOpen || e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                when (e.nativeKeyEvent.keyCode) {
                    KeyEvent.KEYCODE_DPAD_LEFT -> { skip(-10); true }
                    KeyEvent.KEYCODE_DPAD_RIGHT -> { skip(10); true }
                    KeyEvent.KEYCODE_MEDIA_REWIND -> { skip(-30); true }
                    KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> { skip(30); true }
                    KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER,
                    KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_PAUSE, KeyEvent.KEYCODE_SPACE -> {
                        if (status == "error") { request = VodRequest(request.url, request.title, request.subtitle, request.key, time / 1000, request.poster,
                            request.kind, request.id, request.ext, request.series, request.episodes, request.episodeIndex) } else pause()
                        true
                    }
                    KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_INFO -> { overlay = !overlay; touch += 1; true }
                    KeyEvent.KEYCODE_CHANNEL_UP, KeyEvent.KEYCODE_MEDIA_NEXT -> { if (hasNext) playNext(); true }
                    KeyEvent.KEYCODE_MENU, KeyEvent.KEYCODE_PROG_YELLOW -> { tracksOpen = true; overlay = true; true }
                    else -> false
                }
            }
            .focusable()
    ) {
        AndroidView(factory = { ctx -> VLCVideoLayout(ctx).also { layoutRef[0] = it; app.vlc.attach(it) } }, modifier = Modifier.fillMaxSize())
        Box(Modifier.fillMaxSize().clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
            overlay = !overlay; touch += 1
        })

        when (status) {
            "loading" -> CircularProgressIndicator(color = Color.White, strokeWidth = 3.dp, modifier = Modifier.align(Alignment.Center).size(46.dp))
            "error" -> Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("⚠", color = VColor.Yellow, fontSize = 28.sp)
                Text("Couldn’t play this title", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Pill("Try again", {
                        request = VodRequest(request.url, request.title, request.subtitle, request.key, time / 1000, request.poster,
                            request.kind, request.id, request.ext, request.series, request.episodes, request.episodeIndex)
                    }, primary = true)
                    Pill("Close", { close() })
                }
            }
            "ended" -> if (nextIn > 0) Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Next episode in $nextIn", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Pill("Play now", { playNext() }, primary = true)
                    Pill("Close", { close() })
                }
            }
        }

        if (overlay && status != "error" && status != "ended") {
            // Top
            Row(
                Modifier.fillMaxWidth().align(Alignment.TopStart)
                    .background(Brush.verticalGradient(listOf(Color(0xCC000000), Color.Transparent)))
                    .padding(horizontal = 24.dp, vertical = 18.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (!tv) {
                    VodButton(42.dp, { close() }) { GlyphIcon(Glyph.Back, size = 18.dp) }
                    Spacer(Modifier.width(14.dp))
                }
                Column(Modifier.weight(1f)) {
                    Text(request.title, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (request.subtitle.isNotEmpty()) Text(request.subtitle, color = Color(0xB3FFFFFF), fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Box {
                    VodButton(42.dp, { tracksOpen = true }) { Text("CC", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Black) }
                    TrackMenu(app, tracksOpen) { tracksOpen = false }
                }
            }
            // Centre (touch)
            if (!tv) {
                Row(Modifier.align(Alignment.Center), horizontalArrangement = Arrangement.spacedBy(48.dp), verticalAlignment = Alignment.CenterVertically) {
                    VodButton(58.dp, { skip(-10) }) { Text("−10", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold) }
                    VodButton(78.dp, { pause() }) { GlyphIcon(if (status == "paused") Glyph.Play else Glyph.Pause, size = 30.dp) }
                    VodButton(58.dp, { skip(10) }) { Text("+10", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold) }
                }
            }
            // Bottom: seek bar
            Column(
                Modifier.fillMaxWidth().align(Alignment.BottomStart)
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color(0xE6000000))))
                    .padding(horizontal = 28.dp, vertical = 18.dp)
            ) {
                val max = length.coerceAtLeast(1).toFloat()
                Slider(
                    value = (scrub ?: time.toFloat()).coerceIn(0f, max), valueRange = 0f..max,
                    onValueChange = { scrub = it; touch += 1 },
                    onValueChangeFinished = { scrub?.let { app.vlc.seekTo(it.toLong()); time = it.toLong() }; scrub = null },
                    enabled = length > 0,
                    colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = VColor.Accent, inactiveTrackColor = Color(0x44FFFFFF))
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(clockOf((scrub?.toLong() ?: time)), color = Color(0xCCFFFFFF), fontSize = 13.sp)
                    if (status == "paused") {
                        Spacer(Modifier.width(12.dp))
                        Text("PAUSED", color = VColor.Yellow, fontSize = 12.sp, fontWeight = FontWeight.Black)
                    }
                    Spacer(Modifier.weight(1f))
                    if (tv) Text("◀▶ 10 s  ·  OK pause  ·  menu audio/subtitles" + if (hasNext) "  ·  CH+ next episode" else "",
                        color = Color(0x80FFFFFF), fontSize = 12.sp)
                    if (hasNext && !tv) {
                        Pill("Next episode ›", { playNext() })
                        Spacer(Modifier.width(12.dp))
                    }
                    Spacer(Modifier.width(12.dp))
                    Text(if (length > 0) "-" + clockOf(length - (scrub?.toLong() ?: time)) else "--:--", color = Color(0xCCFFFFFF), fontSize = 13.sp)
                }
            }
        }
    }
}

@Composable
private fun TrackMenu(app: AppState, open: Boolean, onDismiss: () -> Unit) {
    val audio = remember(open) { if (open) app.vlc.audioTracks() else emptyList() }
    val subs = remember(open) { if (open) app.vlc.subtitleTracks() else emptyList() }
    val currentAudio = remember(open) { app.vlc.audioTrack }
    val currentSub = remember(open) { app.vlc.subtitleTrack }
    DropdownMenu(expanded = open, onDismissRequest = onDismiss) {
        Text("AUDIO", color = VColor.Faint, fontSize = 11.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
        if (audio.isEmpty()) DropdownMenuItem(text = { Text("Default") }, onClick = onDismiss)
        audio.forEach { t ->
            DropdownMenuItem(text = { Text((if (t.id == currentAudio) "✓  " else "     ") + t.name) }, onClick = { app.vlc.selectAudio(t.id); onDismiss() })
        }
        Text("SUBTITLES", color = VColor.Faint, fontSize = 11.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
        if (subs.isEmpty()) DropdownMenuItem(text = { Text("None in this file") }, onClick = onDismiss)
        subs.forEach { t ->
            DropdownMenuItem(text = { Text((if (t.id == currentSub) "✓  " else "     ") + t.name) }, onClick = { app.vlc.selectSubtitle(t.id); onDismiss() })
        }
    }
}

@Composable
private fun VodButton(size: Dp, onClick: () -> Unit, content: @Composable () -> Unit) {
    Box(
        Modifier.size(size).clip(CircleShape).background(Color(0x40000000)).border(1.dp, Color(0x33FFFFFF), CircleShape).clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) { content() }
}
