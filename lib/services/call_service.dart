import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Thin wrapper over the Jitsi Meet SDK. Jitsi handles the entire in-call
/// lifecycle (join, mute, camera flip, screen share, hang up, reconnect) and
/// works identically for 1:1 and group rooms — we just pass a room name that
/// both/all participants share.
///
/// When JaaS is configured (AppConfig.usesJaas), the call is routed through
/// https://8x8.vc with a short-lived JWT minted server-side by the
/// `jitsi-token` Edge Function. The JWT marks the user as moderator, so they
/// join instantly instead of getting stuck in meet.jit.si's lobby.
class CallService {
  final _jitsi = JitsiMeet();

  Future<void> join({
    required String roomId,
    required String displayName,
    String? email,
    bool audioOnly = false,
    void Function()? onEnded,
  }) async {
    var serverUrl = AppConfig.jitsiServerUrl;
    var room = roomId;
    String? token;

    if (AppConfig.usesJaas) {
      final res = await Supabase.instance.client.functions.invoke(
        'jitsi-token',
        body: {'room': roomId},
      );
      final data = res.data;
      token = (data is Map) ? data['token'] as String? : null;
      if (token == null) {
        throw Exception('Failed to obtain a call token: $data');
      }
      serverUrl = AppConfig.jaasServerUrl;
      room = '${AppConfig.jaasAppId}/$roomId';
    }

    final options = JitsiMeetConferenceOptions(
      serverURL: serverUrl,
      room: room,
      token: token,
      configOverrides: {
        // Force a clean start state every call. The Jitsi SDK otherwise
        // persists your last mute state and restores it on rejoin (which left
        // the mic stuck muted, and — because video started muted — the camera
        // permission was never even requested).
        'startWithAudioMuted': false,
        'startWithVideoMuted': audioOnly,
        'startAudioOnly': false, // never audio-only mode
        'subject': 'MentorSpace session',
        // Hide Jitsi's built-in toast notifications (e.g. "X is now a
        // moderator") for a cleaner, app-native feel. An empty allow-list
        // means none are shown; disabledNotifications also targets the
        // moderator ones in case the allow-list is ignored on some builds.
        'notifications': <String>[],
        'disabledNotifications': <String>[
          'notify.moderator',
          'notify.grantedTo',
          'notify.grantedToUnknown',
        ],
      },
      featureFlags: {
        'invite.enabled': false,
        'meeting-name.enabled': false,
        'prejoinpage.enabled': false,
        'security-options.enabled': false,
      },
      userInfo: JitsiMeetUserInfo(
        displayName: displayName,
        email: email,
      ),
    );

    // Auto-end the call when everyone else has left (WhatsApp-style): the lone
    // remaining person shouldn't sit in an empty room. We count remote
    // participants rather than track their IDs, because the SDK sometimes
    // reports a null/empty participantId — which previously left the call open.
    var remoteCount = 0;

    final listener = JitsiMeetEventListener(
      participantJoined: (email, name, role, participantId) {
        remoteCount++;
      },
      participantLeft: (participantId) {
        if (remoteCount > 0) remoteCount--;
        // 1:1 -> the other person left; group -> the last one left.
        if (remoteCount <= 0) {
          _jitsi.hangUp(); // triggers conferenceTerminated -> onEnded
        }
      },
      conferenceTerminated: (url, error) => onEnded?.call(),
    );

    await _jitsi.join(options, listener);
  }

  Future<void> hangUp() => _jitsi.hangUp();
}
