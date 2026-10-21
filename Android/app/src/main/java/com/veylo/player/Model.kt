package com.veylo.player

data class Channel(
    val key: String,
    val name: String,
    val title: String,
    val quality: String,
    val category: String,
    val logo: String,
    val url: String,
    val altUrl: String,
    val streamId: String?,
    val epgId: String
)

class Category(val name: String, val channels: List<Channel>)

class Country(val code: String, val name: String, val categories: List<Category>, val channels: List<Channel>)

data class Programme(val title: String, val desc: String, val start: Long, val end: Long)

/** A saved account. The password / playlist link are stored only when "Save this provider" is on. */
data class Provider(
    val id: String,
    val name: String,
    val kind: String,              // "xtream" | "m3u"
    val server: String = "",
    val username: String = "",
    val password: String = "",
    val playlistUrl: String = "",
    val lastUsed: Long = 0
)

class Session(
    val provider: Provider,
    val xtream: Xtream?,
    val channels: List<Channel>,
    val categories: List<Category>,
    val countries: List<Country>?
) {
    val byKey: Map<String, Channel> = channels.associateBy { it.key }
}

class LoginError(message: String) : Exception(message)
