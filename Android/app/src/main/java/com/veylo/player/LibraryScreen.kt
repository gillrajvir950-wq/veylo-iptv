package com.veylo.player

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.SubcomposeAsyncImage
import kotlinx.coroutines.delay

/** Poster with title; a progress bar when started. */
@Composable
fun PosterCard(title: String, poster: String, meta: String, progress: Float?, onClick: () -> Unit, modifier: Modifier = Modifier) {
    FocusCard(onClick = onClick, modifier = modifier) { focused ->
        val shape = RoundedCornerShape(12.dp)
        Box(
            Modifier.fillMaxWidth().aspectRatio(2f / 3f).clip(shape).background(CardBrush)
                .border(if (focused) 3.dp else 1.dp, if (focused) Color.White else Color(0x1AFFFFFF), shape)
        ) {
            val name: @Composable () -> Unit = {
                Box(Modifier.fillMaxSize().padding(10.dp), contentAlignment = Alignment.Center) {
                    Text(title, color = Color(0xCCFFFFFF), fontSize = 14.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, maxLines = 4, overflow = TextOverflow.Ellipsis)
                }
            }
            if (poster.isNotEmpty()) {
                SubcomposeAsyncImage(model = poster, contentDescription = null, contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(), loading = { name() }, error = { name() })
            } else name()
            if (progress != null) {
                Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(4.dp).background(Color(0x66000000))) {
                    Box(Modifier.fillMaxWidth(progress).height(4.dp).background(VColor.Accent))
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (meta.isNotEmpty()) Text(meta, color = VColor.Faint, fontSize = 11.sp, maxLines = 1)
    }
}

fun metaOf(item: VodItem): String = listOfNotNull(
    item.year.ifEmpty { null },
    if (item.rating > 0) "★ " + String.format("%.1f", item.rating) else null
).joinToString("  ·  ")

private class LibSection(val id: String, val label: String, val items: List<VodItem>)

@Composable
fun LibraryScreen(app: AppState, kind: VodKind, wide: Boolean, bottomSpace: Int) {
    val session = app.session ?: return
    val noun = if (kind == VodKind.Movie) "Movies" else "Series"
    if (session.xtream == null) {
        Message(noun, "$noun need an Xtream login. This account is an M3U playlist — add the same provider as Xtream Codes in Settings to see $noun.")
        return
    }
    LaunchedEffect(kind, session) { app.loadLibrary(kind) }
    val state = app.libraries[kind]
    val lib = state?.lib
    if (lib == null) {
        if (state?.error != null) {
            Message(noun, "Couldn’t load $noun. ${state.error}", retry = { app.loadLibrary(kind, force = true) })
        } else {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator(color = Color.White, strokeWidth = 3.dp)
                    Spacer(Modifier.height(14.dp))
                    Text("Loading ${noun.lowercase()}… the first time can take a minute.", color = VColor.Faint, fontSize = 14.sp)
                }
            }
        }
        return
    }

    var selectedId by rememberSaveable(kind) { mutableStateOf("all") }
    var searching by rememberSaveable(kind) { mutableStateOf(false) }
    var query by rememberSaveable(kind) { mutableStateOf("") }
    val progress = remember(app.vodVersion, lib) { app.store.progressAll() }
    val progressById = remember(progress) {
        val map = HashMap<String, Float>()
        progress.forEach { p ->
            if (kind == VodKind.Movie && p.kind == "movie") map[p.id] = p.fraction
            if (kind == VodKind.Series && p.kind == "episode" && !map.containsKey(p.series)) map[p.series] = p.fraction
        }
        map
    }
    val sections: List<LibSection> = remember(lib, app.vodVersion, progress) {
        val started = progress.mapNotNull { p ->
            when {
                kind == VodKind.Movie && p.kind == "movie" -> lib.byId[p.id]
                kind == VodKind.Series && p.kind == "episode" -> lib.byId[p.series]
                else -> null
            }
        }.distinct()
        val mine = app.store.myList(kind).mapNotNull { lib.byId[it] }
        listOf(
            LibSection("all", "All $noun", lib.items),
            LibSection("continue", "Continue Watching", started),
            LibSection("mylist", "My List", mine),
            LibSection("recent", "Recently Added", lib.items.sortedByDescending { it.added }.take(120))
        ) + lib.categories.map { LibSection("c:" + it.id, Names.title(it.name), it.items) }
    }
    val selected = sections.firstOrNull { it.id == selectedId } ?: sections.first()
    val results = remember(query, lib) {
        val q = query.trim().lowercase()
        if (q.isEmpty()) emptyList() else lib.items.asSequence().filter { it.name.lowercase().contains(q) }.take(400).toList()
    }
    val showing = if (searching && query.isNotBlank()) results else selected.items
    val title = if (searching && query.isNotBlank()) "Search results" else selected.label
    val grid = rememberLazyGridState()
    LaunchedEffect(selected.id, query) { grid.scrollToItem(0) }
    androidx.activity.compose.BackHandler(enabled = searching) { searching = false; query = "" }

    val gridView: @Composable (Modifier) -> Unit = { mod ->
        Column(mod) {
            Row(Modifier.padding(horizontal = 20.dp, vertical = 6.dp), verticalAlignment = Alignment.Bottom) {
                Text(title, color = Color.White, fontSize = if (wide) 26.sp else 18.sp, fontWeight = FontWeight.Bold, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                Spacer(Modifier.width(8.dp))
                Text("${showing.size}", color = VColor.Faint, fontSize = 13.sp)
                if (state.loading) {
                    Spacer(Modifier.width(10.dp))
                    CircularProgressIndicator(color = VColor.Faint, strokeWidth = 2.dp, modifier = Modifier.size(14.dp))
                }
            }
            if (showing.isEmpty()) {
                Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) {
                    Text(when {
                        searching && query.isBlank() -> "Type a title."
                        searching -> "Nothing found for “$query”."
                        selected.id == "mylist" -> "Nothing in My List yet. Open a title and tap My List."
                        selected.id == "continue" -> "Titles you start watching show up here."
                        else -> "Nothing here."
                    }, color = VColor.Faint, fontSize = 15.sp, textAlign = TextAlign.Center)
                }
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(if (wide) 150.dp else 106.dp), state = grid,
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 6.dp, bottom = (bottomSpace + 16).dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    itemsIndexed(showing, key = { i, it -> "$i:" + it.id }) { _, item ->
                        PosterCard(item.title, item.poster, metaOf(item), progressById[item.id], onClick = { app.detail = item })
                    }
                }
            }
        }
    }

    val searchField: @Composable (Modifier) -> Unit = { mod ->
        val focus = remember { FocusRequester() }
        OutlinedTextField(
            value = query, onValueChange = { query = it }, singleLine = true, placeholder = { Text("Search ${noun.lowercase()}") },
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search, autoCorrect = false), shape = RoundedCornerShape(30.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = Color.White, unfocusedTextColor = VColor.Text, focusedBorderColor = VColor.Accent,
                unfocusedBorderColor = Color(0x33FFFFFF), cursorColor = Color.White,
                focusedContainerColor = Color(0x14FFFFFF), unfocusedContainerColor = Color(0x14FFFFFF)
            ),
            modifier = mod.focusRequester(focus)
        )
        LaunchedEffect(Unit) { delay(120); runCatching { focus.requestFocus() } }
    }

    if (wide) {
        Row(Modifier.fillMaxSize()) {
            LazyColumn(Modifier.width(300.dp).fillMaxHeight().padding(start = 20.dp), contentPadding = PaddingValues(top = 6.dp, bottom = 24.dp)) {
                item {
                    FocusRow(onClick = { searching = true; selectedId = "all" }, selected = searching, modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp)) { f ->
                        Icon(Icons.Filled.Search, contentDescription = null, tint = if (f) Color.Black else Color.White, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(12.dp))
                        Text(if (query.isBlank()) "Search" else "Search: $query", color = if (f) Color.Black else VColor.Text, fontSize = 16.sp, maxLines = 1)
                    }
                }
                itemsIndexed(sections, key = { _, s -> s.id }) { _, s ->
                    FocusRow(onClick = { searching = false; selectedId = s.id }, selected = !searching && s.id == selected.id,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp)) { f ->
                        Text(s.label, color = if (f) Color.Black else VColor.Text, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        Text("${s.items.size}", color = if (f) Color.DarkGray else VColor.Faint, fontSize = 13.sp)
                    }
                }
            }
            Box(Modifier.width(1.dp).fillMaxHeight().background(Color(0x14FFFFFF)))
            Column(Modifier.weight(1f)) {
                if (searching) searchField(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 6.dp))
                gridView(Modifier.fillMaxSize())
            }
        }
    } else {
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 12.dp, top = 10.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(noun, color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                FocusRow(onClick = { app.loadLibrary(kind, force = true) }, radius = 30.dp, padding = PaddingValues(10.dp)) { f ->
                    Icon(Icons.Filled.Refresh, contentDescription = "Reload", tint = if (f) Color.Black else Color.White)
                }
                FocusRow(onClick = { searching = !searching; if (!searching) query = "" }, radius = 30.dp, padding = PaddingValues(10.dp)) { f ->
                    Icon(if (searching) Icons.Filled.Close else Icons.Filled.Search, contentDescription = "Search", tint = if (f) Color.Black else Color.White)
                }
            }
            if (searching) {
                searchField(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp))
            } else {
                LazyRow(contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    itemsIndexed(sections, key = { _, s -> s.id }) { _, s ->
                        val active = s.id == selected.id
                        FocusRow(
                            onClick = { selectedId = s.id }, radius = 30.dp,
                            modifier = Modifier.clip(RoundedCornerShape(30.dp)).background(if (active) Color.White else Color(0x1AFFFFFF)),
                            padding = PaddingValues(horizontal = 15.dp, vertical = 8.dp)
                        ) { f ->
                            Text(s.label, color = if (active || f) Color.Black else Color.White, fontSize = 14.sp,
                                fontWeight = if (active) FontWeight.SemiBold else FontWeight.Medium, maxLines = 1)
                        }
                    }
                }
            }
            gridView(Modifier.weight(1f))
        }
    }
}

@Composable
private fun Message(title: String, text: String, retry: (() -> Unit)? = null) {
    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(title, color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(10.dp))
            Text(text, color = VColor.Faint, fontSize = 15.sp, textAlign = TextAlign.Center, lineHeight = 22.sp)
            if (retry != null) {
                Spacer(Modifier.height(16.dp))
                Pill("Try again", retry, primary = true)
            }
        }
    }
}
