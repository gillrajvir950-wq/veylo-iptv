package com.veylo.player

/** M3U playlists: categories from group-title, logos from tvg-logo. */
object M3U {
    private fun attribute(name: String, line: String): String =
        Regex("$name=\"([^\"]*)\"", RegexOption.IGNORE_CASE).find(line)?.groupValues?.get(1)?.trim() ?: ""

    fun parse(text: String, baseUrl: String): List<Channel> {
        val channels = ArrayList<Channel>()
        var pending: Array<String>? = null   // name, group, logo, tvg-id
        for (raw in text.replace("﻿", "").lineSequence()) {
            val line = raw.trim()
            if (line.isEmpty()) continue
            if (line.startsWith("#EXTINF:")) {
                val comma = line.lastIndexOf(',')
                pending = arrayOf(
                    if (comma >= 0) line.substring(comma + 1).trim() else "",
                    attribute("group-title", line), attribute("tvg-logo", line), attribute("tvg-id", line)
                )
            } else if (!line.startsWith("#")) {
                var url = line
                if (!url.startsWith("http://", true) && !url.startsWith("https://", true)) url = baseUrl.substringBeforeLast('/') + "/" + url
                val info = pending ?: arrayOf("", "", "", "")
                val name = info[0].ifEmpty { "Channel ${channels.size + 1}" }
                channels.add(
                    Channel(
                        key = "m:" + Names.hash(url), name = name, title = Names.title(name), quality = Names.quality(name),
                        category = info[1].ifEmpty { "Uncategorized" }, logo = info[2], url = url, altUrl = "",
                        streamId = null, epgId = info[3]
                    )
                )
                pending = null
            }
        }
        return channels
    }

    /** `…/get.php?username=…&password=…` → Xtream login details (server, username, password). */
    fun xtreamFrom(url: String): Triple<String, String, String>? {
        val m = Regex("^(https?://[^?#]*?)/?get\\.php\\?(.*)$", RegexOption.IGNORE_CASE).find(url.trim()) ?: return null
        val params = HashMap<String, String>()
        for (pair in m.groupValues[2].split('&')) {
            val i = pair.indexOf('=')
            if (i > 0) params[pair.substring(0, i)] = android.net.Uri.decode(pair.substring(i + 1))
        }
        val user = params["username"] ?: return null
        val pass = params["password"] ?: return null
        return Triple(m.groupValues[1], user, pass)
    }
}
