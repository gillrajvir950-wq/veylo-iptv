package com.veylo.player

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import java.util.Calendar

/** Home: continue watching, recently watched, favorites, and the categories of the country
 *  you watch most. */
@Composable
fun HomeScreen(app: AppState, wide: Boolean, bottomSpace: Int) {
    val session = app.session ?: return
    val favorites = remember(app.listsVersion, session) { app.store.favorites().mapNotNull { session.byKey[it] } }
    val favoriteKeys = remember(favorites) { favorites.map { it.key }.toHashSet() }
    val recents = remember(app.listsVersion, session) { app.store.recents().mapNotNull { session.byKey[it] } }
    val shelves: List<Category> = remember(session, recents.firstOrNull()) {
        val last = recents.firstOrNull()
        val country = session.countries?.let { list ->
            list.firstOrNull { c -> last != null && c.code != "OTHER" && c.categories.any { it.name == last.category } } ?: list.firstOrNull { it.code != "OTHER" }
        }
        (country?.categories ?: session.categories).filter { it.channels.isNotEmpty() }.take(10)
    }
    val tileWidth = if (wide) 236.dp else 158.dp
    val posterWidth = if (wide) 150.dp else 112.dp
    val started = remember(app.vodVersion, session) { app.store.progressAll().take(20) }
    val movies = app.libraries[VodKind.Movie]?.lib
    val seriesLib = app.libraries[VodKind.Series]?.lib
    val side = if (wide) 40.dp else 20.dp
    val heroFocus = remember { FocusRequester() }
    val tv = isTv(app)
    LaunchedEffect(Unit) { if (tv) { delay(200); runCatching { heroFocus.requestFocus() } } }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = (bottomSpace + 24).dp)) {
        if (!wide) {
            item {
                Row(Modifier.fillMaxWidth().padding(horizontal = side, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    BrandMark(34)
                    Spacer(Modifier.weight(1f))
                    Text(session.provider.name, color = VColor.Faint, fontSize = 13.sp, maxLines = 1)
                }
            }
        }
        item {
            Column(Modifier.padding(horizontal = side, vertical = 8.dp)) {
                Text(greeting(), color = Color.White, fontSize = if (wide) 34.sp else 28.sp, fontWeight = FontWeight.Bold)
                Text("${session.channels.size} live channels", color = VColor.Faint, fontSize = 14.sp)
            }
        }
        val hero = recents.firstOrNull() ?: shelves.firstOrNull()?.channels?.firstOrNull()
        if (hero != null) {
            item {
                val lineup = if (recents.isNotEmpty()) recents else shelves.first().channels
                Hero(app, hero, if (recents.isNotEmpty()) "CONTINUE WATCHING" else "LIVE NOW", wide, side, heroFocus) {
                    app.openPlayer(lineup, lineup.indexOf(hero).coerceAtLeast(0), if (recents.isNotEmpty()) "Recently watched" else Names.title(shelves.first().name))
                }
            }
        }
        if (recents.size > 1) item { Shelf(app, "Recently watched", recents, favoriteKeys, tileWidth, side) }
        if (favorites.isNotEmpty()) item { Shelf(app, "Favorites", favorites, favoriteKeys, tileWidth, side) }
        if (started.isNotEmpty()) item {
            PosterShelf("Continue watching", started.map { p ->
                PosterEntry(p.key, p.title, p.poster, if (p.kind == "episode") p.label else "", p.fraction) { openProgress(app, p) }
            }, posterWidth, side)
        }
        movies?.let { lib ->
            item(key = "new-movies") {
                PosterShelf("Recently added movies", lib.items.sortedByDescending { it.added }.take(24).map { m ->
                    PosterEntry(m.key, m.title, m.poster, metaOf(m), null) { app.detail = m }
                }, posterWidth, side)
            }
        }
        seriesLib?.let { lib ->
            item(key = "new-series") {
                PosterShelf("Recently added series", lib.items.sortedByDescending { it.added }.take(24).map { m ->
                    PosterEntry(m.key, m.title, m.poster, metaOf(m), null) { app.detail = m }
                }, posterWidth, side)
            }
        }
        shelves.forEach { cat ->
            item(key = "cat:" + cat.name) { Shelf(app, Names.title(cat.name), cat.channels, favoriteKeys, tileWidth, side, cat.channels.size) }
        }
    }
}

