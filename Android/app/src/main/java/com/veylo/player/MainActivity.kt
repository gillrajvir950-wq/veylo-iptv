package com.veylo.player

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.lifecycleScope

class MainActivity : ComponentActivity() {
    private lateinit var app: AppState
    private var stoppedWhilePlaying = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        app = AppState(this, lifecycleScope)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = VColor.Accent, background = VColor.Bg, surface = VColor.Panel)) {
                VeyloApp(app)
            }
        }
        app.start()
    }

    // In the background the stream stops (frees the provider connection) and restarts on return.
    override fun onStop() {
        super.onStop()
        if (app.screen == Screen.Player) { app.vlc.stop(); stoppedWhilePlaying = true }
    }

    override fun onStart() {
        super.onStart()
        if (stoppedWhilePlaying) { stoppedWhilePlaying = false; app.resumeTick += 1 }
    }
}

@Composable
fun VeyloApp(app: AppState) {
    Box(Modifier.fillMaxSize().background(VColor.Bg)) {
        when (app.screen) {
            Screen.Login -> LoginScreen(app)
            Screen.Loading -> LoadingScreen(app)
            Screen.Browser -> MainShell(app)
            Screen.Player -> app.player?.let { PlayerScreen(app, it) } ?: MainShell(app)
        }
        val toast = app.toast
        if (toast != null && app.screen != Screen.Player) {
            Text(toast, color = Color.White, fontSize = 16.sp, modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 120.dp)
                .background(Color(0xEE1E1B26), RoundedCornerShape(30.dp)).padding(horizontal = 22.dp, vertical = 12.dp))
        }
    }
}
