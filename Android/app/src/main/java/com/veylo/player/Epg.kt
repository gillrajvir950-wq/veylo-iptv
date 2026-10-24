package com.veylo.player

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap

/** Now / next per channel (Xtream short EPG), shared by tiles, rows and the player.
 *  Kept until the current programme ends (max 10 min); two requests at a time. */
object Epg {
    private class Entry(val list: List<Programme>, val until: Long)

    private val cache = ConcurrentHashMap<String, Entry>()
    private val gate = Semaphore(2)
    @Volatile private var owner: Xtream? = null

    fun peek(channel: Channel): List<Programme>? {
        val e = cache[channel.key] ?: return null
        return if (e.until > System.currentTimeMillis()) e.list else null
    }

    suspend fun load(x: Xtream, channel: Channel): List<Programme> {
        if (owner !== x) { cache.clear(); owner = x }
        peek(channel)?.let { return it }
        val id = channel.streamId ?: return emptyList()
        return gate.withPermit {
            peek(channel) ?: withContext(Dispatchers.IO) {
                runCatching { x.shortEpg(id, 4) }.getOrDefault(emptyList())
            }.also { list ->
                val now = System.currentTimeMillis()
                val current = list.firstOrNull { it.end > now }
                cache[channel.key] = Entry(list, minOf(now + 600_000, current?.end ?: (now + 600_000)))
            }
        }
    }

    fun now(list: List<Programme>?): Programme? {
        val t = System.currentTimeMillis()
        return list?.firstOrNull { it.start <= t && it.end > t }
    }

    fun next(list: List<Programme>?): Programme? {
        val t = System.currentTimeMillis()
        return list?.firstOrNull { it.start > t }
    }
}

/** Programmes for a channel on screen; fetched after it has been visible for a moment. */
@Composable
fun rememberProgrammes(app: AppState, channel: Channel, wait: Long = 450): List<Programme>? {
    val x = app.session?.xtream
    var list by remember(channel.key) { mutableStateOf(Epg.peek(channel)) }
    if (x != null && channel.streamId != null) {
        LaunchedEffect(channel.key) {
            if (list == null) {
                delay(wait)
                list = Epg.load(x, channel)
            }
        }
    }
    return list
}
