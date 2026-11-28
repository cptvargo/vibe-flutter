import Flutter
import GoogleCast
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialise Google Cast before any plugin or Flutter engine work.
    // CC1AD845 is Google's Default Media Receiver — no Cast developer console
    // registration required; supports audio and video playback out of the box.
    let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
    let options  = GCKCastOptions(discoveryCriteria: criteria)
    options.startDiscoveryAfterFirstTapOnCastButton = false
    GCKCastContext.setSharedInstanceWith(options)
    GCKLogger.sharedInstance().delegate = nil   // suppress Cast SDK logs

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Register our Cast platform-channel bridge
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CastPlugin") {
      CastPlugin.register(with: registrar)
    }
  }
}
