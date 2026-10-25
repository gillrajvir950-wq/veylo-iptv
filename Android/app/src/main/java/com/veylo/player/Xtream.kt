package com.veylo.player

import android.net.Uri
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/** Xtream Codes API. The live stream URL scheme is the same as on the iPhone app. */
class Xtream(server: String, val username: String, val password: String) {
    val server: String = server.trim().trimEnd('/').let { if (it.startsWith("http://", true) || it.startsWith("https://", true)) it else "http://$it" }

    data class Account(val status: String, val expires: Long?, val active: Int, val max: Int)

    fun endpoint(action: String? = null, extra: String = ""): String =
        "$server/player_api.php?username=${Uri.encode(username)}&password=${Uri.encode(password)}" +
            (if (action != null) "&action=$action" else "") + extra

    fun authenticate(): Account {
        val text = Net.get(endpoint())
        val root = try { JSONObject(text) } catch (e: Exception) { throw LoginError("The provider didn’t answer like an Xtream server.") }
        val info = root.optJSONObject("user_info") ?: throw LoginError("Wrong username or password.")
        if (info.str("auth") != "1") throw LoginError("Wrong username or password.")
        return Account(
            info.str("status"),
            info.str("exp_date").toLongOrNull()?.times(1000),
            info.str("active_cons").toIntOrNull() ?: 0,
            info.str("max_connections").toIntOrNull() ?: 0
        )
    }

    fun streamUrl(id: String, ext: String) = "$server/live/${Uri.encode(username)}/${Uri.encode(password)}/$id.$ext"

    /** Live channels in the provider's category order. `format` = "ts" (default) or "m3u8". */
    fun loadLive(format: String): Pair<List<Channel>, List<String>> {
        val other = if (format == "ts") "m3u8" else "ts"
        val names = HashMap<String, String>()
        val order = ArrayList<String>()
        try {
            for (c in rows(Net.get(endpoint("get_live_categories")))) {
                val name = c.str("category_name").ifEmpty { "Uncategorized" }
                names[c.str("category_id")] = name
                order.add(name)
            }
        } catch (e: Exception) { /* no category API: everything is Uncategorized */ }
        val channels = ArrayList<Channel>()
        for (s in rows(Net.get(endpoint("get_live_streams"), 120000))) {
            val id = s.str("stream_id")
            if (id.isEmpty()) continue
            val name = s.str("name").ifEmpty { "Channel $id" }
            channels.add(
                Channel(
                    key = "x:$id", name = name, title = Names.title(name), quality = Names.quality(name),
                    category = names[s.str("category_id")] ?: "Uncategorized", logo = s.str("stream_icon"),
                    url = streamUrl(id, format), altUrl = streamUrl(id, other), streamId = id, epgId = s.str("epg_channel_id")
                )
            )
        }
        if (channels.isEmpty()) throw LoginError("The provider returned no live channels.")
        return channels to order
    }

    /** Now / next for one channel (base64 titles). */
    fun shortEpg(streamId: String, limit: Int = 4): List<Programme> {
        val text = Net.get(endpoint("get_short_epg", "&stream_id=$streamId&limit=$limit"), 20000)
        val root = try { JSONObject(text) } catch (e: Exception) { return emptyList() }
        val list = root.optJSONArray("epg_listings") ?: return emptyList()
        val now = System.currentTimeMillis()
        val out = ArrayList<Programme>()
        for (i in 0 until list.length()) {
            val p = list.optJSONObject(i) ?: continue
            val start = p.str("start_timestamp").toLongOrNull()?.times(1000) ?: date(p.str("start"))
            val end = p.str("stop_timestamp").toLongOrNull()?.times(1000) ?: date(p.str("end").ifEmpty { p.str("stop") })
            val title = base64(p.str("title"))
            if (title.isNotEmpty() && end > now) out.add(Programme(title, base64(p.str("description")), start, end))
        }
        return out.sortedBy { it.start }
    }

    companion object {
        /** Lists may be arrays or objects keyed by id; bad rows are skipped. */
        fun rows(text: String): List<JSONObject> {
            val t = text.trim()
            val out = ArrayList<JSONObject>()
            try {
                if (t.startsWith("[")) {
                    val a = JSONArray(t)
                    for (i in 0 until a.length()) a.optJSONObject(i)?.let { out.add(it) }
                } else if (t.startsWith("{")) {
                    val o = JSONObject(t)
                    val keys = o.keys()
                    while (keys.hasNext()) o.optJSONObject(keys.next())?.let { out.add(it) }
                }
            } catch (e: Exception) { /* not JSON */ }
            return out
        }

        private fun base64(value: String): String = try {
            String(Base64.decode(value, Base64.DEFAULT), Charsets.UTF_8).trim()
        } catch (e: Exception) { value }

        private fun date(value: String): Long = try {
            SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).apply { timeZone = TimeZone.getDefault() }.parse(value)?.time ?: 0L
        } catch (e: Exception) { 0L }
    }
}

/** JSON value as text: "" for missing / null (Android's optString returns "null"). */
fun JSONObject.str(key: String): String {
    val v = opt(key)
    return if (v == null || v == JSONObject.NULL) "" else v.toString()
}
