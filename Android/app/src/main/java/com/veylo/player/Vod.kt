package com.veylo.player

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

enum class VodKind { Movie, Series }

data class VodItem(
    val kind: VodKind,
    val id: String,
    val name: String,
    val title: String,
    val year: String,
    val rating: Double,
    val poster: String,
    val plot: String,
    val genre: String,
    val added: Long,
    val ext: String,
    val categoryId: String
) {
    /** Resume / My List key: "m:<id>" for movies, "s:<id>" for series. */
    val key: String get() = (if (kind == VodKind.Movie) "m:" else "s:") + id
}

class VodCategory(val id: String, val name: String, val items: List<VodItem>)

class Library(val kind: VodKind, val items: List<VodItem>, val categories: List<VodCategory>, val loadedAt: Long) {
    val byId: Map<String, VodItem> = items.associateBy { it.id }
}

class MovieInfo(val plot: String, val genre: String, val cast: String, val director: String, val year: String,
                val rating: Double, val duration: Long, val backdrop: String, val poster: String, val ext: String)

class Episode(val id: String, val season: Int, val number: Int, val title: String, val ext: String, val plot: String, val duration: Long, val image: String) {
    val key: String get() = "e:$id"
}

class Season(val number: Int, val episodes: List<Episode>)

class SeriesInfo(val plot: String, val genre: String, val cast: String, val year: String, val rating: Double,
                 val backdrop: String, val poster: String, val seasons: List<Season>)

/** Movies & Series from the Xtream API. Lists are saved on the phone per account (no password)
 *  so the next opening is instant; refreshed in the background after 12 h. */
object Vod {
    private const val FRESH = 12 * 3600 * 1000L

    private fun num(v: String): Double = v.toDoubleOrNull() ?: 0.0

    /** Poster links come as "//host/x.jpg", with escaped slashes or as bare TMDB paths. */
    fun image(raw: String): String {
        val u = raw.trim().replace("\\/", "/")
        if (u.isEmpty()) return ""
        if (u.startsWith("//")) return "http:$u"
        if (Regex("^/[A-Za-z0-9]+\\.(jpg|png|webp)$", RegexOption.IGNORE_CASE).matches(u)) return "https://image.tmdb.org/t/p/w342$u"
        return if (u.startsWith("http://") || u.startsWith("https://")) u else ""
    }

    private fun yearOf(text: String): String = Regex("\\b(19|20)\\d{2}\\b").find(text)?.value ?: ""

    /** "EN - The Movie (2021)" → "The Movie". */
    fun title(name: String): String {
        val t = Names.title(name).replace(Regex("\\s*[(\\[]\\s*(19|20)\\d{2}\\s*[)\\]]\\s*$"), "").trim()
        return t.ifEmpty { name }
    }

    private fun duration(info: JSONObject): Long {
        info.str("duration_secs").toLongOrNull()?.let { if (it > 0) return it }
        Regex("^(\\d+):(\\d{2}):(\\d{2})$").find(info.str("duration"))?.let { m ->
            return m.groupValues[1].toLong() * 3600 + m.groupValues[2].toLong() * 60 + m.groupValues[3].toLong()
        }
        info.str("episode_run_time").toLongOrNull()?.let { if (it > 0) return it * 60 }
        return 0
    }

    private fun firstImage(o: JSONObject, key: String): String {
        val v = o.opt(key)
        return when (v) {
            is JSONArray -> if (v.length() > 0) image(v.optString(0)) else ""
            null, JSONObject.NULL -> ""
            else -> image(v.toString())
        }
    }

    private fun parse(kind: VodKind, itemsText: String, catsText: String, loadedAt: Long): Library {
        val names = LinkedHashMap<String, String>()
        for (c in Xtream.rows(catsText)) names[c.str("category_id")] = c.str("category_name").ifEmpty { "Uncategorized" }
        val movie = kind == VodKind.Movie
        val items = ArrayList<VodItem>()
        for (v in Xtream.rows(itemsText)) {
            val id = v.str(if (movie) "stream_id" else "series_id")
            if (id.isEmpty()) continue
            val name = v.str("name").ifEmpty { v.str("title") }
            val r5 = num(v.str("rating_5based"))
            items.add(VodItem(
                kind = kind, id = id, name = name, title = title(name),
                year = v.str("year").ifEmpty { yearOf(name).ifEmpty { yearOf(v.str("releaseDate").ifEmpty { v.str("release_date") }) } },
                rating = if (r5 > 0) Math.round(r5 * 20) / 10.0 else num(v.str("rating")),
                poster = image(if (movie) v.str("stream_icon") else v.str("cover").ifEmpty { v.str("stream_icon") }),
                plot = v.str("plot"), genre = v.str("genre"),
                added = (v.str("added").ifEmpty { v.str("last_modified") }).toLongOrNull() ?: 0,
                ext = v.str("container_extension").ifEmpty { "mp4" }, categoryId = v.str("category_id")
            ))
        }
        val buckets = LinkedHashMap<String, MutableList<VodItem>>()
        for (it in items) buckets.getOrPut(if (names.containsKey(it.categoryId)) it.categoryId else "") { mutableListOf() }.add(it)
        val cats = ArrayList<VodCategory>()
        for ((id, name) in names) buckets[id]?.let { cats.add(VodCategory(id, name, it)) }
        buckets[""]?.let { cats.add(VodCategory("", "Uncategorized", it)) }
        return Library(kind, items, cats, loadedAt)
    }

