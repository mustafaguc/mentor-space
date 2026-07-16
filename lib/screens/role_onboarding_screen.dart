import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/providers.dart';
import '../ui/brand.dart';

const _sectors = [
  'education',
  'health',
  'law',
  'tech',
  'agriculture',
  'services',
];

/// Shown once, right after a user's first sign-in (social or email), before
/// they reach the app. This is the single place role is chosen, so the whole
/// sign-in flow is identical for clients and mentors.
class RoleOnboardingScreen extends ConsumerStatefulWidget {
  const RoleOnboardingScreen({super.key});

  @override
  ConsumerState<RoleOnboardingScreen> createState() =>
      _RoleOnboardingScreenState();
}

class _RoleOnboardingScreenState extends ConsumerState<RoleOnboardingScreen> {
  final _name = TextEditingController();
  final _headline = TextEditingController();
  final _rate = TextEditingController(text: '0');
  String? _role;
  String? _sector;
  bool _loading = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _name.dispose();
    _headline.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _show('Please enter your name.');
      return;
    }
    if (_role == null) {
      _show('Please choose how you want to use MentorSpace.');
      return;
    }
    if (_role == 'mentor' && (_sector == null)) {
      _show('Please pick your sector.');
      return;
    }
    setState(() => _loading = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client.from('profiles').upsert({
        'id': uid,
        'full_name': name,
        'role': _role,
        if (_role == 'mentor') 'headline': _headline.text.trim(),
        if (_role == 'mentor') 'sector': _sector,
        if (_role == 'mentor')
          'coins_per_minute': int.tryParse(_rate.text.trim()) ?? 0,
      });
      ref.invalidate(myProfileProvider); // AuthGate advances to Home
    } catch (e) {
      _show('Could not save: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    // Prefill the name from the profile the trigger created (from OAuth).
    final me = ref.watch(myProfileProvider).value;
    if (!_prefilled && me?.fullName != null && me!.fullName!.isNotEmpty) {
      _name.text = me.fullName!;
      _prefilled = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your profile'),
        actions: [
          TextButton(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            child: const Text('Log out'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Text('Welcome! 👋',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Brand.ink)),
          const SizedBox(height: 4),
          const Text('One quick step and you are in.',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 15)),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Your name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 24),
          const Text('How do you want to use MentorSpace?',
              style: TextStyle(fontWeight: FontWeight.w700, color: Brand.ink)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _RoleCard(
                  icon: Icons.person_search_rounded,
                  title: 'Client',
                  subtitle: 'Find & call mentors',
                  selected: _role == 'client',
                  onTap: () => setState(() => _role = 'client'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RoleCard(
                  icon: Icons.school_rounded,
                  title: 'Mentor',
                  subtitle: 'Offer live sessions',
                  selected: _role == 'mentor',
                  onTap: () => setState(() => _role = 'mentor'),
                ),
              ),
            ],
          ),
          // Mentor-only details so they're immediately listable.
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _role == 'mentor' ? _mentorFields() : const SizedBox.shrink(),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white))
                : const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _mentorFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        TextField(
          controller: _headline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Headline',
            hintText: 'e.g. Cardiologist, Tax lawyer, Flutter dev',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          value: _sector,
          decoration: const InputDecoration(
            labelText: 'Sector',
            prefixIcon: Icon(Icons.category_outlined),
          ),
          items: _sectors
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s[0].toUpperCase() + s.substring(1)),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _sector = v),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _rate,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Rate (coins per minute)',
            prefixIcon: Icon(Icons.monetization_on_outlined),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
        decoration: BoxDecoration(
          gradient: selected ? Brand.primaryGradient : null,
          color: selected ? null : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.transparent : const Color(0xFFE5E7EB),
            width: 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Brand.indigo.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(icon, size: 30, color: selected ? Colors.white : Brand.indigo),
            const SizedBox(height: 10),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: selected ? Colors.white : Brand.ink)),
            const SizedBox(height: 2),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    color: selected
                        ? Colors.white.withValues(alpha: 0.9)
                        : const Color(0xFF6B7280))),
          ],
        ),
      ),
    );
  }
}
