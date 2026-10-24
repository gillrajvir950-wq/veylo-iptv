package com.veylo.player

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Binder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Read-only data for GillTV. Paths: status, categories, channels, favorites, continue, epg.
 * Callers other than the pinned GillTV get an empty cursor (and nothing is revealed about why).
 */
class GillTvProvider : ContentProvider() {
    override fun onCreate() = true

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
        val ctx = context ?: return MatrixCursor(arrayOf("error"))
        val path = uri.pathSegments.firstOrNull().orEmpty()
        val caller = Binder.getCallingUid()
        if (!GillTvBridge.callerAllowed(ctx, caller)) return empty(path)
        val store = Store(ctx)
        if (!store.bridgeEnabled) return if (path == "status") status(null, false) else empty(path)
        val snap = GillTvBridge.snapshot(ctx)
        if (path == "status") return status(snap, true)
        if (snap == null) return empty(path)
        store.scope = snap.scope
        return when (path) {
            "categories" -> categories(snap)
            "channels" -> channels(snap, uri)
            "favorites" -> channelRows(store.favorites().mapNotNull { snap.byKey[it] }.take(60))
            "continue" -> continueRows(snap, store)
            "epg" -> epg(snap, store, uri)
            else -> empty(path)
        }
    }

    private fun empty(path: String) = MatrixCursor(columnsOf(path))

    private fun columnsOf(path: String): Array<String> = when (path) {
        "status" -> STATUS
        "categories" -> arrayOf("name", "count")
        "epg" -> arrayOf("key", "now_title", "now_start", "now_end", "next_title", "next_start")
        "continue" -> CONTINUE
        else -> CHANNEL
    }

    private fun status(snap: GillTvBridge.Snapshot?, enabled: Boolean): Cursor {
        val c = MatrixCursor(STATUS)
        c.addRow(arrayOf(GillTvBridge.SCHEMA, if (snap != null) 1 else 0, snap?.provider ?: "", snap?.items?.size ?: 0,
            snap?.updated ?: 0L, if (snap?.xtream == true) 1 else 0, if (enabled) 1 else 0, BuildConfig.VERSION_NAME))
        return c
    }

    private fun categories(snap: GillTvBridge.Snapshot): Cursor {
        val counts = HashMap<String, Int>()
        snap.items.forEach { counts[it.category] = (counts[it.category] ?: 0) + 1 }
        val c = MatrixCursor(arrayOf("name", "count"))
        snap.categories.forEach { n -> counts[n]?.let { c.addRow(arrayOf(n, it)) } }
        counts.keys.filter { it !in snap.categories }.forEach { c.addRow(arrayOf(it, counts[it])) }
        return c
    }

    private fun channels(snap: GillTvBridge.Snapshot, uri: Uri): Cursor {
        val category = uri.getQueryParameter("category")
        val q = uri.getQueryParameter("q")?.trim()?.lowercase().orEmpty()
        val limit = (uri.getQueryParameter("limit")?.toIntOrNull() ?: 100).coerceIn(1, 500)
        val offset = (uri.getQueryParameter("offset")?.toIntOrNull() ?: 0).coerceAtLeast(0)
        val rows = snap.items.asSequence()
            .filter { category == null || it.category == category }
            .filter { q.isEmpty() || it.name.lowercase().contains(q) }
            .drop(offset).take(limit).toList()
        return channelRows(rows)
    }

    private fun channelRows(items: List<GillTvBridge.Item>): Cursor {
        val c = MatrixCursor(CHANNEL)
        items.forEach { c.addRow(arrayOf(it.key, it.name, it.quality, it.category, it.logo)) }
        return c
    }

    private fun continueRows(snap: GillTvBridge.Snapshot, store: Store): Cursor {
        val c = MatrixCursor(CONTINUE)
        store.progressAll().take(12).forEach { p ->
            c.addRow(arrayOf(p.key, p.kind, p.title, p.label, GillTvBridge.publicUrl(p.poster, store), (p.fraction * 100).toInt(), p.t))
        }
        store.recents().mapNotNull { snap.byKey[it] }.take(12).forEach { ch ->
            c.addRow(arrayOf(ch.key, "live", ch.name, ch.category, ch.logo, -1, 0L))
        }
        return c
    }

    /** Now / next from the provider (asked with Veylo's own login; only titles and times go back). */
    private fun epg(snap: GillTvBridge.Snapshot, store: Store, uri: Uri): Cursor {
        val c = MatrixCursor(columnsOf("epg"))
        val keys = uri.getQueryParameter("keys")?.split(',')?.map { it.trim() }?.filter { it.startsWith("x:") }?.distinct()?.take(12).orEmpty()
        val provider = store.active()
        if (keys.isEmpty() || provider == null || !snap.xtream) return c
        val x = if (provider.kind == "xtream") Xtream(provider.server, provider.username, provider.password)
        else M3U.xtreamFrom(provider.playlistUrl)?.let { Xtream(it.first, it.second, it.third) } ?: return c
        val rows = runBlocking {
            withTimeoutOrNull(8000) {
                coroutineScope {
                    keys.map { k ->
                        async(Dispatchers.IO) {
                            val item = snap.byKey[k] ?: return@async null
                            val ch = Channel(item.key, item.name, item.name, item.quality, item.category, item.logo, "", "", k.removePrefix("x:"), "")
                            val list = runCatching { Epg.load(x, ch) }.getOrDefault(emptyList())
                            k to list
                        }
                    }.awaitAll()
                }
            }
        }.orEmpty()
        rows.filterNotNull().forEach { (k, list) ->
            val now = Epg.now(list); val next = Epg.next(list)
            c.addRow(arrayOf(k, now?.title.orEmpty(), now?.start ?: 0L, now?.end ?: 0L, next?.title.orEmpty(), next?.start ?: 0L))
        }
        return c
    }

    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException("read-only")
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException("read-only")
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException("read-only")

    companion object {
        private val STATUS = arrayOf("schema", "signed_in", "provider", "channels", "updated", "epg", "enabled", "version")
        private val CHANNEL = arrayOf("key", "name", "quality", "category", "logo")
        private val CONTINUE = arrayOf("key", "kind", "title", "subtitle", "poster", "percent", "time")
    }
}
