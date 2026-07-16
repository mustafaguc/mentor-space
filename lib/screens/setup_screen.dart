import 'package:flutter/material.dart';

import '../ui/brand.dart';
import '../ui/widgets.dart';

/// Shown when Supabase keys aren't configured yet, so the app runs and tells
/// you exactly what to do instead of crashing on launch.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 12),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.rocket_launch_rounded,
                  size: 42, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text(
              'Connect Supabase',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              'Two minutes and you are live.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Column(
                children: [
                  _Step(n: '1', text: 'Create a free project at supabase.com'),
                  _Step(
                      n: '2',
                      text:
                          'Open the SQL Editor and run supabase/schema.sql'),
                  _Step(
                      n: '3',
                      text:
                          'Project Settings → API → copy the Project URL and anon public key'),
                  _Step(
                      n: '4',
                      text:
                          'Paste them into lib/config/app_config.dart (or pass with --dart-define), then hot-restart'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Video calling uses meet.jit.si by default — no setup needed for development.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String text;
  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
                gradient: Brand.primaryGradient, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(n,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    height: 1.4, color: Brand.ink, fontSize: 14.5)),
          ),
        ],
      ),
    );
  }
}
