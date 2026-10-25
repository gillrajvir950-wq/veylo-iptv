package com.veylo.player

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** HTTP for provider APIs and playlists. Some providers refuse unknown apps (HTTP 451, 884, 403…),
 *  so a refused request is repeated with the identities other IPTV players use; the one that
 *  works is kept for the next requests. Nothing is logged (URLs contain the password). */
object Net {
    const val VLC_AGENT = "VLC/3.0.21 LibVLC/3.0.21"
    private val AGENTS = listOf<String?>(null, VLC_AGENT, "IPTVSmartersPro", "okhttp/4.12.0")

    @Volatile var workingAgent: String? = null

    class HttpError(val code: Int) : IOException("The provider answered HTTP $code.")

    fun get(url: String, readTimeoutMs: Int = 60000): String {
        val order = (listOf(workingAgent) + AGENTS).distinct()
        var last: IOException? = null
        for (agent in order) {
            try {
                val text = getOnce(url, agent, readTimeoutMs)
                workingAgent = agent
                return text
            } catch (e: HttpError) {
                last = e
                if (e.code == 401 || e.code == 404) throw e
            } catch (e: java.net.SocketTimeoutException) {
                throw e   // slow / dead server: another identity won't help, and each try could wait a minute
            } catch (e: java.net.UnknownHostException) {
                throw e
            } catch (e: java.net.ConnectException) {
                throw e
            } catch (e: IOException) {
                last = e   // e.g. connection dropped: some panels cut unknown apps off this way
            }
        }
        throw last ?: IOException("Couldn’t reach the provider.")
    }

    private fun getOnce(url: String, agent: String?, readTimeoutMs: Int): String {
        var target = url
        var redirects = 0
        while (true) {
            val connection = URL(target).openConnection() as HttpURLConnection
            connection.connectTimeout = 15000
            connection.readTimeout = readTimeoutMs
            connection.instanceFollowRedirects = false   // http ↔ https redirects are followed below
            if (agent != null) connection.setRequestProperty("User-Agent", agent)
            connection.setRequestProperty("Accept", "*/*")
            try {
                val code = connection.responseCode
                if (code in 300..399 && redirects < 5) {
                    val location = connection.getHeaderField("Location") ?: throw HttpError(code)
                    target = URL(URL(target), location).toString()
                    redirects += 1
                    continue
                }
                if (code !in 200..299) throw HttpError(code)
                return connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            } finally {
                connection.disconnect()
            }
        }
    }
}
