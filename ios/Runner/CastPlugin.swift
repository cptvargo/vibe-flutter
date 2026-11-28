import Flutter
import GoogleCast

// CastPlugin bridges the Flutter "vibe/cast" MethodChannel and
// "vibe/cast/events" EventChannel to the native Google Cast SDK.
//
// Registration happens in AppDelegate.didInitializeImplicitFlutterEngine(_:).
// The Cast context is also initialised there before this plugin is registered.
class CastPlugin: NSObject,
    FlutterPlugin,
    FlutterStreamHandler,
    GCKDiscoveryManagerListener,
    GCKSessionManagerListener {

    private var eventSink: FlutterEventSink?

    // MARK: - FlutterPlugin

    static func register(with registrar: FlutterPluginRegistrar) {
        let method = FlutterMethodChannel(
            name: "vibe/cast",
            binaryMessenger: registrar.messenger())
        let events = FlutterEventChannel(
            name: "vibe/cast/events",
            binaryMessenger: registrar.messenger())
        let instance = CastPlugin()
        registrar.addMethodCallDelegate(instance, channel: method)
        events.setStreamHandler(instance)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startDiscovery":   startDiscovery(result: result)
        case "connectToDevice":  connectToDevice(call, result: result)
        case "loadMedia":        loadMedia(call, result: result)
        case "stopCasting":      stopCasting(result: result)
        case "seekTo":           seekTo(call, result: result)
        default:                 result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: - Discovery

    private func startDiscovery(result: FlutterResult) {
        guard GCKCastContext.isSharedInstanceInitialized() else {
            result(FlutterError(code: "CAST_NOT_INIT",
                                message: "Cast context not initialised",
                                details: nil))
            return
        }
        let dm = GCKCastContext.sharedInstance().discoveryManager
        dm.add(self)
        dm.startDiscovery()
        GCKCastContext.sharedInstance().sessionManager.add(self)
        emitDevices()
        result(nil)
    }

    private func emitDevices() {
        guard GCKCastContext.isSharedInstanceInitialized() else { return }
        let dm = GCKCastContext.sharedInstance().discoveryManager
        var list: [[String: String]] = []
        for i in 0..<dm.deviceCount {
            let d = dm.device(at: i)
            list.append([
                "id":    d.uniqueID,
                "name":  d.friendlyName ?? d.uniqueID,
                "model": d.modelName ?? "",
            ])
        }
        eventSink?(["type": "devicesUpdated", "devices": list])
    }

    // GCKDiscoveryManagerListener
    func didUpdateDeviceList() { emitDevices() }
    func didInsertDevice(_ device: GCKDevice, at index: UInt) { emitDevices() }
    func didRemoveDevice(_ device: GCKDevice, at index: UInt) { emitDevices() }

    // MARK: - Connect / Disconnect

    private func connectToDevice(_ call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String else {
            result(FlutterError(code: "BAD_ARGS", message: "deviceId required", details: nil))
            return
        }
        guard GCKCastContext.isSharedInstanceInitialized() else {
            result(FlutterError(code: "CAST_NOT_INIT", message: "Cast context not initialised", details: nil))
            return
        }
        let dm = GCKCastContext.sharedInstance().discoveryManager
        for i in 0..<dm.deviceCount {
            let d = dm.device(at: i)
            if d.uniqueID == deviceId {
                GCKCastContext.sharedInstance().sessionManager.startSession(with: d)
                result(nil)
                return
            }
        }
        result(FlutterError(code: "NOT_FOUND",
                            message: "Device \(deviceId) not found",
                            details: nil))
    }

    private func stopCasting(result: FlutterResult) {
        guard GCKCastContext.isSharedInstanceInitialized() else { result(nil); return }
        GCKCastContext.sharedInstance().sessionManager
            .endSessionAndStopCasting(true)
        result(nil)
    }

    // GCKSessionManagerListener
    func sessionManager(_ sm: GCKSessionManager, didStart session: GCKSession) {
        let d = session.device
        eventSink?([
            "type": "sessionStarted",
            "device": ["id": d.uniqueID, "name": d.friendlyName ?? "", "model": d.modelName ?? ""],
        ])
    }
    func sessionManager(_ sm: GCKSessionManager,
                        didEnd session: GCKSession,
                        withError error: Error?) {
        eventSink?(["type": "sessionEnded"])
    }
    func sessionManager(_ sm: GCKSessionManager,
                        didFailToStart session: GCKSession,
                        withError error: Error) {
        eventSink?(["type": "sessionFailed", "error": error.localizedDescription])
    }
    func sessionManager(_ sm: GCKSessionManager,
                        didSuspend session: GCKSession,
                        with reason: GCKConnectionSuspendReason) {
        eventSink?(["type": "sessionEnded"])
    }

    // MARK: - Load Media

    private func loadMedia(_ call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "BAD_ARGS", message: "args required", details: nil))
            return
        }
        guard GCKCastContext.isSharedInstanceInitialized(),
              let session = GCKCastContext.sharedInstance().sessionManager
                  .currentCastSession else {
            result(FlutterError(code: "NO_SESSION",
                                message: "No active Cast session",
                                details: nil))
            return
        }

        let url         = args["url"]         as? String ?? ""
        let title       = args["title"]       as? String ?? ""
        let artist      = args["artist"]      as? String ?? ""
        let album       = args["album"]       as? String ?? ""
        let artUrl      = args["artUrl"]      as? String ?? ""
        let contentType = args["contentType"] as? String ?? "audio/mpeg"

        let meta = GCKMediaMetadata(metadataType: .musicTrack)
        meta.setString(title,  forKey: kGCKMetadataKeyTitle)
        meta.setString(artist, forKey: kGCKMetadataKeyArtist)
        meta.setString(album,  forKey: kGCKMetadataKeyAlbumTitle)
        if !artUrl.isEmpty, let artUri = URL(string: artUrl) {
            meta.addImage(GCKImage(url: artUri, width: 400, height: 400))
        }

        guard let contentUrl = URL(string: url) else {
            result(FlutterError(code: "BAD_URL", message: "Invalid URL: \(url)", details: nil))
            return
        }

        let builder = GCKMediaInformationBuilder(contentURL: contentUrl)
        builder.streamType   = .buffered
        builder.contentType  = contentType
        builder.metadata     = meta
        let media = builder.build()

        let opts = GCKMediaLoadOptions()
        opts.autoplay = true

        session.remoteMediaClient?.loadMedia(media, with: opts)
        result(nil)
    }

    // MARK: - Seek

    private func seekTo(_ call: FlutterMethodCall, result: FlutterResult) {
        guard GCKCastContext.isSharedInstanceInitialized(),
              let client = GCKCastContext.sharedInstance().sessionManager
                  .currentCastSession?.remoteMediaClient else {
            result(nil); return
        }
        let ms = (call.arguments as? [String: Any])?["positionMs"] as? Int ?? 0
        let opts = GCKMediaSeekOptions()
        opts.interval = TimeInterval(ms) / 1000.0
        client.seek(with: opts)
        result(nil)
    }
}