private fun greeting(): String {
    val h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
    return when {
        h < 5 -> "Good night"
        h < 12 -> "Good morning"
        h < 17 -> "Good afternoon"
        else -> "Good evening"
    }
}

@Composable
private fun Hero(app: AppState, channel: Channel, label: String, wide: Boolean, side: androidx.compose.ui.unit.Dp,
                 focus: FocusRequester, onPlay: () -> Unit) {
    val programmes = rememberProgrammes(app, channel, 0)
    val now = Epg.now(programmes)
    FocusRow(
        onClick = onPlay, focusRequester = focus, radius = 24.dp, padding = PaddingValues(0.dp),
        modifier = Modifier.padding(horizontal = side, vertical = 12.dp).fillMaxWidth(if (wide) 0.62f else 1f)
    ) { focused ->
        Box(
            Modifier.fillMaxWidth().height(if (wide) 260.dp else 210.dp).clip(RoundedCornerShape(24.dp))
                .background(Brush.linearGradient(listOf(Color(0xFF3B1F7A), Color(0xFF15121D))))
                .border(if (focused) 3.dp else 1.dp, if (focused) Color.White else Color(0x22FFFFFF), RoundedCornerShape(24.dp))
        ) {
            Box(Modifier.align(Alignment.TopEnd).padding(22.dp).width(if (wide) 220.dp else 140.dp)) {
                ChannelArt(channel, false, false, nameSize = 18)
            }
            Column(Modifier.align(Alignment.BottomStart).padding(22.dp)) {
                Text(label, color = Color(0xB3FFFFFF), fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp)
                Spacer(Modifier.height(4.dp))
                Text(channel.title, color = Color.White, fontSize = if (wide) 30.sp else 24.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (now != null) {
                    Text("Now: ${now.title}", color = Color(0xCCFFFFFF), fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Spacer(Modifier.height(6.dp))
                    Box(Modifier.width(200.dp)) { ProgressLine(now) }
                }
                Spacer(Modifier.height(12.dp))
                Row(
                    Modifier.clip(RoundedCornerShape(30.dp)).background(Color.White).padding(horizontal = 20.dp, vertical = 9.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("▶  Play", color = Color.Black, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun Shelf(app: AppState, title: String, channels: List<Channel>, favorites: Set<String>,
                  tileWidth: androidx.compose.ui.unit.Dp, side: androidx.compose.ui.unit.Dp, total: Int? = null) {
    Column(Modifier.padding(top = 18.dp)) {
        SectionTitle(title, Modifier.padding(horizontal = side, vertical = 6.dp), trailing = total?.let { "$it" })
        LazyRow(contentPadding = PaddingValues(horizontal = side, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            itemsIndexed(channels.take(24), key = { i, c -> "$i:" + c.key }) { _, c ->
                ChannelTile(app, c, favorites.contains(c.key), onClick = {
                    app.openPlayer(channels, channels.indexOf(c).coerceAtLeast(0), title)
                }, modifier = Modifier.width(tileWidth))
            }
        }
    }
}

class PosterEntry(val key: String, val title: String, val poster: String, val meta: String, val progress: Float?, val onClick: () -> Unit)

@Composable
private fun PosterShelf(title: String, entries: List<PosterEntry>, width: androidx.compose.ui.unit.Dp, side: androidx.compose.ui.unit.Dp) {
    if (entries.isEmpty()) return
    Column(Modifier.padding(top = 18.dp)) {
        SectionTitle(title, Modifier.padding(horizontal = side, vertical = 6.dp))
        LazyRow(contentPadding = PaddingValues(horizontal = side, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            itemsIndexed(entries, key = { i, e -> "$i:" + e.key }) { _, e ->
                PosterCard(e.title, e.poster, e.meta, e.progress, onClick = e.onClick, modifier = Modifier.width(width))
            }
        }
    }
}

/** Continue watching: open the movie or series page (the saved entry has enough to show it). */
fun openProgress(app: AppState, p: Store.Progress) {
    val movie = p.kind == "movie"
    val kind = if (movie) VodKind.Movie else VodKind.Series
    val id = if (movie) p.id else p.series
    if (id.isEmpty()) return
    val known = app.libraries[kind]?.lib?.byId?.get(id)
    app.detail = known ?: VodItem(kind, id, p.title, p.title, "", 0.0, p.poster, "", "", 0, p.ext.ifEmpty { "mp4" }, "")
}
