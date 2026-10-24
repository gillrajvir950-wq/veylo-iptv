package com.veylo.player

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.List
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Signed-in app: Home · Live TV · Settings.
 *  Phones: floating bottom bar. Boxes / tablets in landscape: menu at the top (remote friendly). */
@Composable
fun MainShell(app: AppState) {
    val tv = isTv(app)
    BackHandler(enabled = app.tab != Tab.Home && app.detail == null) { app.tab = Tab.Home }
    Backdrop {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val wide = tv || maxWidth >= 720.dp
            val detail = app.detail
            if (detail != null) {
                DetailScreen(app, detail, wide)
            } else if (wide) {
                Column(Modifier.fillMaxSize().statusBarsPadding()) {
                    TopMenu(app)
                    Box(Modifier.weight(1f)) { Page(app, wide = true, bottomSpace = 0) }
                }
            } else {
                Box(Modifier.fillMaxSize().statusBarsPadding()) {
                    Page(app, wide = false, bottomSpace = 96)
                    BottomBar(app, Modifier.align(Alignment.BottomCenter))
                }
            }
        }
    }
}

@Composable
private fun Page(app: AppState, wide: Boolean, bottomSpace: Int) {
    when (app.tab) {
        Tab.Home -> HomeScreen(app, wide, bottomSpace)
        Tab.Live -> LiveScreen(app, wide, bottomSpace)
        Tab.Movies -> LibraryScreen(app, VodKind.Movie, wide, bottomSpace)
        Tab.Series -> LibraryScreen(app, VodKind.Series, wide, bottomSpace)
        Tab.Settings -> Box(Modifier.fillMaxSize().padding(bottom = bottomSpace.dp)) { SettingsScreen(app) }
    }
}

@Composable
private fun TopMenu(app: AppState) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 28.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        BrandMark(36)
        Spacer(Modifier.width(36.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Tab.values().forEach { t ->
                FocusRow(
                    onClick = { app.tab = t }, selected = app.tab == t, radius = 30.dp,
                    padding = PaddingValues(horizontal = 20.dp, vertical = 9.dp)
                ) { f ->
                    Text(t.title, color = if (f) Color.Black else if (app.tab == t) Color.White else VColor.Faint,
                        fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
        Spacer(Modifier.weight(1f))
        Text(app.session?.provider?.name ?: "", color = VColor.Faint, fontSize = 14.sp, maxLines = 1)
        Spacer(Modifier.width(12.dp))
        Text("v" + BuildConfig.VERSION_NAME, color = Color(0x66FFFFFF), fontSize = 12.sp)
    }
}

@Composable
private fun BottomBar(app: AppState, modifier: Modifier) {
    val icons = mapOf(Tab.Home to Icons.Filled.Home, Tab.Live to Icons.Filled.PlayArrow, Tab.Movies to Icons.Filled.Star,
        Tab.Series to Icons.Filled.List, Tab.Settings to Icons.Filled.Settings)
    Row(
        modifier.navigationBarsPadding().padding(horizontal = 14.dp, vertical = 10.dp).fillMaxWidth()
            .shadow(18.dp, RoundedCornerShape(40.dp))
            .clip(RoundedCornerShape(40.dp)).background(Color(0xF21A1722))
            .border(1.dp, Color(0x22FFFFFF), RoundedCornerShape(40.dp)).padding(5.dp),
        horizontalArrangement = Arrangement.SpaceEvenly
    ) {
        Tab.values().forEach { t ->
            val active = app.tab == t
            Column(
                Modifier.weight(1f).clip(RoundedCornerShape(30.dp)).background(if (active) Color(0x22FFFFFF) else Color.Transparent)
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { app.tab = t }
                    .padding(vertical = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(icons.getValue(t), contentDescription = t.title, tint = if (active) VColor.Accent else Color(0x9EFFFFFF), modifier = Modifier.size(22.dp))
                Spacer(Modifier.height(2.dp))
                Text(if (t == Tab.Live) "Live" else t.title, color = if (active) VColor.Accent else Color(0x9EFFFFFF), fontSize = 11.sp, maxLines = 1,
                    fontWeight = if (active) FontWeight.SemiBold else FontWeight.Medium)
            }
        }
    }
}
