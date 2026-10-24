package com.veylo.player

import android.content.Context
import android.net.Uri
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.util.VLCVideoLayout

/** One VLC engine for the app — the player that opens channels instantly on the iPhone. */
class Vlc(context: Context) {
    private val libVlc = LibVLC(context.applicationContext, arrayListOf(
        "--network-caching=1500",
        "--live-caching=1500",
        "--http-reconnect",
        "--no-stats",
        "--audio-time-stretch"
    ))
    val player = MediaPlayer(libVlc)
    private var listener: ((MediaPlayer.Event) -> Unit)? = null
    private var attached: VLCVideoLayout? = null

    init {
        player.setEventListener { event -> listener?.invoke(event) }
    }

    fun setListener(l: ((MediaPlayer.Event) -> Unit)?) { listener = l }

    fun attach(layout: VLCVideoLayout) {
        if (attached === layout) return
        if (attached != null) player.detachViews()
        player.attachViews(layout, null, false, false)
        attached = layout
    }

    fun detach(layout: VLCVideoLayout) {
        if (attached === layout) {
            player.detachViews()
            attached = null
        }
    }

    fun play(url: String) {
        val media = Media(libVlc, Uri.parse(url))
        media.setHWDecoderEnabled(true, false)
        media.addOption(":network-caching=1500")
        player.media = media
        media.release()
        player.play()
    }

    /** Movie / episode, optionally from a second. */
    fun playVod(url: String, startAt: Long) {
        val media = Media(libVlc, Uri.parse(url))
        media.setHWDecoderEnabled(true, false)
        media.addOption(":network-caching=3000")
        if (startAt > 5) media.addOption(":start-time=$startAt")
        player.media = media
        media.release()
        player.play()
    }

    /** Milliseconds. */
    val time: Long get() = try { player.time } catch (e: Exception) { 0L }
    val length: Long get() = try { player.length } catch (e: Exception) { 0L }

    fun seekTo(ms: Long) {
        val len = length
        val target = if (len > 0) ms.coerceIn(0, len - 1000) else ms.coerceAtLeast(0)
        try { player.setTime(target) } catch (e: Exception) { }
    }

    class Track(val id: Int, val name: String)

    fun audioTracks(): List<Track> = try {
        player.audioTracks?.filter { it.id >= 0 }?.map { Track(it.id, it.name ?: "Track ${it.id}") } ?: emptyList()
    } catch (e: Exception) { emptyList() }

    fun subtitleTracks(): List<Track> = try {
        player.spuTracks?.map { Track(it.id, if (it.id < 0) "Off" else (it.name ?: "Subtitle ${it.id}")) } ?: emptyList()
    } catch (e: Exception) { emptyList() }

    val audioTrack: Int get() = try { player.audioTrack } catch (e: Exception) { -1 }
    val subtitleTrack: Int get() = try { player.spuTrack } catch (e: Exception) { -1 }
    fun selectAudio(id: Int) { try { player.setAudioTrack(id) } catch (e: Exception) { } }
    fun selectSubtitle(id: Int) { try { player.setSpuTrack(id) } catch (e: Exception) { } }

    fun togglePause(): Boolean {
        return if (player.isPlaying) { player.pause(); true } else { player.play(); false }
    }

    fun stop() {
        try { player.stop() } catch (e: Exception) { }
    }

    /** Fit / Fill / Stretch. */
    fun setScale(mode: Int) {
        when (mode) {
            0 -> { player.setVideoScale(MediaPlayer.ScaleType.SURFACE_BEST_FIT) }
            1 -> { player.setVideoScale(MediaPlayer.ScaleType.SURFACE_FIT_SCREEN) }
            else -> { player.setVideoScale(MediaPlayer.ScaleType.SURFACE_FILL) }
        }
    }
}
