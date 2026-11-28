package com.playvibemusic.vibe

import android.content.Context
import android.net.Uri
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadOptions
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaSeekOptions
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.common.images.WebImage
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class CastPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {

    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    private var castContext: CastContext? = null
    private val sessionListener = object : SessionManagerListener<CastSession> {

        override fun onSessionStarted(session: CastSession, sessionId: String) {
            val d = session.castDevice ?: return
            sendEvent(mapOf(
                "type"   to "sessionStarted",
                "device" to mapOf(
                    "id"    to d.deviceId,
                    "name"  to (d.friendlyName ?: d.deviceId),
                    "model" to (d.modelName ?: ""),
                ),
            ))
        }

        override fun onSessionEnded(session: CastSession, error: Int) {
            sendEvent(mapOf("type" to "sessionEnded"))
        }

        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {}
        override fun onSessionResumeFailed(session: CastSession, error: Int) {}
        override fun onSessionSuspended(session: CastSession, reason: Int) {
            sendEvent(mapOf("type" to "sessionEnded"))
        }
        override fun onSessionStarting(session: CastSession) {}
        override fun onSessionStartFailed(session: CastSession, error: Int) {
            sendEvent(mapOf("type" to "sessionFailed", "error" to "Error $error"))
        }
        override fun onSessionEnding(session: CastSession) {}
        override fun onSessionResuming(session: CastSession, sessionId: String) {}
    }

    // MARK: - FlutterPlugin

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context      = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "vibe/cast")
        eventChannel  = EventChannel(binding.binaryMessenger, "vibe/cast/events")
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    // MARK: - MethodCallHandler

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startDiscovery"  -> startDiscovery(result)
            "connectToDevice" -> connectToDevice(call, result)
            "loadMedia"       -> loadMedia(call, result)
            "stopCasting"     -> stopCasting(result)
            "seekTo"          -> seekTo(call, result)
            else              -> result.notImplemented()
        }
    }

    // MARK: - EventChannel.StreamHandler

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // MARK: - Discovery

    private fun startDiscovery(result: Result) {
        try {
            castContext = CastContext.getSharedInstance(context)
            castContext?.sessionManager?.addSessionManagerListener(
                sessionListener, CastSession::class.java)
            emitDevices()
            result.success(null)
        } catch (e: Exception) {
            result.error("CAST_NOT_INIT", e.message, null)
        }
    }

    private fun emitDevices() {
        val dm = castContext?.mergedDiscoveryManager ?: return
        val list = mutableListOf<Map<String, String>>()
        for (i in 0 until dm.deviceCount) {
            val d = dm.getDevice(i) ?: continue
            list.add(mapOf(
                "id"    to d.deviceId,
                "name"  to (d.friendlyName ?: d.deviceId),
                "model" to (d.modelName ?: ""),
            ))
        }
        sendEvent(mapOf("type" to "devicesUpdated", "devices" to list))
    }

    // MARK: - Connect / Disconnect

    private fun connectToDevice(call: MethodCall, result: Result) {
        val deviceId = call.argument<String>("deviceId") ?: run {
            result.error("BAD_ARGS", "deviceId required", null)
            return
        }
        val dm = castContext?.mergedDiscoveryManager ?: run {
            result.error("CAST_NOT_INIT", "Cast not initialised", null)
            return
        }
        for (i in 0 until dm.deviceCount) {
            val d = dm.getDevice(i) ?: continue
            if (d.deviceId == deviceId) {
                castContext?.sessionManager?.startSession(d)
                result.success(null)
                return
            }
        }
        result.error("NOT_FOUND", "Device $deviceId not found", null)
    }

    private fun stopCasting(result: Result) {
        castContext?.sessionManager?.endCurrentSession(true)
        result.success(null)
    }

    // MARK: - Load Media

    private fun loadMedia(call: MethodCall, result: Result) {
        val session = castContext?.sessionManager?.currentCastSession ?: run {
            result.error("NO_SESSION", "No active Cast session", null)
            return
        }

        val url         = call.argument<String>("url")         ?: ""
        val title       = call.argument<String>("title")       ?: ""
        val artist      = call.argument<String>("artist")      ?: ""
        val album       = call.argument<String>("album")       ?: ""
        val artUrl      = call.argument<String>("artUrl")      ?: ""
        val contentType = call.argument<String>("contentType") ?: "audio/mpeg"

        val meta = MediaMetadata(MediaMetadata.MEDIA_TYPE_MUSIC_TRACK)
        meta.putString(MediaMetadata.KEY_TITLE, title)
        meta.putString(MediaMetadata.KEY_ARTIST, artist)
        meta.putString(MediaMetadata.KEY_ALBUM_TITLE, album)
        if (artUrl.isNotEmpty()) {
            meta.addImage(WebImage(Uri.parse(artUrl)))
        }

        val mediaInfo = MediaInfo.Builder(url)
            .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
            .setContentType(contentType)
            .setMetadata(meta)
            .build()

        val loadOptions = MediaLoadOptions.Builder()
            .setAutoplay(true)
            .build()

        session.remoteMediaClient?.load(mediaInfo, loadOptions)
        result.success(null)
    }

    // MARK: - Seek

    private fun seekTo(call: MethodCall, result: Result) {
        val ms = call.argument<Int>("positionMs") ?: 0
        castContext?.sessionManager?.currentCastSession
            ?.remoteMediaClient
            ?.seek(
                MediaSeekOptions.Builder()
                    .setPosition(ms.toLong())
                    .build()
            )
        result.success(null)
    }

    // MARK: - Helpers

    private fun sendEvent(data: Map<String, Any>) {
        // Post on main thread — Flutter EventSink must be called from main thread
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            eventSink?.success(data)
        }
    }
}
