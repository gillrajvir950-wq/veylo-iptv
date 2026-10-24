package com.veylo.player

import android.content.pm.PackageManager
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.SubcomposeAsyncImage

/** Android TV / box (remote, no touch). */
@Composable
fun isTv(app: AppState? = null): Boolean {
    val context = LocalContext.current
    return remember { context.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) }
}

/** Black with soft violet / blue light, like the iPhone app. */
@Composable
fun Backdrop(content: @Composable BoxScope.() -> Unit) {
    Box(
        Modifier.fillMaxSize().background(VColor.Bg).drawBehind {
            drawRect(Brush.radialGradient(
                listOf(Color(0x664C1D95), Color.Transparent),
                center = Offset(size.width * 0.1f, 0f), radius = size.width * 0.9f
            ))
            drawRect(Brush.radialGradient(
                listOf(Color(0x331D4ED8), Color.Transparent),
                center = Offset(size.width * 0.95f, size.height * 0.35f), radius = size.width * 0.7f
            ))
        },
        content = content
    )
}

val CardBrush = Brush.linearGradient(listOf(Color(0xFF26222F), Color(0xFF17151D)))

/** A card that grows and gets a white ring when the remote focuses it. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun FocusCard(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onLongClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.(focused: Boolean) -> Unit
) {
    val source = remember { MutableInteractionSource() }
    val focused by source.collectIsFocusedAsState()
    val scale by animateFloatAsState(if (focused) 1.06f else 1f, label = "focus")
    Column(
        modifier
            .graphicsLayer { scaleX = scale; scaleY = scale }
            .combinedClickable(interactionSource = source, indication = null, onLongClick = onLongClick, onClick = onClick)
    ) { content(focused) }
}

/** Logo on a dark 16:9 card, quality badge, favorite heart. */
@Composable
fun ChannelArt(channel: Channel, focused: Boolean, favorite: Boolean, modifier: Modifier = Modifier, nameSize: Int = 15) {
    val shape = RoundedCornerShape(16.dp)
    Box(
        modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(shape).background(CardBrush)
            .then(if (focused) Modifier.border(3.dp, Color.White, shape) else Modifier.border(1.dp, Color(0x1FFFFFFF), shape)),
        contentAlignment = Alignment.Center
    ) {
        val name: @Composable () -> Unit = {
            Text(channel.title, color = Color.White.copy(alpha = 0.85f), fontSize = nameSize.sp, fontWeight = FontWeight.Bold,
                maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center, modifier = Modifier.padding(10.dp))
        }
        if (channel.logo.startsWith("http")) {
            SubcomposeAsyncImage(
                model = channel.logo, contentDescription = null, contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxSize().padding(horizontal = 22.dp, vertical = 16.dp),
                loading = { name() }, error = { name() }
            )
        } else name()
        Row(Modifier.align(Alignment.TopEnd).padding(7.dp)) {
            if (channel.quality.isNotEmpty()) {
                Text(channel.quality, color = Color.Black, fontSize = 9.sp, fontWeight = FontWeight.Black,
                    modifier = Modifier.clip(RoundedCornerShape(4.dp)).background(Color(0xE6FFFFFF)).padding(horizontal = 5.dp, vertical = 1.dp))
            }
            if (favorite) {
                Spacer(Modifier.width(5.dp))
                Box(Modifier.size(18.dp).clip(CircleShape).background(Color(0xCCFF2D55)), contentAlignment = Alignment.Center) {
                    Text("♥", color = Color.White, fontSize = 10.sp)
                }
            }
        }
    }
}

/** Channel tile: card + name + what's on now. */
@Composable
fun ChannelTile(app: AppState, channel: Channel, favorite: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier, showNow: Boolean = true) {
    val programmes = if (showNow) rememberProgrammes(app, channel) else null
    val now = Epg.now(programmes)
    FocusCard(onClick = onClick, onLongClick = { app.toggleFavorite(channel) }, modifier = modifier) { focused ->
        ChannelArt(channel, focused, favorite)
        Spacer(Modifier.height(8.dp))
        Text(channel.title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        // Fixed height below the name, so every tile in a row lines up (with or without a programme).
        Text(
            now?.title ?: Names.title(channel.category), color = if (now != null) VColor.Text.copy(alpha = 0.7f) else VColor.Faint,
            fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis
        )
        Spacer(Modifier.height(5.dp))
        if (now != null) ProgressLine(now) else Spacer(Modifier.height(3.dp))
    }
}

@Composable
fun ProgressLine(p: Programme, modifier: Modifier = Modifier) {
    val t = System.currentTimeMillis()
    val f = if (p.end > p.start) ((t - p.start).toFloat() / (p.end - p.start)).coerceIn(0f, 1f) else 0f
    Box(modifier.fillMaxWidth().height(3.dp).clip(RoundedCornerShape(2.dp)).background(Color(0x33FFFFFF))) {
        Box(Modifier.fillMaxWidth(f).height(3.dp).background(VColor.Accent))
    }
}

@Composable
fun LiveBadge() {
    Row(
        Modifier.clip(RoundedCornerShape(20.dp)).background(VColor.Red).padding(horizontal = 8.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(6.dp).clip(CircleShape).background(Color.White))
        Spacer(Modifier.width(5.dp))
        Text("LIVE", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
    }
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier, trailing: String? = null) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Text(text, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        if (trailing != null) {
            Spacer(Modifier.width(8.dp))
            Text(trailing, color = VColor.Faint, fontSize = 13.sp)
        }
    }
}
