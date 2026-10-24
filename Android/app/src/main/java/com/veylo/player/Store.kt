package com.veylo.player

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** App-private storage on this device. Saved accounts (with password) only when the user ticks
 *  "Save this provider"; favorites and recents are kept per account. */
class Store(context: Context) {
    private val prefs = context.getSharedPreferences("veylo", Context.MODE_PRIVATE)
    var scope: String = "default"

    fun providers(): List<Provider> {
        val raw = prefs.getString("providers", null) ?: return emptyList()
        return try {
            val a = JSONArray(raw)
            (0 until a.length()).mapNotNull { a.optJSONObject(it) }.map {
                Provider(it.str("id"), it.str("name"), it.str("kind"), it.str("server"), it.str("username"),
                    it.str("password"), it.str("playlistUrl"), it.optLong("lastUsed"))
            }
        } catch (e: Exception) { emptyList() }
    }

    private fun writeProviders(list: List<Provider>) {
        val a = JSONArray()
        list.forEach { p ->
            a.put(JSONObject().put("id", p.id).put("name", p.name).put("kind", p.kind).put("server", p.server)
                .put("username", p.username).put("password", p.password).put("playlistUrl", p.playlistUrl).put("lastUsed", p.lastUsed))
        }
        prefs.edit().putString("providers", a.toString()).apply()
    }

    /** Adds or updates (same server+user, or same playlist) and returns the saved copy. */
    fun saveProvider(p: Provider): Provider {
        val list = providers().toMutableList()
        val at = list.indexOfFirst {
            it.id == p.id || (it.kind == p.kind && if (p.kind == "xtream") it.server == p.server && it.username == p.username else it.playlistUrl == p.playlistUrl)
        }
        val id = if (at >= 0) list[at].id else "p" + System.currentTimeMillis().toString(36)
        val name = p.name.ifEmpty { if (at >= 0) list[at].name else hostOf(if (p.kind == "xtream") p.server else p.playlistUrl) }
        val saved = p.copy(id = id, name = name, lastUsed = System.currentTimeMillis())
        if (at >= 0) list[at] = saved else list.add(saved)
        writeProviders(list)
        return saved
    }

    fun removeProvider(id: String) {
        writeProviders(providers().filter { it.id != id })
        if (activeId() == id) setActive(null)
    }

    fun touch(id: String) = writeProviders(providers().map { if (it.id == id) it.copy(lastUsed = System.currentTimeMillis()) else it })

    fun activeId(): String? = prefs.getString("active", null)
    fun setActive(id: String?) = prefs.edit().putString("active", id).apply()
    fun active(): Provider? = activeId()?.let { id -> providers().firstOrNull { it.id == id } }

    private fun list(key: String): List<String> = try {
        val a = JSONArray(prefs.getString("$key.$scope", "[]"))
        (0 until a.length()).map { a.optString(it) }
    } catch (e: Exception) { emptyList() }

    private fun putList(key: String, list: List<String>) =
        prefs.edit().putString("$key.$scope", JSONArray(list).toString()).apply()

    fun favorites() = list("favorites")
    fun toggleFavorite(key: String): Boolean {
        val l = favorites().toMutableList()
        val added = !l.remove(key)
        if (added) l.add(0, key)
        putList("favorites", l)
        return added
    }

    fun recents() = list("recents")
    fun addRecent(key: String) = putList("recents", (listOf(key) + recents().filter { it != key }).take(30))

    // ---------- Movies & Series (per account) ----------
    fun myList(kind: VodKind) = list("mylist." + kind.name)
    fun toggleMyList(kind: VodKind, id: String): Boolean {
        val l = myList(kind).toMutableList()
        val added = !l.remove(id)
        if (added) l.add(0, id)
        putList("mylist." + kind.name, l)
        return added
    }

    /** kind "movie" (id = movie id) or "episode" (id = episode id, series = series id, label = "S1 · E2 · title"). */
    class Progress(val key: String, val pos: Long, val dur: Long, val t: Long, val title: String, val poster: String,
                   val kind: String, val id: String, val ext: String, val series: String, val label: String) {
        val fraction: Float get() = if (dur > 0) (pos.toFloat() / dur).coerceIn(0f, 1f) else 0f
    }

    /** Where movies / episodes were stopped (seconds), newest first. */
    fun progressAll(): List<Progress> = try {
        val o = JSONObject(prefs.getString("progress.$scope", "{}") ?: "{}")
        o.keys().asSequence().mapNotNull { k ->
            val p = o.optJSONObject(k) ?: return@mapNotNull null
            Progress(k, p.optLong("pos"), p.optLong("dur"), p.optLong("t"), p.str("title"), p.str("poster"), p.str("kind"), p.str("id"), p.str("ext"),
                p.str("series"), p.str("label"))
        }.sortedByDescending { it.t }.toList()
    } catch (e: Exception) { emptyList() }

    fun progress(key: String): Progress? = progressAll().firstOrNull { it.key == key }

    /** pos = null removes the entry (finished or restarted). Keeps the newest 300. */
    fun setProgress(key: String, pos: Long?, dur: Long = 0, title: String = "", poster: String = "", kind: String = "", id: String = "",
                    ext: String = "", series: String = "", label: String = "") {
        val o = try { JSONObject(prefs.getString("progress.$scope", "{}") ?: "{}") } catch (e: Exception) { JSONObject() }
        o.remove(key)
        if (pos != null) {
            o.put(key, JSONObject().put("pos", pos).put("dur", dur).put("t", System.currentTimeMillis())
                .put("title", title).put("poster", poster).put("kind", kind).put("id", id).put("ext", ext)
                .put("series", series).put("label", label))
        }
        if (o.length() > 300) {
            val keep = o.keys().asSequence().map { it to (o.optJSONObject(it)?.optLong("t") ?: 0) }.toList().sortedByDescending { it.second }.drop(300)
            keep.forEach { o.remove(it.first) }
        }
        prefs.edit().putString("progress.$scope", o.toString()).apply()
    }

    fun clearProgress() = prefs.edit().remove("progress.$scope").apply()

    var lastChannel: String
        get() = prefs.getString("lastChannel.$scope", "") ?: ""
        set(value) = prefs.edit().putString("lastChannel.$scope", value).apply()

    /** "ts" (default, like the iPhone app) or "m3u8". */
    var format: String
        get() = prefs.getString("format", "ts") ?: "ts"
        set(value) = prefs.edit().putString("format", value).apply()

    /** Lets GillTV (pinned app) browse channels and start playback here. No credentials are ever shared. */
    var bridgeEnabled: Boolean
        get() = prefs.getBoolean("gilltvBridge", true)
        set(value) = prefs.edit().putBoolean("gilltvBridge", value).apply()

    var autostart: Boolean
        get() = prefs.getBoolean("autostart", true)
        set(value) = prefs.edit().putBoolean("autostart", value).apply()

    companion object {
        fun hostOf(url: String): String = Regex("^[a-z]+://([^/:?#]+)", RegexOption.IGNORE_CASE).find(url)?.groupValues?.get(1) ?: "Provider"
    }
}
