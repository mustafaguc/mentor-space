import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'screens/auth_gate.dart';
import 'screens/setup_screen.dart';
import 'services/push_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Push wakeups. Firebase/FCM is only used on Android (iOS rings via PushKit
  // VoIP, handled natively). Wrapped so the app still boots if Firebase isn't
  // configured yet (e.g. before google-services.json has been added).
  var firebaseReady = false;
  if (Platform.isAndroid) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      firebaseReady = true;
    } catch (_) {
      // No Firebase config: killed/background wakeups disabled; the in-app
      // Realtime fallback still rings while the app is open.
    }
  }

  final configured = AppConfig.isConfigured;
  if (configured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
    try {
      await PushService.instance.initApp(firebaseReady: firebaseReady);
    } catch (_) {}
  }

  runApp(ProviderScope(child: MentorSpaceApp(configured: configured)));
}

class MentorSpaceApp extends StatelessWidget {
  final bool configured;
  const MentorSpaceApp({super.key, required this.configured});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MentorSpace',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: configured ? const AuthGate() : const SetupScreen(),
    );
  }
}
