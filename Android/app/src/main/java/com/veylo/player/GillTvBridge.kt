package com.veylo.player

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/**
 * Secure app-to-app bridge for GillTV (the Android TV launcher). GillTV can browse and start channels
 * here; it never receives the provider address, user name, password or any stream / authenticated URL.
 *
 *  - Data: read-only ContentProvider [GillTvProvider] (authority [AUTHORITY]).
 *  - Playback: GillTV sends [ACTION_PLAY] / [ACTION_RESUME] to [MainActivity]; Veylo plays with its own login.
 *  - Only the pinned app (package + signing certificate) may query. Everything else gets an empty answer.
 */
object GillTvBridge {
    const val AUTHORITY = "com.veylo.player.gilltv"
    const val SCHEMA = 1
    const val ACTION_PLAY = "com.veylo.player.action.PLAY_CHANNEL"
    const val ACTION_RESUME = "com.veylo.player.action.RESUME_VOD"
    const val EXTRA_KEY = "channel_key"
    const val EXTRA_PROGRESS_KEY = "progress_key"

    /** package -> allowed signing certificate SHA-256 digests (lower-case hex). */
    private val PINNED: Map<String, Set<String>> = mapOf(
        "com.gilltv.launcher" to setOf("c0707633915720edffdcd9e493a55126710acd384aed0ca521f2c16d42dac5d9")
    )

    @Suppress("DEPRECATION")
    fun callerAllowed(context: Context, uid: Int): Boolean {
        val pm = context.packageManager
        val packages = pm.getPackagesForUid(uid) ?: return false
        for (pkg in packages) {
            val pinned = PINNED[pkg] ?: continue
            val signatures = try {
                if (Build.VERSION.SDK_INT >= 28) {
                    val info = pm.getPackageInfo(pkg, PackageManager.GET_SIGNING_CERTIFICATES).signingInfo
                    if (info == null) emptyList()
                    else if (info.hasMultipleSigners()) info.apkContentsSigners.toList() else info.signingCertificateHistory.toList()
                } else {
                    pm.getPackageInfo(pkg, PackageManager.GET_SIGNATURES).signatures.toList()
                }
            } catch (e: Exception) { emptyList() }
            // Every signer of the caller must be pinned.
            if (signatures.isNotEmpty() && signatures.all { sha256(it.toByteArray()) in pinned }) return true
        }
        return false
    }

    /** Image links are passed on only when they carry no account details. */
    fun publicUrl(url: String, store: Store): String {
        if (!(url.startsWith("http://") || url.startsWith("https://"))) return ""
        val a = store.active() ?: return url
        if (a.username.isNotEmpty() && url.contains(a.username)) return ""
        if (a.password.isNotEmpty() && url.contains(a.password)) return ""
        return url
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    // ---------- catalog snapshot (names / categories / logos only — no URLs with credentials) ----------

    class Item(val key: String, val name: String, val quality: String, val category: String, val logo: String)

    class Snapshot(val scope: String, val provider: String, val xtream: Boolean, val updated: Long,
                   val categories: List<String>, val items: List<Item>) {
        val byKey: Map<String, Item> by lazy { items.associateBy { it.key } }
    }

    private fun file(context: Context) = File(context.filesDir, "gilltv-catalog.json")

    @Volatile private var memo: Pair<Long, Snapshot>? = null

    /** Written after every sign-in, off the main thread. */
    fun publish(context: Context, session: Session, scope: String) {
        val user = session.xtream?.username.orEmpty()
        val pass = session.xtream?.password.orEmpty()
        fun safeLogo(url: String): String {
            if (!(url.startsWith("http://") || url.startsWith("https://"))) return ""
            if (user.isNotEmpty() && url.contains(user)) return ""
            if (pass.isNotEmpty() && url.contains(pass)) return ""
            return url
        }
        val items = JSONArray()
        session.channels.forEach { c ->
            items.put(JSONArray().put(c.key).put(c.title).put(c.quality).put(c.category).put(safeLogo(c.logo)))
        }
        val root = JSONObject().put("schema", SCHEMA).put("scope", scope).put("provider", session.provider.name)
            .put("xtream", session.xtream != null).put("updated", System.currentTimeMillis())
            .put("categories", JSONArray(session.categories.map { it.name })).put("items", items)
        val tmp = File(context.filesDir, "gilltv-catalog.tmp")
        tmp.writeText(root.toString())
        tmp.renameTo(file(context))
        memo = null
    }

    fun clear(context: Context) { file(context).delete(); memo = null }

    fun snapshot(context: Context): Snapshot? {
        val f = file(context)
        if (!f.exists()) return null
        memo?.let { if (it.first == f.lastModified()) return it.second }
        return try {
            val o = JSONObject(f.readText())
            val cats = o.getJSONArray("categories").let { a -> (0 until a.length()).map { a.getString(it) } }
            val arr = o.getJSONArray("items")
            val items = ArrayList<Item>(arr.length())
            for (i in 0 until arr.length()) {
                val r = arr.getJSONArray(i)
                items.add(Item(r.getString(0), r.getString(1), r.getString(2), r.getString(3), r.getString(4)))
            }
            Snapshot(o.optString("scope", "default"), o.optString("provider"), o.optBoolean("xtream"), o.optLong("updated"), cats, items)
                .also { memo = f.lastModified() to it }
        } catch (e: Exception) { null }
    }
}
