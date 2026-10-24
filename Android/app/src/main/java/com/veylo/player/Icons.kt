package com.veylo.player

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Small drawn icons (the extended Material icon set would add megabytes to the app). */
enum class Glyph { Play, Pause, Prev, Next, Full, ExitFull, List, Back, Aspect }

@Composable
fun GlyphIcon(glyph: Glyph, color: Color = Color.White, size: Dp = 22.dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.width
        val h = this.size.height
        val stroke = Stroke(width = w * 0.11f, cap = StrokeCap.Round)
        fun tri(left: Float, right: Float, top: Float, bottom: Float, pointRight: Boolean) {
            val p = Path()
            if (pointRight) {
                p.moveTo(left, top); p.lineTo(right, (top + bottom) / 2); p.lineTo(left, bottom)
            } else {
                p.moveTo(right, top); p.lineTo(left, (top + bottom) / 2); p.lineTo(right, bottom)
            }
            p.close()
            drawPath(p, color)
        }
        when (glyph) {
            Glyph.Play -> tri(w * 0.24f, w * 0.86f, h * 0.14f, h * 0.86f, true)
            Glyph.Pause -> {
                drawRoundRect(color, Offset(w * 0.22f, h * 0.15f), Size(w * 0.18f, h * 0.7f), CornerRadius(w * 0.04f))
                drawRoundRect(color, Offset(w * 0.6f, h * 0.15f), Size(w * 0.18f, h * 0.7f), CornerRadius(w * 0.04f))
            }
            Glyph.Prev -> {
                drawRoundRect(color, Offset(w * 0.14f, h * 0.2f), Size(w * 0.11f, h * 0.6f), CornerRadius(w * 0.03f))
                tri(w * 0.3f, w * 0.86f, h * 0.2f, h * 0.8f, false)
            }
            Glyph.Next -> {
                tri(w * 0.14f, w * 0.7f, h * 0.2f, h * 0.8f, true)
                drawRoundRect(color, Offset(w * 0.75f, h * 0.2f), Size(w * 0.11f, h * 0.6f), CornerRadius(w * 0.03f))
            }
            Glyph.Full, Glyph.ExitFull -> {
                val a = w * 0.14f; val b = w * 0.86f; val l = w * 0.26f
                val inward = glyph == Glyph.ExitFull
                listOf(Offset(a, a) to Offset(1f, 1f), Offset(b, a) to Offset(-1f, 1f), Offset(a, b) to Offset(1f, -1f), Offset(b, b) to Offset(-1f, -1f))
                    .forEach { (corner, dir) ->
                        val c = if (inward) Offset(corner.x + dir.x * l, corner.y + dir.y * l) else corner
                        val sx = if (inward) -dir.x else dir.x
                        val sy = if (inward) -dir.y else dir.y
                        drawLine(color, c, Offset(c.x + sx * l, c.y), stroke.width, StrokeCap.Round)
                        drawLine(color, c, Offset(c.x, c.y + sy * l), stroke.width, StrokeCap.Round)
                    }
            }
            Glyph.List -> listOf(0.25f, 0.5f, 0.75f).forEach { y ->
                drawLine(color, Offset(w * 0.15f, h * y), Offset(w * 0.85f, h * y), stroke.width, StrokeCap.Round)
            }
            Glyph.Back -> {
                drawLine(color, Offset(w * 0.62f, h * 0.18f), Offset(w * 0.3f, h * 0.5f), stroke.width, StrokeCap.Round)
                drawLine(color, Offset(w * 0.3f, h * 0.5f), Offset(w * 0.62f, h * 0.82f), stroke.width, StrokeCap.Round)
            }
            Glyph.Aspect -> {
                drawRoundRect(color, Offset(w * 0.1f, h * 0.24f), Size(w * 0.8f, h * 0.52f), CornerRadius(w * 0.08f), style = stroke)
            }
        }
    }
}
