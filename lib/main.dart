import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'screens/auth_gate.dart';
import 'screens/setup_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final configured = AppConfig.isConfigured;
  if (configured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
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
