import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A call the user accepted from the native ringing UI, ready to be joined.
/// The media itself is still handled entirely by Jitsi — this only carries the
/// room name to hand off to `CallService.join`.
class AcceptedCall {
  final String sessionId;
  final String roomId;
  final String callerName;
  const AcceptedCall({
    required this.sessionId,
    required this.roomId,
    required this.callerName,
  });

  factory AcceptedCall.fromExtra(Map<dynamic, dynamic> extra) => AcceptedCall(
        sessionId: (extra['sessionId'] as String?) ?? '',
        roomId: (extra['roomId'] as String?) ?? '',
        callerName: (extra['callerName'] as String?)?.trim().isNotEmpty == true
            ? extra['callerName'] as String
            : 'Someone',
      );
}

/// Top-level FCM background handler (Android). Must be a top-level / static
/// function annotated with `@pragma('vm:entry-point')` so it survives
/// tree-shaking and can run in a background isolate when the app is killed.
///
/// It only needs the CallKit plugin (no Supabase / Firebase app), so a data
/// push can raise the native full-screen ringing UI even with the app dead.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await PushService.handleDataMessage(message.data);
}

/// Incoming-call plumbing: keeps the device's push token registered, turns an
/// incoming-call signal (FCM data push on Android, PushKit VoIP on iOS, or the
/// in-app Realtime fallback) into a native ringing UI, and routes the user's
/// Accept/Decline back into the app.
///
/// Design note: `flutter_callkit_incoming` is ONLY the "doorbell" — the native
/// lock-screen ringing surface. On Accept we emit an [AcceptedCall]; the app
/// then joins the Jitsi room via the existing `CallService`, which owns 100% of
/// the audio/video. CallKit carries no media.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final _acceptsCtrl = StreamController<AcceptedCall>.broadcast();

  /// Fires when the user accepts a call while the app is alive.
  Stream<AcceptedCall> get accepts => _acceptsCtrl.stream;

  /// A call accepted while the app was launching (cold start from the ringing
  /// UI). The first listener to come up consumes it via [takePending].
  AcceptedCall? _pending;
  AcceptedCall? takePending() {
    final p = _pending;
    _pending = null;
    return p;
  }

  /// Session ids we've already raised a ring for, so the Realtime fallback and
  /// the FCM push don't double-ring the same call. Static because the ring can
  /// be shown from the background isolate.
  static final Set<String> _shownCallIds = {};

  bool _wired = false;

  SupabaseClient get _db => Supabase.instance.client;

  /// Wire CallKit events, the FCM foreground listener, and token sync. Call once
  /// from `main` after Firebase (Android) and Supabase are initialized.
  Future<void> initApp({required bool firebaseReady}) async {
    if (_wired) return;
    _wired = true;

    _listenCallKitEvents();

    // FCM only wakes Android. iOS incoming calls arrive as PushKit VoIP pushes
    // handled natively in AppDelegate, which forwards them to CallKit.
    if (firebaseReady && Platform.isAndroid) {
      FirebaseMessaging.onMessage.listen((m) => handleDataMessage(m.data));
      FirebaseMessaging.instance.onTokenRefresh.listen((_) => syncTokens());
    }

    // Keep the device token attached to whoever is signed in.
    _db.auth.onAuthStateChange.listen((state) {
      final ev = state.event;
      final signedIn = ev == AuthChangeEvent.signedIn ||
          ev == AuthChangeEvent.tokenRefreshed ||
          ev == AuthChangeEvent.initialSession;
      if (signedIn && _db.auth.currentUser != null) {
        syncTokens();
      }
    });

    if (_db.auth.currentUser != null) await syncTokens();
  }

  Future<void> _requestPermissions() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {}
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'rationaleMessagePermission':
            'MentorSpace needs notification access to ring you for incoming calls.',
        'postNotificationMessageRequired':
            'Enable notifications in Settings so you don’t miss calls.',
      });
    } catch (_) {}
    // Android 14+ requires an explicit grant to launch the full-screen ringer.
    try {
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (_) {}
  }

  /// Register this device's push token for the signed-in user.
  ///  - Android: the FCM registration token.
  ///  - iOS: the PushKit VoIP token (only VoIP pushes can ring a killed app).
  Future<void> syncTokens() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    await _requestPermissions();
    try {
      if (Platform.isAndroid) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) await _upsertToken(uid, token, 'android');
      } else if (Platform.isIOS) {
        final voip = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
        if (voip != null && voip.isNotEmpty) {
          await _upsertToken(uid, voip, 'ios_voip');
        }
      }
    } catch (_) {}
  }

  Future<void> _upsertToken(String uid, String token, String platform) async {
    await _db.from('device_tokens').upsert({
      'token': token,
      'user_id': uid,
      'platform': platform,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Detach this device's token(s). Call just before signing out so the next
  /// caller doesn't ring a device the user has left.
  Future<void> removeTokens() async {
    try {
      final tokens = <String>[];
      if (Platform.isAndroid) {
        final t = await FirebaseMessaging.instance.getToken();
        if (t != null) tokens.add(t);
      } else if (Platform.isIOS) {
        final v = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
        if (v != null && v.isNotEmpty) tokens.add(v);
      }
      for (final t in tokens) {
        await _db.from('device_tokens').delete().eq('token', t);
      }
    } catch (_) {}
  }

  // ---- Incoming signal -> native ring --------------------------------------

  /// Turn an incoming-call data payload into a native ringing UI. Safe to call
  /// from the FCM background isolate. Dedupes by session id.
  static Future<void> handleDataMessage(Map<String, dynamic> data) async {
    final type = data['type'];
    final sessionId = data['sessionId'] as String?;
    if (sessionId == null) return;

    if (type == 'cancel_call') {
      _shownCallIds.remove(sessionId);
      await FlutterCallkitIncoming.endCall(sessionId);
      return;
    }
    if (type != 'incoming_call') return;
    if (_shownCallIds.contains(sessionId)) return;
    _shownCallIds.add(sessionId);

    await _show(
      sessionId: sessionId,
      roomId: (data['roomId'] as String?) ?? '',
      callerId: (data['callerId'] as String?) ?? '',
      callerName: (data['callerName'] as String?)?.trim().isNotEmpty == true
          ? data['callerName'] as String
          : 'Someone',
    );
  }

  /// Realtime (foreground) fallback: a `sessions` INSERT arrived while the app
  /// is open. Reuses the exact same CallKit UI as the push path, so the app
  /// still rings in-foreground even before Firebase/APNs is configured.
  Future<void> showFromSession(Map<String, dynamic> session) async {
    final sessionId = session['id'] as String?;
    if (sessionId == null || _shownCallIds.contains(sessionId)) return;

    final callerId = (session['client_id'] as String?) ?? '';
    var callerName = 'Someone';
    try {
      final caller = await _db
          .from('profiles')
          .select('full_name')
          .eq('id', callerId)
          .maybeSingle();
      final n = (caller?['full_name'] as String?)?.trim();
      if (n != null && n.isNotEmpty) callerName = n;
    } catch (_) {}

    _shownCallIds.add(sessionId);
    await _show(
      sessionId: sessionId,
      roomId: (session['room_id'] as String?) ?? '',
      callerId: callerId,
      callerName: callerName,
    );
  }

  static Future<void> _show({
    required String sessionId,
    required String roomId,
    required String callerId,
    required String callerName,
  }) async {
    final params = CallKitParams(
      // iOS CallKit requires a UUID; our session ids are gen_random_uuid().
      id: sessionId,
      nameCaller: callerName,
      appName: 'MentorSpace',
      handle: 'MentorSpace call',
      type: 1, // video
      duration: 45000, // auto-miss after 45s of ringing
      extra: {
        'sessionId': sessionId,
        'roomId': roomId,
        'callerId': callerId,
        'callerName': callerName,
      },
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#6C4CF1',
        actionColor: '#22C55E',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'Incoming calls',
        isShowFullLockedScreen: true,
        isImportant: true,
        isFullScreen: true,
        textAccept: 'Accept',
        textDecline: 'Decline',
      ),
      ios: const IOSParams(
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  // ---- Accept / Decline routing --------------------------------------------

  void _listenCallKitEvents() {
    FlutterCallkitIncoming.onEvent.listen((event) async {
      if (event == null) return;
      switch (event) {
        case CallEventActionCallAccept(:final callKitParams):
          final call = AcceptedCall.fromExtra(callKitParams.extra ?? const {});
          if (call.roomId.isEmpty) break;
          _pending = call;
          _acceptsCtrl.add(call);
          // We don't use CallKit's in-call screen — Jitsi renders the call — so
          // end the native call to free the audio session for WebRTC.
          await FlutterCallkitIncoming.endCall(callKitParams.id);
          _shownCallIds.remove(callKitParams.id);
        case CallEventActionCallDecline(:final callKitParams):
          _shownCallIds.remove(callKitParams.id);
          await _markSession(
              callKitParams.extra?['sessionId'] as String?, 'rejected');
        case CallEventActionCallTimeout(:final id):
          _shownCallIds.remove(id);
          await _markSession(id, 'missed');
        case CallEventActionCallEnded(:final callKitParams):
          _shownCallIds.remove(callKitParams.id);
        case CallEventActionDidUpdateDevicePushTokenVoip():
          await syncTokens(); // iOS VoIP token rotated
        default:
          break;
      }
    });
  }

  Future<void> _markSession(String? sessionId, String status) async {
    if (sessionId == null || sessionId.isEmpty) return;
    try {
      await _db.from('sessions').update({'status': status}).eq('id', sessionId);
    } catch (_) {}
  }
}
