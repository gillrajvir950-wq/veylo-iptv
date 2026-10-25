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
    /** Details of a saved account that failed to open, shown in the login form (fix password / retry). */
    var loginPrefill by mutableStateOf<Provider?>(null)
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

    /** Requests from GillTV (via MainActivity intents), handled as soon as the session is up. */
    private var pendingChannel: String? = null
    private var pendingResume: String? = null

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
                    // Typed again on the login screen (e.g. a new password) with "Save" off: an account
                    // saved earlier is still updated, so it never keeps the old password.
                    val known = if (!save && provider.id.isEmpty()) store.matchProvider(provider) else null
                    val saved = if (save || known != null) store.saveProvider(provider) else provider
                    if (save) store.setActive(saved.id) else if (saved.id.isNotEmpty()) store.touch(saved.id)
                    store.scope = saved.id.ifEmpty { "default" }
                    session = Session(saved, s.xtream, s.channels, s.categories, s.countries)
                    adding = false
                    loginPrefill = null
                    tab = Tab.Home
                    libraries = emptyMap()
                    detail = null
                    screen = Screen.Browser
                    publishCatalog()
                    if (consumePending()) return@launch
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
                    // Switching accounts / Reload channels while signed in: stay on the open account.
                    val open = session
                    if (open != null && !autostart) {
                        screen = Screen.Browser
                        showToast("Couldn’t open ${provider.name.ifEmpty { "that account" }}: ${Repo.friendly(e)}")
                        return@launch
                    }
                    loginError = Repo.friendly(e)
                    loginPrefill = provider
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

    /** Snapshot for GillTV (names, categories, logos only), written off the main thread. */
    private fun publishCatalog() {
        val s = session ?: return
        val id = store.scope
        scope.launch(kotlinx.coroutines.Dispatchers.IO) { runCatching { GillTvBridge.publish(appContext, s, id) } }
    }

    /** Intent from GillTV: play a channel / resume a movie or episode with this app's own login. */
    fun handleExternal(intent: android.content.Intent?) {
        when (intent?.action) {
            GillTvBridge.ACTION_PLAY -> { pendingChannel = intent.getStringExtra(GillTvBridge.EXTRA_KEY); pendingResume = null }
            GillTvBridge.ACTION_RESUME -> { pendingResume = intent.getStringExtra(GillTvBridge.EXTRA_PROGRESS_KEY); pendingChannel = null }
            else -> return
        }
        if (!store.bridgeEnabled) { pendingChannel = null; pendingResume = null; return }
        consumePending()
    }

    /** True when something started playing. Waits (returns false) while signed out or still connecting. */
    private fun consumePending(): Boolean {
        val s = session ?: return false
        if (screen == Screen.Login || screen == Screen.Loading) return false
        val key = pendingChannel
        val resume = pendingResume
        pendingChannel = null; pendingResume = null
        if (key != null) {
            val channel = s.byKey[key] ?: run { showToast("Channel not found"); return false }
            val cat = s.categories.firstOrNull { it.name == channel.category }
            val lineup = cat?.channels ?: listOf(channel)
            if (screen == Screen.Vod) closeVod()
            openPlayer(lineup, lineup.indexOf(channel).coerceAtLeast(0), cat?.name ?: "Channels")
            return true
        }
        if (resume != null) {
            val x = s.xtream ?: run { showToast("Needs an Xtream account"); return false }
            val p = store.progress(resume) ?: run { showToast("Nothing to resume"); return false }
            val movie = p.kind == "movie"
            val id = p.id
            val url = if (movie) "${x.server}/movie/${android.net.Uri.encode(x.username)}/${android.net.Uri.encode(x.password)}/$id.${p.ext.ifEmpty { "mp4" }}"
            else "${x.server}/series/${android.net.Uri.encode(x.username)}/${android.net.Uri.encode(x.password)}/$id.${p.ext.ifEmpty { "mp4" }}"
            if (screen == Screen.Player) closePlayer()
            openVod(VodRequest(url = url, title = p.title, subtitle = p.label, key = p.key, startAt = p.pos, poster = p.poster,
                kind = p.kind, id = p.id, ext = p.ext))
            return true
        }
        return false
    }

    fun signOut() {
        GillTvBridge.clear(appContext)
        vlc.stop()
        store.setActive(null)
        loginPrefill = null
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
