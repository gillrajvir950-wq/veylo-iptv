package com.veylo.player

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

enum class Screen { Login, Loading, Browser, Player, Vod }

/** Sections of the signed-in app (bottom bar on phones, top menu on TV). */
enum class Tab(val title: String) { Home("Home"), Live("Live TV"), Movies("Movies"), Series("Series"), Settings("Settings") }

/** A movie or episode to play. For series, `episodes` lets the player go on to the next one. */
class VodRequest(
    val url: String, val title: String, val subtitle: String, val key: String, val startAt: Long,
    val poster: String, val kind: String, val id: String, val ext: String,
    val series: VodItem? = null, val episodes: List<Episode> = emptyList(), val episodeIndex: Int = -1
)

class LibState(val loading: Boolean, val lib: Library?, val error: String?)

class PlayerRequest(val lineup: List<Channel>, val index: Int, val title: String)

/** Screen state for the whole app (single activity, survives rotation — configChanges). */
class AppState(context: Context, private val scope: CoroutineScope) {
    val appContext: Context = context.applicationContext
    val store = Store(context)
    val vlc by lazy { Vlc(context) }

    var screen by mutableStateOf(Screen.Login)
    var tab by mutableStateOf(Tab.Home)
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
    /** Movies & Series lists, detail page, VOD player. */
    var libraries by mutableStateOf<Map<VodKind, LibState>>(emptyMap())
    var detail by mutableStateOf<VodItem?>(null)
    var vod by mutableStateOf<VodRequest?>(null)
    /** Bumped when My List / resume points change. */
    var vodVersion by mutableStateOf(0)

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
                    tab = Tab.Home
                    libraries = emptyMap()
                    detail = null
                    screen = Screen.Browser
                    if (s.xtream != null) scope.launch {
                        delay(1500)
                        loadLibrary(VodKind.Movie)
                        loadLibrary(VodKind.Series)
                    }
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

    /** Saved copy at once; downloads when missing or older than 12 h (or `force`). */
    fun loadLibrary(kind: VodKind, force: Boolean = false) {
        val x = session?.xtream ?: return
        val current = libraries[kind]
        if (current?.loading == true) return
        if (!force && current?.lib != null && Vod.isFresh(current.lib)) return
        val owner = session
        libraries = libraries + (kind to LibState(true, current?.lib, null))
        scope.launch {
            var lib = current?.lib
            if (lib == null && !force) {
                lib = Vod.cached(appContext, x, kind)
                if (session !== owner) return@launch
                if (lib != null) libraries = libraries + (kind to LibState(!Vod.isFresh(lib), lib, null))
                if (lib != null && Vod.isFresh(lib)) return@launch
            }
            try {
                val fresh = Vod.download(appContext, x, kind)
                if (session === owner) libraries = libraries + (kind to LibState(false, fresh, null))
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                if (session === owner) libraries = libraries + (kind to LibState(false, lib, Repo.friendly(e)))
            }
        }
    }

    fun openVod(request: VodRequest) {
        vlc.stop()
        vod = request
        screen = Screen.Vod
    }

    fun closeVod() {
        vlc.stop()
        vod = null
        vodVersion += 1
        screen = Screen.Browser
    }

    fun showSettings() {
        tab = Tab.Settings
        screen = Screen.Browser
    }

    fun signOut() {
        vlc.stop()
        store.setActive(null)
        session = null
        player = null
        vod = null
        detail = null
        libraries = emptyMap()
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
