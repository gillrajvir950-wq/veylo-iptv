package com.veylo.player

import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldColors
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

/** A row of the category list. */
class Section(val id: String, val label: String, val badge: String, val channels: List<Channel>, val kind: String = "list", val country: Country? = null)

private val fieldColors: TextFieldColors @Composable get() = OutlinedTextFieldDefaults.colors(
    focusedTextColor = Color.White, unfocusedTextColor = VColor.Text, focusedBorderColor = VColor.Accent,
    unfocusedBorderColor = Color(0x33FFFFFF), cursorColor = Color.White,
    focusedContainerColor = Color(0x14FFFFFF), unfocusedContainerColor = Color(0x14FFFFFF)
)

@Composable
fun LiveScreen(app: AppState, wide: Boolean, bottomSpace: Int) {
    if (wide) LiveTv(app) else LivePhone(app, bottomSpace)
}

private fun searchIn(list: List<Channel>, query: String): List<Channel> {
    val q = query.trim().lowercase()
    if (q.isEmpty()) return emptyList()
    return list.asSequence().filter { it.name.lowercase().contains(q) }.take(500).toList()
}

// ---------------------------------------------------------------- Phone

@Composable
private fun LivePhone(app: AppState, bottomSpace: Int) {
    val session = app.session ?: return
    var countryCode by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedId by rememberSaveable { mutableStateOf("all") }
    var searching by rememberSaveable { mutableStateOf(false) }
    var query by rememberSaveable { mutableStateOf("") }
    var menu by remember { mutableStateOf(false) }
    val country = session.countries?.firstOrNull { it.code == countryCode }

    val favorites = remember(app.listsVersion, session) { app.store.favorites().mapNotNull { session.byKey[it] } }
    val favoriteKeys = remember(favorites) { favorites.map { it.key }.toHashSet() }
    val recents = remember(app.listsVersion, session) { app.store.recents().mapNotNull { session.byKey[it] } }
    val scope = country?.channels ?: session.channels
    val chips: List<Section> = remember(session, country, favorites, recents) {
        listOf(
            Section("all", if (country != null) "All " + country.name else "All", "", scope),
            Section("favorites", "Favorites", "♥", favorites),
            Section("recent", "Recent", "", recents)
        ) + (country?.categories ?: session.categories).map { Section("c:" + it.name, Names.title(it.name), "", it.channels) }
    }
    val selected = chips.firstOrNull { it.id == selectedId } ?: chips.first()
    val results = remember(query, scope) { searchIn(scope, query) }
    val showing = if (searching && query.isNotBlank()) results else selected.channels
    val title = if (searching && query.isNotBlank()) "Search results" else selected.label
    val grid = rememberLazyGridState()
    LaunchedEffect(selected.id, countryCode, query) { grid.scrollToItem(0) }
    BackHandler(enabled = searching) { searching = false; query = "" }

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 12.dp, top = 10.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Live TV", color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            if (session.countries != null) {
                Box {
                    Pill((country?.name ?: "All countries") + "  ▾", { menu = true })
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text("All countries") }, onClick = { countryCode = null; selectedId = "all"; menu = false })
                        session.countries.forEach { c ->
                            DropdownMenuItem(text = { Text("${c.name}  ·  ${c.channels.size}") }, onClick = { countryCode = c.code; selectedId = "all"; menu = false })
                        }
                    }
                }
            }
            FocusRow(onClick = { searching = !searching; if (!searching) query = "" }, radius = 30.dp, padding = PaddingValues(10.dp)) { f ->
                Icon(if (searching) Icons.Filled.Close else Icons.Filled.Search, contentDescription = "Search", tint = if (f) Color.Black else Color.White)
            }
        }
        if (searching) {
            val focus = remember { FocusRequester() }
            OutlinedTextField(
                value = query, onValueChange = { query = it }, singleLine = true,
                placeholder = { Text(if (country != null) "Search ${country.name}" else "Search all channels") },
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search, autoCorrect = false),
                shape = RoundedCornerShape(30.dp), colors = fieldColors,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp).focusRequester(focus)
            )
            LaunchedEffect(Unit) { delay(100); runCatching { focus.requestFocus() } }
        } else {
            LazyRow(contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                itemsIndexed(chips, key = { _, s -> s.id }) { _, s ->
                    val active = s.id == selected.id
                    FocusRow(
                        onClick = { selectedId = s.id }, radius = 30.dp,
                        modifier = Modifier.clip(RoundedCornerShape(30.dp)).background(if (active) Color.White else Color(0x1AFFFFFF)),
                        padding = PaddingValues(horizontal = 15.dp, vertical = 8.dp)
                    ) { f ->
                        Text((if (s.badge.isNotEmpty()) s.badge + " " else "") + s.label, color = if (active || f) Color.Black else Color.White,
                            fontSize = 14.sp, fontWeight = if (active) FontWeight.SemiBold else FontWeight.Medium, maxLines = 1)
                    }
                }
            }
        }
        Row(Modifier.padding(horizontal = 20.dp, vertical = 4.dp), verticalAlignment = Alignment.Bottom) {
            Text(title, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            Spacer(Modifier.width(8.dp))
            Text("${showing.size}", color = VColor.Faint, fontSize = 13.sp)
        }
        if (showing.isEmpty()) {
            EmptyNote(when {
                searching && query.isBlank() -> "Type a channel name."
                searching -> "Nothing found for “$query”."
                selected.id == "favorites" -> "No favorites yet.\nPress and hold a channel to add it."
                selected.id == "recent" -> "Channels you watch will show up here."
                else -> "No channels here."
            })
        } else {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(150.dp), state = grid,
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = (bottomSpace + 16).dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(18.dp)
            ) {
                itemsIndexed(showing, key = { i, c -> "$i:" + c.key }) { i, c ->
                    ChannelTile(app, c, favoriteKeys.contains(c.key), onClick = { app.openPlayer(showing, i, title) })
                }
            }
        }
    }
}

