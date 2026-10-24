package com.veylo.player

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun BrandMark(size: Int = 44) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Image(painterResource(R.mipmap.ic_launcher), contentDescription = null, modifier = Modifier.size(size.dp).clip(RoundedCornerShape((size / 4).dp)))
        Spacer(Modifier.width((size / 3).dp))
        Text("veylo", color = Color(0xFFEDE8FF), fontSize = (size * 0.62).sp, fontWeight = FontWeight.Black)
    }
}

@Composable
fun LoadingScreen(app: AppState) {
    Box(Modifier.fillMaxSize().background(VColor.Bg), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            BrandMark(64)
            Spacer(Modifier.height(36.dp))
            CircularProgressIndicator(color = Color.White, strokeWidth = 3.dp)
            Spacer(Modifier.height(20.dp))
            Text(app.loadingText, color = VColor.Faint, fontSize = 17.sp)
        }
    }
}

@Composable
private fun field(label: String, value: String, onChange: (String) -> Unit, password: Boolean = false, keyboard: KeyboardType = KeyboardType.Text) {
    OutlinedTextField(
        value = value, onValueChange = onChange, singleLine = true,
        label = { Text(label) },
        visualTransformation = if (password) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = if (password) KeyboardType.Password else keyboard, imeAction = ImeAction.Next, autoCorrect = false),
        colors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = Color.White, unfocusedTextColor = VColor.Text,
            focusedBorderColor = VColor.Accent, unfocusedBorderColor = VColor.Line,
            focusedLabelColor = Color.White, unfocusedLabelColor = VColor.Faint, cursorColor = Color.White
        ),
        modifier = Modifier.fillMaxWidth().padding(vertical = 5.dp)
    )
}

@Composable
fun LoginScreen(app: AppState) {
    var kind by rememberSaveable { mutableStateOf("xtream") }
    var name by rememberSaveable { mutableStateOf("") }
    var server by rememberSaveable { mutableStateOf("") }
    var username by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var playlist by rememberSaveable { mutableStateOf("") }
    var save by rememberSaveable { mutableStateOf(true) }
    var localError by remember { mutableStateOf<String?>(null) }
    val saved = remember(app.listsVersion) { app.store.providers().sortedByDescending { it.lastUsed } }

    BackHandler(enabled = app.adding && app.session != null) { app.adding = false; app.showSettings() }

    Box(Modifier.fillMaxSize().background(VColor.Bg), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier.widthIn(max = 620.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(Modifier.height(12.dp))
            BrandMark(56)
            Spacer(Modifier.height(10.dp))
            Text(if (app.adding) "Add an account" else "Sign in to your IPTV provider", color = VColor.Faint, fontSize = 16.sp)
            Spacer(Modifier.height(22.dp))

            if (!app.adding && saved.isNotEmpty()) {
                Text("SAVED ACCOUNTS", color = VColor.Faint, fontSize = 12.sp, fontWeight = FontWeight.Bold, modifier = Modifier.fillMaxWidth())
                saved.forEach { p ->
                    FocusRow(onClick = { app.connect(p, save = true) }, modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp)) { f ->
                        Column(Modifier.weight(1f)) {
                            Text(p.name, color = if (f) Color.Black else VColor.Text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                            Text(if (p.kind == "xtream") "Xtream · ${p.username}" else "M3U playlist", color = if (f) Color.DarkGray else VColor.Faint, fontSize = 13.sp)
                        }
                        Text("Connect", color = if (f) Color.Black else VColor.Accent, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    }
                }
                Spacer(Modifier.height(18.dp))
                Text("OR ADD ANOTHER", color = VColor.Faint, fontSize = 12.sp, fontWeight = FontWeight.Bold, modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height(8.dp))
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                Pill("Xtream Codes", { kind = "xtream" }, primary = kind == "xtream")
                Pill("M3U Playlist", { kind = "m3u" }, primary = kind == "m3u")
            }
            Spacer(Modifier.height(10.dp))
            field("Account name (optional)", name, { name = it })
            if (kind == "xtream") {
                field("Server (http://host:port)", server, { server = it }, keyboard = KeyboardType.Uri)
                field("Username", username, { username = it })
                field("Password", password, { password = it }, password = true)
            } else {
                field("Playlist link (M3U)", playlist, { playlist = it }, keyboard = KeyboardType.Uri)
            }
            FocusRow(onClick = { save = !save }, modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)) { f ->
                Box(
                    Modifier.size(22.dp).clip(RoundedCornerShape(6.dp)).background(if (save) VColor.Accent else Color(0xFF2A2634)),
                    contentAlignment = Alignment.Center
                ) { if (save) Text("✓", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold) }
                Spacer(Modifier.width(12.dp))
                Column {
                    Text("Save this provider", color = if (f) Color.Black else VColor.Text, fontSize = 16.sp)
                    Text("Signs in automatically next time. Stored only on this device.", color = if (f) Color.DarkGray else VColor.Faint, fontSize = 12.sp)
                }
            }
            val message = localError ?: app.loginError
            if (message != null) {
                Text(message, color = Color(0xFFFF8A80), fontSize = 15.sp, modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp))
            }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                Pill("Connect", {
                    localError = null
                    val p = if (kind == "xtream") {
                        if (server.isBlank() || username.isBlank() || password.isEmpty()) { localError = "Enter server, username and password."; return@Pill }
                        Provider("", name.trim(), "xtream", server.trim(), username.trim(), password)
                    } else {
                        if (!playlist.trim().startsWith("http")) { localError = "Enter the playlist link (http…)."; return@Pill }
                        Provider("", name.trim(), "m3u", playlistUrl = playlist.trim())
                    }
                    app.connect(p, save)
                }, primary = true)
                if (app.adding && app.session != null) Pill("Back", { app.adding = false; app.showSettings() })
            }
            Spacer(Modifier.height(30.dp))
            Text("Veylo plays streams from your own provider. Use it only for content you are allowed to watch.", color = VColor.Faint, fontSize = 12.sp)
        }
    }
}
