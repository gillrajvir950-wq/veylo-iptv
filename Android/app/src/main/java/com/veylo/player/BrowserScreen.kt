package com.veylo.player

import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

/** A row of the category sidebar. */
class Section(val id: String, val label: String, val badge: String, val channels: List<Channel>, val kind: String = "list", val country: Country? = null)

@Composable
fun BrowserScreen(app: AppState) {
    val session = app.session ?: return
    var countryCode by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedId by rememberSaveable { mutableStateOf("all") }
    var query by rememberSaveable { mutableStateOf("") }
    val country = session.countries?.firstOrNull { it.code == countryCode }

    val favorites = remember(app.listsVersion, session) { app.store.favorites().mapNotNull { session.byKey[it] } }
    val recents = remember(app.listsVersion, session) { app.store.recents().mapNotNull { session.byKey[it] } }
    val results = remember(query, session) {
        val q = query.trim().lowercase()
        if (q.isEmpty()) emptyList() else session.channels.asSequence().filter { it.name.lowercase().contains(q) }.take(500).toList()
    }
    val sections: List<Section> = remember(session, country, favorites, recents, results, query) {
        if (country != null) {
            listOf(Section("back", "All countries", "‹", emptyList(), "back"), Section("cn:" + country.code, "All " + country.name, country.code, country.channels)) +
                country.categories.map { Section("c:" + it.name, Names.title(it.name), "", it.channels) }
        } else {
            val top = listOf(
                Section("search", if (query.isBlank()) "Search" else "Search: $query", "⌕", results, "search"),
                Section("all", "All Channels", "▤", session.channels),
                Section("favorites", "Favorites", "♥", favorites),
                Section("recent", "Recently Watched", "↺", recents)
            )
            val rest = session.countries?.map { Section("country:" + it.code, it.name, if (it.code == "OTHER") "…" else it.code, it.channels, "country", it) }
                ?: session.categories.map { Section("c:" + it.name, Names.title(it.name), "", it.channels) }
            top + rest
        }
    }
    val selected = sections.firstOrNull { it.id == selectedId } ?: sections.first { it.kind != "back" }

    BackHandler(enabled = country != null) { countryCode = null; selectedId = "all" }

    fun choose(s: Section) {
        when (s.kind) {
            "country" -> { countryCode = s.country?.code; selectedId = "cn:" + (s.country?.code ?: "") }
            "back" -> { countryCode = null; selectedId = "all" }
            else -> selectedId = s.id
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().background(VColor.Bg)) {
        val wide = maxWidth >= 640.dp
        Column(Modifier.fillMaxSize()) {
            // Header
            Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                BrandMark(36)
                Spacer(Modifier.weight(1f))
                if (wide) Text(session.provider.name, color = VColor.Faint, fontSize = 14.sp, modifier = Modifier.padding(end = 14.dp))
                Pill("Settings", { app.screen = Screen.Settings })
            }
            if (wide) {
                Row(Modifier.fillMaxSize()) {
                    LazyColumn(
                        Modifier.width(300.dp).fillMaxHeight().padding(start = 16.dp),
                        contentPadding = PaddingValues(bottom = 24.dp)
                    ) {
                        itemsIndexed(sections, key = { _, s -> s.id }) { _, s ->
                            FocusRow(onClick = { choose(s) }, selected = s.id == selected.id, modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp)) { f ->
                                Badge(s.badge, f)
                                Text(s.label, color = if (f) Color.Black else VColor.Text, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                                if (s.kind != "search" && s.kind != "back") Text(s.channels.size.toString(), color = if (f) Color.DarkGray else VColor.Faint, fontSize = 13.sp)
                            }
                        }
                    }
                    Box(Modifier.width(1.dp).fillMaxHeight().background(VColor.Line))
                    ChannelPane(app, selected, query, { query = it }, Modifier.weight(1f))
                }
            } else {
                LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    itemsIndexed(sections, key = { _, s -> s.id }) { _, s ->
                        FocusRow(
                            onClick = { choose(s) }, selected = s.id == selected.id, radius = 30.dp,
                            modifier = Modifier.border(1.dp, VColor.Line, RoundedCornerShape(30.dp)),
                            padding = PaddingValues(horizontal = 14.dp, vertical = 8.dp)
                        ) { f ->
                            Text((if (s.badge.isNotEmpty() && s.badge.length <= 2) s.badge + "  " else "") + s.label, color = if (f) Color.Black else VColor.Text, fontSize = 14.sp, maxLines = 1)
                        }
                    }
                }
                ChannelPane(app, selected, query, { query = it }, Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun Badge(text: String, focused: Boolean) {
    if (text.isEmpty()) { Spacer(Modifier.width(4.dp)); return }
    val code = text.length >= 2 && text[0].isLetter()
    Box(
        Modifier.width(if (code) 44.dp else 30.dp).padding(end = 12.dp)
            .then(if (code) Modifier.clip(RoundedCornerShape(6.dp)).background(if (focused) Color(0x22000000) else Color(0x22FFFFFF)) else Modifier),
        contentAlignment = Alignment.Center
    ) {
        Text(text, color = if (focused) Color.Black else VColor.Text, fontSize = if (code) 11.sp else 17.sp, fontWeight = FontWeight.Black, maxLines = 1)
    }
}

@Composable
private fun ChannelPane(app: AppState, section: Section, query: String, onQuery: (String) -> Unit, modifier: Modifier) {
    val favorites = remember(app.listsVersion) { app.store.favorites().toHashSet() }
    val listState = rememberLazyListState()
    LaunchedEffect(section.id) { listState.scrollToItem(0) }
    Column(modifier.fillMaxHeight().padding(horizontal = 16.dp)) {
        Row(verticalAlignment = Alignment.Bottom, modifier = Modifier.padding(start = 8.dp, top = 4.dp, bottom = 8.dp)) {
            Text(if (section.kind == "search") "Search" else section.label, color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Spacer(Modifier.width(12.dp))
            Text("${section.channels.size} channels", color = VColor.Faint, fontSize = 14.sp, modifier = Modifier.padding(bottom = 4.dp))
        }
        if (section.kind == "search") {
            val focus = remember { FocusRequester() }
            OutlinedTextField(
                value = query, onValueChange = onQuery, singleLine = true, placeholder = { Text("Channel name") },
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search, autoCorrect = false),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = Color.White, unfocusedTextColor = VColor.Text, focusedBorderColor = VColor.Accent,
                    unfocusedBorderColor = VColor.Line, cursorColor = Color.White
                ),
                modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp).focusRequester(focus)
            )
            LaunchedEffect(Unit) { delay(150); runCatching { focus.requestFocus() } }
        }
        if (section.channels.isEmpty()) {
            val message = when (section.id) {
                "favorites" -> "No favorites yet. Long-press a channel (or press the yellow / menu button) to add it."
                "recent" -> "Channels you watch will show up here."
                "search" -> if (query.isBlank()) "Type a channel name — results show while you type." else "Nothing found."
                else -> "No channels here."
            }
            Text(message, color = VColor.Faint, fontSize = 16.sp, modifier = Modifier.padding(24.dp))
            return@Column
        }
        LazyColumn(state = listState, contentPadding = PaddingValues(bottom = 32.dp)) {
            itemsIndexed(section.channels, key = { i, c -> c.key + "#" + i }) { i, c ->
                FocusRow(
                    onClick = { app.openPlayer(section.channels, i, section.label) },
                    onLongClick = { app.toggleFavorite(c) },
                    modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp).onPreviewKeyEvent { e ->
                        val code = e.nativeKeyEvent.keyCode
                        if (e.type == KeyEventType.KeyDown &&
                            (code == KeyEvent.KEYCODE_PROG_YELLOW || code == KeyEvent.KEYCODE_MENU)) { app.toggleFavorite(c); true } else false
                    },
                    padding = PaddingValues(horizontal = 12.dp, vertical = 8.dp)
                ) { f ->
                    Text((i + 1).toString(), color = if (f) Color.DarkGray else VColor.Faint, fontSize = 14.sp, modifier = Modifier.width(44.dp))
                    ChannelLogo(c, 88.dp, 50.dp, f)
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(c.title, color = if (f) Color.Black else VColor.Text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(Names.title(c.category), color = if (f) Color.DarkGray else VColor.Faint, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    if (c.quality.isNotEmpty()) Text(c.quality, color = if (f) Color.Black else VColor.Faint, fontSize = 11.sp, fontWeight = FontWeight.Black, modifier = Modifier.padding(horizontal = 8.dp))
                    if (favorites.contains(c.key)) Text("♥", color = if (f) Color(0xFFD0021B) else VColor.Red, fontSize = 16.sp)
                }
            }
        }
    }
}

