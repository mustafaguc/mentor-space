import CallKit
import Flutter
import PushKit
import UIKit
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Register for VoIP pushes. Only a VoIP (PushKit) push can wake a fully
    // killed iOS app to ring — this is the same mechanism WhatsApp uses.
    let voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
    voipRegistry.delegate = self
    voipRegistry.desiredPushTypes = [.voIP]

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // A new/rotated VoIP token — hand it to the plugin. Dart reads it via
  // getDevicePushTokenVoIP() and stores it in `device_tokens` (platform ios_voip).
  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType
  ) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  // Incoming VoIP push -> we MUST report a call to CallKit immediately (iOS 13+),
  // or the system terminates the app. This raises the native full-screen ringing
  // UI; on Accept, the Flutter side joins the Jitsi room (CallKit carries no media).
  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }

    let info = payload.dictionaryPayload
    let sessionId = info["sessionId"] as? String ?? UUID().uuidString
    let roomId = info["roomId"] as? String ?? ""
    let callerId = info["callerId"] as? String ?? ""
    let callerName = info["callerName"] as? String ?? "Someone"

    let data = flutter_callkit_incoming.Data(
      id: sessionId,
      nameCaller: callerName,
      handle: "MentorSpace call",
      type: 1 // video
    )
    data.appName = "MentorSpace"
    data.duration = 45000
    data.extra = [
      "sessionId": sessionId,
      "roomId": roomId,
      "callerId": callerId,
      "callerName": callerName,
    ]

    SwiftFlutterCallkitIncomingPlugin.sharedInstance?
      .showCallkitIncoming(data, fromPushKit: true)
    completion()
  }
}
