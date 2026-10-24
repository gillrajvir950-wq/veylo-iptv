package com.veylo.player

import androidx.compose.foundation.ExperimentalFoundationApi
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlinx.coroutines.delay

/** One big card at the top of Home: something to continue, or a channel to watch. */
private class Feature(
    val key: String, val label: String, val title: String, val subtitle: String,
    val poster: String, val channel: Channel?, val progress: Float?, val onPlay: () -> Unit
)

/** Home: a featured carousel, then rows — continue watching, your channels, new movies and series,
 *  and a few categories of the country you watch. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun HomeScreen(app: AppState, wide: Boolean, bottomSpace: Int) {
    val session = app.session ?: return
    val favorites = remember(app.listsVersion, session) { app.store.favorites().mapNotNull { session.byKey[it] } }
    val favoriteKeys = remember(favorites) { favorites.map { it.key }.toHashSet() }
    val recents = remember(app.listsVersion, session) { app.store.recents().mapNotNull { session.byKey[it] } }
    val started = remember(app.vodVersion, session) { app.store.progressAll().take(20) }
    val movies = app.libraries[VodKind.Movie]?.lib
    val seriesLib = app.libraries[VodKind.Series]?.lib
    val shelves: List<Category> = remember(session, recents.firstOrNull()) {
        val last = recents.firstOrNull()
        val country = session.countries?.let { list ->
            list.firstOrNull { c -> last != null && c.code != "OTHER" && c.categories.any { it.name == last.category } } ?: list.firstOrNull { it.code != "OTHER" }
        }
        (country?.categories ?: session.categories).filter { it.channels.isNotEmpty() }.take(6)
    }

    val features: List<Feature> = remember(started, recents, shelves) {
        val list = ArrayList<Feature>()
        started.take(3).forEach { p ->
            val left = if (p.dur > 0) ((p.dur - p.pos) / 60).coerceAtLeast(1) else 0
            list.add(Feature("p:" + p.key, "CONTINUE WATCHING", p.title,
                listOfNotNull(p.label.ifEmpty { null }, if (left > 0) "$left min left" else null).joinToString("  ·  "),
                p.poster, null, p.fraction) { openProgress(app, p) })
        }
        recents.take(2).forEach { c ->
            list.add(Feature("c:" + c.key, "WATCH AGAIN", c.title, Names.title(c.category), "", c, null) {
                app.openPlayer(recents, recents.indexOf(c).coerceAtLeast(0), "Recently watched")
            })
        }
        if (list.isEmpty()) shelves.firstOrNull()?.let { cat ->
            cat.channels.take(3).forEach { c ->
                list.add(Feature("c:" + c.key, "LIVE NOW", c.title, Names.title(cat.name), "", c, null) {
                    app.openPlayer(cat.channels, cat.channels.indexOf(c).coerceAtLeast(0), Names.title(cat.name))
                })
            }
        }
        list
    }

    val side = if (wide) 40.dp else 18.dp
    val tileWidth = if (wide) 220.dp else 140.dp
    val posterWidth = if (wide) 150.dp else 112.dp
    val heroFocus = remember { FocusRequester() }
    val tv = isTv(app)
    LaunchedEffect(Unit) { if (tv) { delay(200); runCatching { heroFocus.requestFocus() } } }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = (bottomSpace + 24).dp)) {
        if (!wide) {
            item {
                Row(Modifier.fillMaxWidth().padding(horizontal = side, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    BrandMark(32)
                    Spacer(Modifier.weight(1f))
                    Text(session.provider.name, color = Color(0xCCFFFFFF), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1,
                        modifier = Modifier.clip(RoundedCornerShape(30.dp)).background(Color(0x1FFFFFFF)).padding(horizontal = 12.dp, vertical = 6.dp))
                }
            }
        }

        // Featured carousel (phones: swipe; TV: the first card, focusable).
        if (features.isNotEmpty()) item {
            if (wide) {
                Row(Modifier.padding(horizontal = side, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    features.take(3).forEachIndexed { i, f ->
                        HeroCard(app, f, Modifier.weight(1f), if (i == 0) heroFocus else null, height = 240.dp)
                    }
                }
            } else {
                val pager = rememberPagerState(pageCount = { features.size })
                LaunchedEffect(features.size) {
                    while (features.size > 1) {
                        delay(6000)
                        runCatching { pager.animateScrollToPage((pager.currentPage + 1) % features.size) }
                    }
                }
                Column {
                    HorizontalPager(state = pager, contentPadding = PaddingValues(horizontal = side), pageSpacing = 12.dp,
                        modifier = Modifier.padding(top = 6.dp)) { page ->
                        HeroCard(app, features[page], Modifier.fillMaxWidth(), null, height = 210.dp)
                    }
                    if (features.size > 1) {
                        Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.Center) {
                            repeat(features.size) { i ->
                                Box(Modifier.padding(horizontal = 3.dp).size(if (i == pager.currentPage) 18.dp else 6.dp, 6.dp)
                                    .clip(CircleShape).background(if (i == pager.currentPage) Color.White else Color(0x55FFFFFF)))
                            }
                        }
                    }
                }
            }
        }

        if (started.isNotEmpty()) item {
            PosterShelf("Continue watching", started.map { p ->
                PosterEntry(p.key, p.title, p.poster, if (p.kind == "episode") p.label else "", p.fraction) { openProgress(app, p) }
            }, posterWidth, side)
        }
        if (recents.isNotEmpty()) item { ChannelShelf(app, "Recently watched", recents, favoriteKeys, tileWidth, side, showNow = true) }
        if (favorites.isNotEmpty()) item { ChannelShelf(app, "Your favorites", favorites, favoriteKeys, tileWidth, side, showNow = true) }
        movies?.let { lib ->
            item(key = "new-movies") {
                PosterShelf("New movies", lib.items.sortedByDescending { it.added }.take(24).map { m ->
                    PosterEntry(m.key, m.title, m.poster, metaOf(m), null) { app.detail = m }
                }, posterWidth, side, onMore = { app.tab = Tab.Movies })
            }
        }
        seriesLib?.let { lib ->
            item(key = "new-series") {
                PosterShelf("New series", lib.items.sortedByDescending { it.added }.take(24).map { m ->
                    PosterEntry(m.key, m.title, m.poster, metaOf(m), null) { app.detail = m }
                }, posterWidth, side, onMore = { app.tab = Tab.Series })
            }
        }
        shelves.forEach { cat ->
            item(key = "cat:" + cat.name) {
                ChannelShelf(app, Names.title(cat.name), cat.channels, favoriteKeys, tileWidth, side, showNow = false,
                    onMore = { app.tab = Tab.Live })
            }
        }
    }
}

@Composable
private fun HeroCard(app: AppState, f: Feature, modifier: Modifier, focus: FocusRequester?, height: Dp) {
    val programmes = if (f.channel != null) rememberProgrammes(app, f.channel, 0) else null
    val now = Epg.now(programmes)
    val shape = RoundedCornerShape(22.dp)
    FocusCard(onClick = f.onPlay, modifier = modifier.then(if (focus != null) Modifier.focusRequester(focus) else Modifier)) { focused ->
        Box(
            Modifier.fillMaxWidth().height(height).clip(shape)
                .background(Brush.linearGradient(listOf(Color(0xFF3A1E78), Color(0xFF1A1630), Color(0xFF0E0D14))))
                .border(if (focused) 3.dp else 1.dp, if (focused) Color.White else Color(0x22FFFFFF), shape)
        ) {
            if (f.poster.isNotEmpty()) {
                AsyncImage(model = f.poster, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            } else if (f.channel != null) {
                Box(Modifier.align(Alignment.TopCenter).padding(top = 20.dp).width(height * 0.72f)) {
                    ChannelArt(f.channel, false, false, nameSize = 18)
                }
            }
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.35f to Color.Transparent, 1f to Color(0xF2000000))))
            Column(Modifier.align(Alignment.BottomStart).padding(start = 18.dp, top = 18.dp, bottom = 18.dp, end = 112.dp)) {
                Text(f.label, color = VColor.Accent, fontSize = 11.sp, fontWeight = FontWeight.Black, letterSpacing = 1.2.sp)
                Text(f.title, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                val sub = if (now != null) "Now: ${now.title}" else f.subtitle
                if (sub.isNotEmpty()) Text(sub, color = Color(0xCCFFFFFF), fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                val bar = f.progress ?: now?.let { p ->
                    val t = System.currentTimeMillis()
                    if (p.end > p.start) ((t - p.start).toFloat() / (p.end - p.start)).coerceIn(0f, 1f) else null
                }
                if (bar != null) {
                    Spacer(Modifier.height(8.dp))
                    Box(Modifier.width(180.dp).height(4.dp).clip(RoundedCornerShape(2.dp)).background(Color(0x44FFFFFF))) {
                        Box(Modifier.fillMaxWidth(bar).height(4.dp).background(VColor.Accent))
                    }
                }
            }
            Row(
                Modifier.align(Alignment.BottomEnd).padding(18.dp).clip(RoundedCornerShape(30.dp)).background(Color.White)
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                GlyphIcon(Glyph.Play, Color.Black, 14.dp)
                Spacer(Modifier.width(6.dp))
                Text(if (f.progress != null) "Resume" else "Play", color = Color.Black, fontSize = 14.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun ShelfHeader(title: String, side: Dp, onMore: (() -> Unit)?) {
    Row(Modifier.fillMaxWidth().padding(start = side, end = side - 6.dp, top = 22.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (onMore != null) {
            FocusRow(onClick = onMore, radius = 20.dp, padding = PaddingValues(horizontal = 10.dp, vertical = 4.dp)) { f ->
                Text("See all ›", color = if (f) Color.Black else VColor.Faint, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun ChannelShelf(app: AppState, title: String, channels: List<Channel>, favorites: Set<String>, tileWidth: Dp, side: Dp,
                         showNow: Boolean, onMore: (() -> Unit)? = null) {
    Column {
        ShelfHeader(title, side, onMore)
        LazyRow(contentPadding = PaddingValues(horizontal = side, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            itemsIndexed(channels.take(24), key = { i, c -> "$i:" + c.key }) { _, c ->
                ChannelTile(app, c, favorites.contains(c.key), onClick = {
                    app.openPlayer(channels, channels.indexOf(c).coerceAtLeast(0), title)
                }, modifier = Modifier.width(tileWidth), showNow = showNow)
            }
        }
    }
}

class PosterEntry(val key: String, val title: String, val poster: String, val meta: String, val progress: Float?, val onClick: () -> Unit)

@Composable
private fun PosterShelf(title: String, entries: List<PosterEntry>, width: Dp, side: Dp, onMore: (() -> Unit)? = null) {
    if (entries.isEmpty()) return
    Column {
        ShelfHeader(title, side, onMore)
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
