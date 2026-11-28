package com.playvibemusic.vibe

import android.content.Context
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider
import com.google.android.gms.cast.framework.media.CastMediaOptions

// Tells the Cast SDK which Cast application to target.
// kDefaultMediaReceiverApplicationID ("CC1AD845") is Google's built-in audio/video
// receiver — no Cast developer console registration required.
class VibeCastOptionsProvider : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions =
        CastOptions.Builder()
            .setReceiverApplicationId(CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID)
            .setCastMediaOptions(CastMediaOptions.Builder().build())
            .build()

    override fun getAdditionalSessionProviders(
        context: Context,
    ): List<SessionProvider>? = null
}
