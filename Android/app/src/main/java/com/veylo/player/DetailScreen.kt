package com.veylo.player

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlinx.coroutines.delay

private fun minutes(seconds: Long): String {
    if (seconds <= 0) return ""
    val h = seconds / 3600
    val m = (seconds % 3600) / 60
    return if (h > 0) "${h}h ${m}m" else "${m} min"
}

/** Movie or series page: backdrop, play / resume, My List, plot, seasons and episodes. */
@Composable
fun DetailScreen(app: AppState, item: VodItem, wide: Boolean) {
    val x = app.session?.xtream ?: return
    BackHandler { app.detail = null }
    var movie by remember(item.key) { mutableStateOf<MovieInfo?>(null) }
    var series by remember(item.key) { mutableStateOf<SeriesInfo?>(null) }
    var error by remember(item.key) { mutableStateOf<String?>(null) }
    var seasonIndex by remember(item.key) { mutableStateOf(-1) }
    LaunchedEffect(item.key) {
        try {
            if (item.kind == VodKind.Movie) movie = Vod.movieInfo(x, item.id) else series = Vod.seriesInfo(x, item.id)
        } catch (e: Exception) {
            error = Repo.friendly(e)
        }
    }
    val progressList = remember(app.vodVersion, item.key) { app.store.progressAll() }
    val inList = remember(app.vodVersion, item.key) { app.store.myList(item.kind).contains(item.id) }
    val playFocus = remember { FocusRequester() }
    val tv = isTv(app)
    LaunchedEffect(item.key) { if (tv) { delay(250); runCatching { playFocus.requestFocus() } } }

    val backdrop = movie?.backdrop?.ifEmpty { null } ?: series?.backdrop?.ifEmpty { null } ?: ""
    val poster = item.poster.ifEmpty { movie?.poster ?: series?.poster ?: "" }
    val plot = (movie?.plot ?: series?.plot ?: "").ifEmpty { item.plot }
    val genre = (movie?.genre ?: series?.genre ?: "").ifEmpty { item.genre }
    val year = item.year.ifEmpty { movie?.year ?: series?.year ?: "" }
    val rating = if (item.rating > 0) item.rating else (movie?.rating ?: series?.rating ?: 0.0)

    // Movies: resume point. Series: the episode watched last.
    val movieProgress = if (item.kind == VodKind.Movie) progressList.firstOrNull { it.kind == "movie" && it.id == item.id } else null
    val lastEpisode = if (item.kind == VodKind.Series) progressList.firstOrNull { it.kind == "episode" && it.series == item.id } else null
    val seasons = series?.seasons ?: emptyList()
    val currentSeason = when {
        seasons.isEmpty() -> null
        seasonIndex in seasons.indices -> seasons[seasonIndex]
        lastEpisode != null -> seasons.firstOrNull { s -> s.episodes.any { it.id == lastEpisode.id } } ?: seasons.first()
        else -> seasons.first()
    }

    fun playMovie(from: Long) {
        val info = movie
        app.openVod(VodRequest(
            url = Vod.movieUrl(x, item, info?.ext?.ifEmpty { item.ext } ?: item.ext), title = item.title,
            subtitle = listOfNotNull(year.ifEmpty { null }, genre.ifEmpty { null }).joinToString("  ·  "),
            key = "v:" + item.id, startAt = from, poster = poster, kind = "movie", id = item.id, ext = item.ext
        ))
    }

    fun playEpisode(season: Season, ep: Episode, from: Long) {
        val all = seasons.flatMap { it.episodes }
        app.openVod(VodRequest(
            url = Vod.episodeUrl(x, ep), title = item.title, subtitle = "S${season.number} · E${ep.number}  ${ep.title}",
            key = ep.key, startAt = from, poster = poster, kind = "episode", id = ep.id, ext = ep.ext,
            series = item, episodes = all, episodeIndex = all.indexOf(ep)
        ))
    }

    Box(Modifier.fillMaxSize().background(VColor.Bg)) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 40.dp)) {
            item {
                Box(Modifier.fillMaxWidth().height(if (wide) 420.dp else 300.dp)) {
                    val hero = backdrop.ifEmpty { poster }
                    if (hero.isNotEmpty()) {
                        AsyncImage(model = hero, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                    }
                    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0x66000000), Color(0x33000000), VColor.Bg))))
                    Row(Modifier.align(Alignment.BottomStart).padding(horizontal = 20.dp, vertical = 8.dp), verticalAlignment = Alignment.Bottom) {
                        if (poster.isNotEmpty()) {
                            AsyncImage(model = poster, contentDescription = null, contentScale = ContentScale.Crop,
                                modifier = Modifier.width(if (wide) 150.dp else 104.dp).aspectRatio(2f / 3f).clip(RoundedCornerShape(12.dp))
                                    .border(1.dp, Color(0x33FFFFFF), RoundedCornerShape(12.dp)))
                            Spacer(Modifier.width(16.dp))
                        }
                        Column {
                            Text(item.title, color = Color.White, fontSize = if (wide) 34.sp else 24.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            val meta = listOfNotNull(
                                year.ifEmpty { null }, genre.ifEmpty { null },
                                if (rating > 0) "★ " + String.format("%.1f", rating) else null,
                                movie?.duration?.let { minutes(it).ifEmpty { null } },
                                if (seasons.isNotEmpty()) "${seasons.size} season${if (seasons.size == 1) "" else "s"}" else null
                            ).joinToString("  ·  ")
                            if (meta.isNotEmpty()) Text(meta, color = Color(0xCCFFFFFF), fontSize = 13.sp, maxLines = 2)
                        }
                    }
                    Box(Modifier.statusBarsPadding().padding(12.dp)) {
                        FocusRow(onClick = { app.detail = null }, radius = 30.dp, padding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
                            modifier = Modifier.clip(RoundedCornerShape(30.dp)).background(Color(0x66000000))) { f ->
                            Text("‹  Back", color = if (f) Color.Black else Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }
            item {
                Row(Modifier.padding(horizontal = 20.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (item.kind == VodKind.Movie) {
                        if (movieProgress != null && movieProgress.pos > 0) {
                            Pill("▶  Resume · ${minutes(movieProgress.dur - movieProgress.pos)} left", { playMovie(movieProgress.pos) }, primary = true, focusRequester = playFocus)
                            Pill("From start", { playMovie(0) })
                        } else {
                            Pill("▶  Play", { playMovie(0) }, primary = true, focusRequester = playFocus)
                        }
                    } else {
                        val season = currentSeason
                        val ep = lastEpisode?.let { p -> seasons.flatMap { it.episodes }.firstOrNull { it.id == p.id } }
                        if (ep != null && lastEpisode != null) {
                            val s = seasons.first { it.episodes.contains(ep) }
                            Pill("▶  Resume S${s.number} · E${ep.number}", { playEpisode(s, ep, lastEpisode.pos) }, primary = true, focusRequester = playFocus)
                        } else if (season != null && season.episodes.isNotEmpty()) {
                            Pill("▶  Play S${season.number} · E${season.episodes.first().number}", { playEpisode(season, season.episodes.first(), 0) }, primary = true, focusRequester = playFocus)
                        }
                    }
                    Pill(if (inList) "✓  My List" else "+  My List", {
                        val added = app.store.toggleMyList(item.kind, item.id)
                        app.vodVersion += 1
                        app.showToast(if (added) "Added to My List" else "Removed from My List")
                    })
                }
                if (movieProgress != null) {
                    Box(Modifier.padding(horizontal = 20.dp).widthIn(max = 420.dp).fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp)).background(Color(0x33FFFFFF))) {
                        Box(Modifier.fillMaxWidth(movieProgress.fraction).height(4.dp).background(VColor.Accent))
                    }
                }
            }
            if (plot.isNotEmpty()) item {
                Text(plot, color = VColor.Text.copy(alpha = 0.85f), fontSize = 15.sp, lineHeight = 22.sp,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp).widthIn(max = 820.dp))
            }
            val cast = movie?.cast ?: series?.cast ?: ""
            if (cast.isNotEmpty()) item { InfoLine("Cast", cast) }
            val director = movie?.director ?: ""
            if (director.isNotEmpty()) item { InfoLine("Director", director) }
            if (error != null) item {
                Text("Couldn’t load the details. $error", color = VColor.Yellow, fontSize = 14.sp, modifier = Modifier.padding(20.dp))
            }
            if (item.kind == VodKind.Series && series == null && error == null) item {
                Box(Modifier.fillMaxWidth().padding(30.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Color.White, strokeWidth = 3.dp) }
            }
            if (seasons.isNotEmpty() && currentSeason != null) {
                item {
                    LazyRow(contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        itemsIndexed(seasons, key = { _, s -> s.number }) { i, s ->
                            val active = s === currentSeason
                            FocusRow(onClick = { seasonIndex = i }, radius = 30.dp,
                                modifier = Modifier.clip(RoundedCornerShape(30.dp)).background(if (active) Color.White else Color(0x1AFFFFFF)),
                                padding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)) { f ->
                                Text("Season ${s.number}", color = if (active || f) Color.Black else Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                }
                itemsIndexed(currentSeason.episodes, key = { _, e -> e.id }) { _, ep ->
                    val p = progressList.firstOrNull { it.kind == "episode" && it.id == ep.id }
                    FocusRow(onClick = { playEpisode(currentSeason, ep, p?.pos ?: 0) }, radius = 14.dp,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 3.dp),
                        padding = PaddingValues(horizontal = 8.dp, vertical = 8.dp)) { f ->
                        Box(Modifier.width(if (wide) 180.dp else 132.dp).aspectRatio(16f / 9f).clip(RoundedCornerShape(10.dp)).background(CardBrush)) {
                            val img = ep.image.ifEmpty { backdrop }
                            if (img.isNotEmpty()) AsyncImage(model = img, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                            Text("${ep.number}", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Black,
                                modifier = Modifier.align(Alignment.BottomStart).padding(6.dp).clip(RoundedCornerShape(4.dp)).background(Color(0x99000000)).padding(horizontal = 6.dp, vertical = 1.dp))
                            if (p != null) Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(3.dp).background(Color(0x66000000))) {
                                Box(Modifier.fillMaxWidth(p.fraction).height(3.dp).background(VColor.Accent))
                            }
                        }
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f)) {
                            Text(ep.title, color = if (f) Color.Black else Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            val d = minutes(ep.duration)
                            if (d.isNotEmpty()) Text(d, color = if (f) Color.DarkGray else VColor.Faint, fontSize = 12.sp)
                            if (ep.plot.isNotEmpty()) Text(ep.plot, color = if (f) Color.DarkGray else VColor.Faint, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun InfoLine(label: String, value: String) {
    Row(Modifier.padding(horizontal = 20.dp, vertical = 4.dp).widthIn(max = 820.dp)) {
        Text(label, color = VColor.Faint, fontSize = 13.sp, modifier = Modifier.width(80.dp))
        Text(value, color = VColor.Text, fontSize = 13.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
    }
}