    private fun cacheFile(context: Context, x: Xtream, kind: VodKind): File {
        val digest = MessageDigest.getInstance("SHA-256").digest("${x.server}|${x.username}".toByteArray())
        val name = digest.take(8).joinToString("") { "%02x".format(it) }
        return File(File(context.cacheDir, "veylo-library").apply { mkdirs() }, "$name-${kind.name.lowercase()}.json")
    }

    /** Saved copy (any age), or null. */
    suspend fun cached(context: Context, x: Xtream, kind: VodKind): Library? = withContext(Dispatchers.IO) {
        try {
            val f = cacheFile(context, x, kind)
            if (!f.exists()) return@withContext null
            val o = JSONObject(f.readText())
            parse(kind, o.optString("items"), o.optString("categories"), o.optLong("t"))
        } catch (e: Exception) { null }
    }

    fun isFresh(lib: Library) = System.currentTimeMillis() - lib.loadedAt < FRESH

    suspend fun download(context: Context, x: Xtream, kind: VodKind): Library = withContext(Dispatchers.IO) {
        val movie = kind == VodKind.Movie
        val cats = try { Net.get(x.endpoint(if (movie) "get_vod_categories" else "get_series_categories")) } catch (e: Exception) { "[]" }
        val items = Net.get(x.endpoint(if (movie) "get_vod_streams" else "get_series"), 180000)
        val now = System.currentTimeMillis()
        val lib = parse(kind, items, cats, now)
        if (lib.items.isEmpty()) throw LoginError(if (movie) "The provider has no movies." else "The provider has no series.")
        try {
            cacheFile(context, x, kind).writeText(JSONObject().put("t", now).put("items", items).put("categories", cats).toString())
        } catch (e: Exception) { /* storage full: still usable now */ }
        lib
    }

    fun clearCache(context: Context) {
        File(context.cacheDir, "veylo-library").listFiles()?.forEach { it.delete() }
    }

    fun movieUrl(x: Xtream, item: VodItem, ext: String = item.ext) =
        "${x.server}/movie/${Uri.encode(x.username)}/${Uri.encode(x.password)}/${item.id}.${ext.ifEmpty { "mp4" }}"

    fun episodeUrl(x: Xtream, ep: Episode) =
        "${x.server}/series/${Uri.encode(x.username)}/${Uri.encode(x.password)}/${ep.id}.${ep.ext.ifEmpty { "mp4" }}"

    suspend fun movieInfo(x: Xtream, id: String): MovieInfo = withContext(Dispatchers.IO) {
        val o = JSONObject(Net.get(x.endpoint("get_vod_info", "&vod_id=" + Uri.encode(id)), 30000))
        val info = o.optJSONObject("info") ?: JSONObject()
        val data = o.optJSONObject("movie_data") ?: JSONObject()
        MovieInfo(
            plot = info.str("plot").ifEmpty { info.str("description") }, genre = info.str("genre"),
            cast = info.str("cast").ifEmpty { info.str("actors") }, director = info.str("director"),
            year = yearOf(info.str("releasedate").ifEmpty { info.str("release_date") }), rating = num(info.str("rating")),
            duration = duration(info), backdrop = firstImage(info, "backdrop_path"),
            poster = image(info.str("movie_image").ifEmpty { info.str("cover_big") }), ext = data.str("container_extension")
        )
    }

    suspend fun seriesInfo(x: Xtream, id: String): SeriesInfo = withContext(Dispatchers.IO) {
        val o = JSONObject(Net.get(x.endpoint("get_series_info", "&series_id=" + Uri.encode(id)), 30000))
        val info = o.optJSONObject("info") ?: JSONObject()
        val seasons = ArrayList<Season>()
        val eps = o.opt("episodes")
        fun addSeason(key: String, rows: JSONArray?) {
            if (rows == null || rows.length() == 0) return
            val first = rows.optJSONObject(0)
            val number = key.toIntOrNull() ?: first?.str("season")?.toIntOrNull() ?: (seasons.size + 1)
            val list = ArrayList<Episode>()
            for (i in 0 until rows.length()) {
                val e = rows.optJSONObject(i) ?: continue
                val eid = e.str("id")
                if (eid.isEmpty()) continue
                val ei = e.optJSONObject("info") ?: JSONObject()
                list.add(Episode(eid, number, e.str("episode_num").toIntOrNull() ?: (i + 1), e.str("title").ifEmpty { "Episode ${i + 1}" },
                    e.str("container_extension").ifEmpty { "mp4" }, ei.str("plot"), duration(ei), image(ei.str("movie_image"))))
            }
            if (list.isNotEmpty()) seasons.add(Season(number, list.sortedBy { it.number }))
        }
        when (eps) {
            is JSONObject -> eps.keys().forEach { k -> addSeason(k, eps.optJSONArray(k)) }
            is JSONArray -> for (i in 0 until eps.length()) addSeason((i + 1).toString(), eps.optJSONArray(i))
        }
        SeriesInfo(
            plot = info.str("plot"), genre = info.str("genre"), cast = info.str("cast"),
            year = yearOf(info.str("releaseDate").ifEmpty { info.str("release_date") }), rating = num(info.str("rating")),
            backdrop = firstImage(info, "backdrop_path"), poster = image(info.str("cover")), seasons = seasons.sortedBy { it.number }
        )
    }
}
