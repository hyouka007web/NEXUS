package com.tufblade.browser

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.content.Intent
import android.os.Bundle
import android.view.animation.DecelerateInterpolator
import androidx.appcompat.app.AppCompatActivity

class SplashActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_splash)

        val logo = findViewById<android.widget.ImageView>(R.id.splashLogo)
        logo.scaleX = 0.78f
        logo.scaleY = 0.78f
        AnimatorSet().apply {
            playTogether(
                ObjectAnimator.ofFloat(logo, "scaleX", 0.78f, 1f),
                ObjectAnimator.ofFloat(logo, "scaleY", 0.78f, 1f),
                ObjectAnimator.ofFloat(logo, "alpha", 0f, 1f)
            )
            duration = 420
            interpolator = DecelerateInterpolator()
            start()
        }
        logo.postDelayed({
            startActivity(Intent(this, MainActivity::class.java))
            overridePendingTransition(android.R.anim.fade_in, android.R.anim.fade_out)
            finish()
        }, 620)
    }
}
