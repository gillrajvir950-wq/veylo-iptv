package com.veylo.player

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Signing in: Xtream API, or an M3U playlist (a get.php link that the provider refuses as a
 *  file is opened through the Xtream API with the same details — like the iPhone app). */
object Repo {
    suspend fun connect(provider: Provider, format: String): Session = withContext(Dispatchers.IO) {
        if (provider.kind == "xtream") return@withContext xtreamSession(provider, Xtream(provider.server, provider.username, provider.password), format)
        val url = provider.playlistUrl.trim()
        try {
            val channels = M3U.parse(Net.get(url, 120000), url)
            if (channels.isEmpty()) throw LoginError("The playlist has no channels.")
            build(provider, null, channels, channels.map { it.category }.distinct())
        } catch (e: Exception) {
            val details = M3U.xtreamFrom(url) ?: throw e
            xtreamSession(provider, Xtream(details.first, details.second, details.third), format)
        }
    }

    private fun xtreamSession(provider: Provider, x: Xtream, format: String): Session {
        x.authenticate()
        val (channels, order) = x.loadLive(format)
        return build(provider, x, channels, order)
    }

    /** Categories in the provider's order (Uncategorized last), then countries. */
    private fun build(provider: Provider, x: Xtream?, channels: List<Channel>, order: List<String>): Session {
        val groups = LinkedHashMap<String, MutableList<Channel>>()
        order.forEach { if (it != "Uncategorized") groups[it] = mutableListOf() }
        channels.forEach { groups.getOrPut(it.category) { mutableListOf() }.add(it) }
        val uncategorized = groups.remove("Uncategorized")
        if (uncategorized != null) groups["Uncategorized"] = uncategorized
        val categories = groups.filterValues { it.isNotEmpty() }.map { Category(it.key, it.value) }
        return Session(provider, x, channels, categories, Names.buildCountries(categories))
    }

    fun friendly(e: Throwable): String = when (e) {
        is LoginError -> e.message ?: "Couldn’t sign in."
        is Net.HttpError -> if (e.code == 401) "Wrong username or password." else (e.message ?: "The provider refused the request.")
        is java.net.UnknownHostException -> "Couldn’t find the server. Check the address."
        is java.net.SocketTimeoutException -> "The provider took too long to answer."
        is java.io.IOException -> "Couldn’t reach the provider (${e.message ?: "network error"})."
        else -> e.message ?: "Something went wrong."
    }
}
