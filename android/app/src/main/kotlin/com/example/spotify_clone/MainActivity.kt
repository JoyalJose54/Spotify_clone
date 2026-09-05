package com.example.spotify_clone

import android.os.Build
import android.os.Bundle
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Instantly remove the Android 12+ splash screen on entry - no logo flash
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val splashScreen = installSplashScreen()
            splashScreen.setOnExitAnimationListener { splashScreenViewProvider ->
                // Remove immediately - do NOT animate it out
                splashScreenViewProvider.remove()
            }
        }
        super.onCreate(savedInstanceState)
    }
}
