package com.veylo.player

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.SubcomposeAsyncImage

object VColor {
    val Bg = Color(0xFF07060C)
    val Panel = Color(0xFF15131D)
    val Line = Color(0xFF2A2634)
    val Accent = Color(0xFF8B5CF6)
    val Faint = Color(0xFF8E8A99)
    val Text = Color(0xFFF4F2F8)
    val Red = Color(0xFFFF3B30)
    val Yellow = Color(0xFFFFD60A)
}

/** A row that works with the remote (D-pad focus → white highlight) and with touch.
 *  `content` gets `focused` so text can turn dark on the white highlight. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun FocusRow(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onLongClick: (() -> Unit)? = null,
    selected: Boolean = false,
    focusRequester: FocusRequester? = null,
    radius: Dp = 14.dp,
    padding: PaddingValues = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
    content: @Composable RowScope.(focused: Boolean) -> Unit
) {
    val source = remember { MutableInteractionSource() }
    val focused by source.collectIsFocusedAsState()
    val shape = RoundedCornerShape(radius)
    val background = when {
        focused -> Color.White
        selected -> Color(0x26FFFFFF)
        else -> Color.Transparent
    }
    Row(
        modifier = modifier
            .then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier)
            .clip(shape)
            .background(background)
            .combinedClickable(interactionSource = source, indication = null, onLongClick = onLongClick, onClick = onClick)
            .padding(padding),
        verticalAlignment = Alignment.CenterVertically
    ) { content(focused) }
}

/** Pill button. */
@Composable
fun Pill(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, primary: Boolean = false, focusRequester: FocusRequester? = null) {
    FocusRow(
        onClick = onClick,
        modifier = modifier.then(if (primary) Modifier else Modifier.border(1.dp, VColor.Line, RoundedCornerShape(40.dp))),
        selected = primary,
        focusRequester = focusRequester,
        radius = 40.dp,
        padding = PaddingValues(horizontal = 22.dp, vertical = 11.dp)
    ) { focused ->
        Text(text, color = if (focused) Color.Black else VColor.Text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** Provider logo, or the channel name on a neutral tile (no logo from another source). */
@Composable
fun ChannelLogo(channel: Channel, width: Dp, height: Dp, focused: Boolean = false) {
    Box(
        modifier = Modifier.size(width, height).clip(RoundedCornerShape(10.dp)).background(if (focused) Color(0xFFE9E6F0) else Color(0xFF221F2B)),
        contentAlignment = Alignment.Center
    ) {
        val name: @Composable () -> Unit = {
            Text(
                channel.title, color = if (focused) Color.Black else VColor.Faint, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center, modifier = Modifier.padding(4.dp)
            )
        }
        if (channel.logo.startsWith("http")) {
            SubcomposeAsyncImage(
                model = channel.logo, contentDescription = null, contentScale = ContentScale.Fit,
                modifier = Modifier.padding(6.dp),
                loading = { name() }, error = { name() }
            )
        } else name()
    }
}
