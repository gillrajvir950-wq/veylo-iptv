package com.veylo.player

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.util.Date

@Composable
private fun Heading(text: String) {
    Text(text, color = VColor.Faint, fontSize = 12.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 22.dp, bottom = 6.dp))
}

@Composable
private fun SettingRow(title: String, value: String, onClick: () -> Unit, focusRequester: FocusRequester? = null) {
    FocusRow(onClick = onClick, modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp), focusRequester = focusRequester) { f ->
        Text(title, color = if (f) Color.Black else VColor.Text, fontSize = 17.sp, modifier = Modifier.weight(1f))
        Text(value, color = if (f) Color.DarkGray else VColor.Faint, fontSize = 15.sp)
    }
}

@Composable
fun SettingsScreen(app: AppState) {
    val session = app.session
    var version by remember { mutableStateOf(0) }
    var confirmRemove by remember { mutableStateOf<String?>(null) }
    var account by remember { mutableStateOf<Xtream.Account?>(null) }
    val providers = remember(version, app.listsVersion) { app.store.providers().sortedByDescending { it.lastUsed } }
    val first = remember { FocusRequester() }

    BackHandler { app.screen = if (session != null) Screen.Browser else Screen.Login }
    LaunchedEffect(Unit) { delay(120); runCatching { first.requestFocus() } }
    LaunchedEffect(session) {
        val x = session?.xtream ?: return@LaunchedEffect
        account = withContext(Dispatchers.IO) { runCatching { x.authenticate() }.getOrNull() }
    }

    Box(Modifier.fillMaxSize().background(VColor.Bg), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = 760.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Settings", color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                Pill("Back", { app.screen = if (session != null) Screen.Browser else Screen.Login }, focusRequester = first)
            }

            Heading("ACCOUNTS")
            providers.forEach { p ->
                val watching = session?.provider?.id == p.id
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FocusRow(onClick = { if (watching) app.screen = Screen.Browser else app.connect(p, save = true) }, modifier = Modifier.weight(1f).padding(vertical = 2.dp)) { f ->
                        Column(Modifier.weight(1f)) {
                            Text(p.name, color = if (f) Color.Black else VColor.Text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                            Text(if (p.kind == "xtream") "Xtream · ${p.username}" else "M3U playlist", color = if (f) Color.DarkGray else VColor.Faint, fontSize = 13.sp)
                        }
                        if (watching) Text("WATCHING", color = if (f) Color.Black else VColor.Accent, fontSize = 12.sp, fontWeight = FontWeight.Black)
                    }
                    Pill(if (confirmRemove == p.id) "Press again" else "Remove", {
                        if (confirmRemove == p.id) {
                            app.store.removeProvider(p.id)
                            confirmRemove = null
                            version += 1
                        } else confirmRemove = p.id
                    })
                }
            }
            SettingRow("Add account", "Xtream or M3U  ›", { app.adding = true; app.loginError = null; app.screen = Screen.Login })

            if (account != null) {
                val a = account!!
                Heading("SUBSCRIPTION")
                SettingRow("Status", a.status.ifEmpty { "—" }, {})
                SettingRow("Expires", a.expires?.let { DateFormat.getDateInstance().format(Date(it)) } ?: "Never", {})
                SettingRow("Connections", "${a.active} of ${a.max} in use", {})
            }

            Heading("PLAYBACK")
            SettingRow("Stream format", if (app.store.format == "ts") "MPEG-TS (recommended)" else "HLS (m3u8)", {
                app.store.format = if (app.store.format == "ts") "m3u8" else "ts"
                version += 1
                app.showToast("Used after the next sign-in (Reload channels)")
            })
            SettingRow("Start with the last channel", if (app.store.autostart) "On" else "Off", { app.store.autostart = !app.store.autostart; version += 1 })
            if (session != null) SettingRow("Reload channels", "${session.channels.size} channels", { app.connect(session.provider, save = false) })

            Heading("ABOUT")
            SettingRow("Veylo for Android", "v" + BuildConfig.VERSION_NAME, {})
            Spacer(Modifier.height(18.dp))
            if (session != null) Pill("Sign out", { app.signOut() })
            Spacer(Modifier.height(40.dp))
        }
    }
}