@Composable
private fun EmptyNote(text: String) {
    Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) {
        Text(text, color = VColor.Faint, fontSize = 15.sp, lineHeight = 22.sp)
    }
}

// ---------------------------------------------------------------- TV / landscape

@Composable
private fun LiveTv(app: AppState) {
    val session = app.session ?: return
    var countryCode by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedId by rememberSaveable { mutableStateOf("all") }
    var query by rememberSaveable { mutableStateOf("") }
    val country = session.countries?.firstOrNull { it.code == countryCode }

    val favorites = remember(app.listsVersion, session) { app.store.favorites().mapNotNull { session.byKey[it] } }
    val favoriteKeys = remember(favorites) { favorites.map { it.key }.toHashSet() }
    val recents = remember(app.listsVersion, session) { app.store.recents().mapNotNull { session.byKey[it] } }
    val results = remember(query, session) { searchIn(session.channels, query) }
    val sections: List<Section> = remember(session, country, favorites, recents, results, query) {
        if (country != null) {
            listOf(Section("back", "All countries", "‹", emptyList(), "back"), Section("cn:" + country.code, "All " + country.name, country.code, country.channels)) +
                country.categories.map { Section("c:" + it.name, Names.title(it.name), "", it.channels) }
        } else {
            listOf(
                Section("search", if (query.isBlank()) "Search" else "Search: $query", "🔍", results, "search"),
                Section("all", "All Channels", "📺", session.channels),
                Section("favorites", "Favorites", "♥", favorites),
                Section("recent", "Recently Watched", "🕘", recents)
            ) + (session.countries?.map { Section("country:" + it.code, it.name, if (it.code == "OTHER") "…" else it.code, it.channels, "country", it) }
                ?: session.categories.map { Section("c:" + it.name, Names.title(it.name), "", it.channels) })
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

    Row(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.width(320.dp).fillMaxHeight().padding(start = 20.dp), contentPadding = PaddingValues(top = 6.dp, bottom = 24.dp)) {
            itemsIndexed(sections, key = { _, s -> s.id }) { _, s ->
                FocusRow(onClick = { choose(s) }, selected = s.id == selected.id, modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp)) { f ->
                    Badge(s.badge, f)
                    Text(s.label, color = if (f) Color.Black else VColor.Text, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    if (s.kind != "search" && s.kind != "back") Text(s.channels.size.toString(), color = if (f) Color.DarkGray else VColor.Faint, fontSize = 13.sp)
                }
            }
        }
        Box(Modifier.width(1.dp).fillMaxHeight().background(Color(0x14FFFFFF)))
        ChannelRows(app, selected, query, { query = it }, favoriteKeys, Modifier.weight(1f))
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
private fun ChannelRows(app: AppState, section: Section, query: String, onQuery: (String) -> Unit, favorites: Set<String>, modifier: Modifier) {
    val listState = rememberLazyListState()
    LaunchedEffect(section.id) { listState.scrollToItem(0) }
    Column(modifier.fillMaxHeight().padding(horizontal = 20.dp)) {
        Row(verticalAlignment = Alignment.Bottom, modifier = Modifier.padding(start = 8.dp, top = 4.dp, bottom = 8.dp)) {
            Text(if (section.kind == "search") "Search" else section.label, color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Spacer(Modifier.width(12.dp))
            Text("${section.channels.size} channels", color = VColor.Faint, fontSize = 14.sp, modifier = Modifier.padding(bottom = 4.dp))
        }
        if (section.kind == "search") {
            val focus = remember { FocusRequester() }
            OutlinedTextField(
                value = query, onValueChange = onQuery, singleLine = true, placeholder = { Text("Channel name") },
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search, autoCorrect = false),
                shape = RoundedCornerShape(30.dp), colors = fieldColors,
                modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp).focusRequester(focus)
            )
            LaunchedEffect(Unit) { delay(150); runCatching { focus.requestFocus() } }
        }
        if (section.channels.isEmpty()) {
            EmptyNote(when (section.id) {
                "favorites" -> "No favorites yet. Hold OK on a channel (or press the yellow / menu button) to add it."
                "recent" -> "Channels you watch will show up here."
                "search" -> if (query.isBlank()) "Type a channel name — results show while you type." else "Nothing found."
                "back" -> "Press OK to see all countries again."
                else -> "No channels here."
            })
            return@Column
        }
        LazyColumn(state = listState, contentPadding = PaddingValues(bottom = 32.dp)) {
            itemsIndexed(section.channels, key = { i, c -> "$i:" + c.key }) { i, c ->
                ChannelRow(app, c, i, favorites.contains(c.key)) { app.openPlayer(section.channels, i, section.label) }
            }
        }
    }
}

@Composable
private fun ChannelRow(app: AppState, c: Channel, index: Int, favorite: Boolean, onClick: () -> Unit) {
    val programmes = rememberProgrammes(app, c)
    val now = Epg.now(programmes)
    FocusRow(
        onClick = onClick, onLongClick = { app.toggleFavorite(c) },
        modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp).onPreviewKeyEvent { e ->
            val code = e.nativeKeyEvent.keyCode
            if (e.type == KeyEventType.KeyDown && (code == KeyEvent.KEYCODE_PROG_YELLOW || code == KeyEvent.KEYCODE_MENU)) {
                app.toggleFavorite(c); true
            } else false
        },
        radius = 16.dp, padding = PaddingValues(horizontal = 12.dp, vertical = 9.dp)
    ) { f ->
        Text((index + 1).toString(), color = if (f) Color.DarkGray else VColor.Faint, fontSize = 14.sp, modifier = Modifier.width(48.dp))
        ChannelLogo(c, 100.dp, 56.dp, f)
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) {
            Text(c.title, color = if (f) Color.Black else VColor.Text, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (now != null) {
                val left = ((now.end - System.currentTimeMillis()) / 60000).coerceAtLeast(1)
                Text("${now.title}  ·  $left min left", color = if (f) Color.DarkGray else VColor.Text.copy(alpha = 0.75f), fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(4.dp))
                Box(Modifier.width(260.dp)) { ProgressLine(now) }
            } else {
                Text(Names.title(c.category), color = if (f) Color.DarkGray else VColor.Faint, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (c.quality.isNotEmpty()) Text(c.quality, color = if (f) Color.Black else VColor.Faint, fontSize = 11.sp, fontWeight = FontWeight.Black, modifier = Modifier.padding(horizontal = 8.dp))
        if (favorite) Text("♥", color = VColor.Red, fontSize = 16.sp)
    }
}
