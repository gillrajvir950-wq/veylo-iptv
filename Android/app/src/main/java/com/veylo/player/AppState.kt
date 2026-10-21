package com.veylo.player

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

enum class Screen { Login, Loading, Browser, Settings, Player }

class PlayerRequest(val lineup: List<Channel>, val index: Int, val title: String)

/** Screen state for the whole app (single activity, survives rotation — configChanges). */
class AppState(context: Context, private val scope: CoroutineScope) {
    val store = Store(context)
    val vlc by lazy { Vlc(context) }

    var screen by mutableStateOf(Screen.Login)
    var session by mutableStateOf<Session?>(null)
    var loadingText by mutableStateOf("")
    var loginError by mutableStateOf<String?>(null)
    var player by mutableStateOf<PlayerRequest?>(null)
    /** Bumped when favorites/recents change, so lists recompose. */
    var listsVersion by mutableStateOf(0)
    var toast by mutableStateOf<String?>(null)
    /** Login opened from Settings › Add account (Back returns there). */
    var adding by mutableStateOf(false)
    /** Bumped when the app comes back from the background while a channel was playing. */
    var resumeTick by mutableStateOf(0)

    private var connectJob: Job? = null
    private var toastJob: Job? = null

    fun start() {
        val active = store.active()
        if (active != null) connect(active, save = false, autostart = true) else screen = Screen.Login
    }

    fun connect(provider: Provider, save: Boolean, autostart: Boolean = false) {
        connectJob?.cancel()
        loginError = null
        loadingText = "Connecting to ${provider.name.ifEmpty { Store.hostOf(provider.server + provider.playlistUrl) }}…"
        screen = Screen.Loading
        connectJob = scope.launch {
            var attempt = 0
            while (true) {
                try {
                    val s = Repo.connect(provider, store.format)
                    val saved = if (save) store.saveProvider(provider) else provider
                    if (save) store.setActive(saved.id) else if (saved.id.isNotEmpty()) store.touch(saved.id)
                    store.scope = saved.id.ifEmpty { "default" }
                    session = Session(saved, s.xtream, s.channels, s.categories, s.countries)
                    adding = false
                    screen = Screen.Browser
                    if (autostart && store.autostart) {
                        val last = session?.byKey?.get(store.lastChannel)
                        if (last != null) {
                            val cat = session?.categories?.firstOrNull { it.name == last.category }
                            val lineup = cat?.channels ?: listOf(last)
                            openPlayer(lineup, lineup.indexOf(last).coerceAtLeast(0), cat?.name ?: "Channels")
                        }
                    }
                    return@launch
                } catch (e: kotlinx.coroutines.CancellationException) {
                    throw e
                } catch (e: Exception) {
                    // Box just switched on: the network may not be up yet.
                    val network = e is java.net.UnknownHostException || e is java.net.ConnectException
                    if (autostart && network && attempt < 3) {
                        attempt += 1
                        loadingText = "Waiting for the network…"
                        delay(4000)
                        continue
                    }
                    loginError = Repo.friendly(e)
                    screen = Screen.Login
                    return@launch
                }
            }
        }
    }

    fun signOut() {
        vlc.stop()
        store.setActive(null)
        session = null
        player = null
        screen = Screen.Login
    }

    fun openPlayer(lineup: List<Channel>, index: Int, title: String) {
        player = PlayerRequest(lineup, index, title)
        screen = Screen.Player
    }

    fun closePlayer() {
        vlc.stop()
        player = null
        screen = Screen.Browser
    }

    fun watched(channel: Channel) {
        store.addRecent(channel.key)
        store.lastChannel = channel.key
        listsVersion += 1
    }

    fun toggleFavorite(channel: Channel) {
        val added = store.toggleFavorite(channel.key)
        listsVersion += 1
        showToast(if (added) "♥ Added to Favorites" else "Removed from Favorites")
    }

    fun showToast(text: String) {
        toast = text
        toastJob?.cancel()
        toastJob = scope.launch { delay(2200); toast = null }
    }
}
