import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../providers/providers.dart';
import '../services/call_service.dart';
import '../services/push_service.dart';
import '../ui/brand.dart';
import '../ui/widgets.dart';
import 'login_screen.dart';
import 'wallet_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _call = CallService();
  RealtimeChannel? _incoming;
  StreamSubscription<AcceptedCall>? _acceptSub;
  String? _activeSessionId;

  // Set only when *this* user is the client who placed the call, so we know to
  // charge coins + prompt them to rate the mentor once the session ends.
  Profile? _mentorToRate;
  DateTime? _callStartedAt;

  String? _sector; // selected category filter; null = all

  SupabaseClient get _db => Supabase.instance.client;

  bool get _isGuest => _db.auth.currentUser == null;

  void _openLogin() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  /// Tapping call: guests are prompted to log in first; members call directly.
  void _handleCall(Profile mentor) {
    if (_isGuest) {
      _openLogin();
    } else {
      _startCall(mentor);
    }
  }

  @override
  void initState() {
    super.initState();
    _listenForIncomingCalls();
    _listenForAccepts();
  }

  @override
  void dispose() {
    if (_incoming != null) _db.removeChannel(_incoming!);
    _acceptSub?.cancel();
    super.dispose();
  }

  // ---- Realtime: mentor receives a call (foreground fallback) ---------------
  // The native ringing UI (flutter_callkit_incoming) is the primary surface for
  // incoming calls, raised by an FCM/VoIP push even when the app is killed. This
  // Realtime listener is a foreground-only fallback that raises the *same* ring
  // while the app is open — useful before push is configured, and deduped by
  // session id inside PushService so the two paths never double-ring.
  void _listenForIncomingCalls() {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    _incoming = _db
        .channel('incoming-calls-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'mentor_id',
            value: uid,
          ),
          callback: (payload) =>
              PushService.instance.showFromSession(payload.newRecord),
        )
        .subscribe();
  }

  // ---- Accept from the native ringing UI -> join the Jitsi room ------------
  void _listenForAccepts() {
    // Cold start: a call accepted from the ringing UI while the app launched.
    final pending = PushService.instance.takePending();
    if (pending != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _acceptCall(pending));
    }
    _acceptSub = PushService.instance.accepts.listen(_acceptCall);
  }

  Future<void> _acceptCall(AcceptedCall call) async {
    if (!mounted || call.roomId.isEmpty) return;
    if (_activeSessionId == call.sessionId) return; // already joining
    await _joinRoom(call.roomId, call.sessionId, status: 'active');
  }

  /// Fire a push so the mentor's device rings (FCM on Android, VoIP on iOS).
  /// Fire-and-forget: the call proceeds even if the ring push fails.
  Future<void> _notifyCallee(String sessionId, {String action = 'ring'}) async {
    try {
      await _db.functions.invoke('notify-call',
          body: {'sessionId': sessionId, 'action': action});
    } catch (_) {}
  }

  Future<int> _currentBalance() async {
    final uid = _db.auth.currentUser!.id;
    final d = await _db
        .from('wallets')
        .select('balance')
        .eq('user_id', uid)
        .maybeSingle();
    return (d?['balance'] as int?) ?? 0;
  }

  // ---- Client starts a call ------------------------------------------------
  Future<void> _startCall(Profile mentor) async {
    final me = ref.read(myProfileProvider).value;
    final uid = _db.auth.currentUser!.id;

    // Need at least one minute's worth of coins to begin a paid call.
    if (mentor.coinsPerMinute > 0) {
      final balance = await _currentBalance();
      if (balance < mentor.coinsPerMinute) {
        if (!mounted) return;
        _snack(
            'You need ${mentor.coinsPerMinute} coins/min to call ${mentor.displayName}. Top up first.');
        await showTopUpSheet(context, ref);
        return;
      }
    }

    final roomId =
        'mentorspace-${DateTime.now().millisecondsSinceEpoch}-${uid.substring(0, 6)}';
    try {
      final inserted = await _db
          .from('sessions')
          .insert({
            'room_id': roomId,
            'client_id': uid,
            'mentor_id': mentor.id,
            'status': 'pending',
          })
          .select('id')
          .single();
      final sessionId = inserted['id'] as String;
      _mentorToRate = mentor; // we're the client -> rate afterwards
      // Wake the mentor's device (rings even if their app is killed).
      unawaited(_notifyCallee(sessionId));
      if (!mounted) return;
      await _joinRoom(roomId, sessionId,
          status: 'active', displayName: me?.displayName);
    } catch (e) {
      _snack('Could not start call: $e');
    }
  }

  Future<void> _joinRoom(String roomId, String sessionId,
      {required String status, String? displayName}) async {
    _activeSessionId = sessionId;
    _callStartedAt = DateTime.now();
    await _db.from('sessions').update({
      'status': status,
      'started_at': DateTime.now().toIso8601String(),
    }).eq('id', sessionId);

    final name =
        displayName ?? ref.read(myProfileProvider).value?.displayName ?? 'User';

    await _call.join(
      roomId: roomId,
      displayName: name,
      email: _db.auth.currentUser?.email,
      onEnded: _onCallEnded,
    );
  }

  Future<void> _onCallEnded() async {
    final id = _activeSessionId;
    final mentor = _mentorToRate;
    final startedAt = _callStartedAt;
    _activeSessionId = null;
    _mentorToRate = null;
    _callStartedAt = null;
    if (id == null) return;
    // If we were the caller and hung up before the mentor answered, dismiss any
    // ring still showing on their device.
    if (mentor != null) unawaited(_notifyCallee(id, action: 'cancel'));
    await _db.from('sessions').update({
      'status': 'ended',
      'ended_at': DateTime.now().toIso8601String(),
    }).eq('id', id);

    // Only the client who placed the call settles coins + rates the mentor.
    if (mentor != null) {
      await _settleCoins(id, mentor, startedAt);
      ref.invalidate(walletProvider);
      ref.invalidate(transactionsProvider);
      if (mounted) await _promptRating(mentor, id);
    }
  }

  /// Charge the client for the session: ceil(minutes) × the mentor's rate,
  /// capped at the current balance. Moves coins client→mentor atomically via
  /// the spend_coins RPC (definer function, so RLS can't be bypassed).
  Future<void> _settleCoins(
      String sessionId, Profile mentor, DateTime? startedAt) async {
    final rate = mentor.coinsPerMinute;
    if (rate <= 0 || startedAt == null) return;

    final seconds = DateTime.now().difference(startedAt).inSeconds;
    if (seconds <= 0) return;
    final minutes = (seconds / 60).ceil();
    var amount = minutes * rate;

    final balance = await _currentBalance();
    if (amount > balance) amount = balance; // never overdraw
    if (amount <= 0) return;

    try {
      await _db.rpc('spend_coins',
          params: {'p_session_id': sessionId, 'p_amount': amount});
      if (mounted) _snack('$amount coins charged for your session.');
    } catch (e) {
      _snack('Could not charge session: $e');
    }
  }

  Future<void> _promptRating(Profile mentor, String sessionId) async {
    final result = await showDialog<({int stars, String comment})>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RatingDialog(mentor: mentor),
    );
    if (result == null) return; // skipped
    try {
      await _db.from('ratings').insert({
        'session_id': sessionId,
        'mentor_id': mentor.id,
        'client_id': _db.auth.currentUser!.id,
        'stars': result.stars,
        if (result.comment.trim().isNotEmpty) 'comment': result.comment.trim(),
      });
      ref.invalidate(mentorsProvider); // refresh the aggregate
      _snack('Thanks for rating ${mentor.displayName}!');
    } catch (e) {
      _snack('Could not save rating: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _logout() async {
    await PushService.instance.removeTokens();
    await _db.auth.signOut();
  }

  // ---- UI ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final mentors = ref.watch(mentorsProvider);
    final online = ref.watch(onlineUsersProvider).value ?? const <String>{};
    final balance = ref.watch(walletProvider).value ?? 0;
    final me = ref.watch(myProfileProvider).value;
    final myId = _db.auth.currentUser?.id;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(mentorsProvider),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Header(
                  isGuest: myId == null,
                  name: me?.displayName ?? 'there',
                  balance: balance,
                  onLogin: _openLogin,
                  onLogout: _logout,
                  onWallet: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WalletScreen())),
                  onTopUp: () => showTopUpSheet(context, ref),
                ),
              ),
              SliverToBoxAdapter(
                child: _CategoryBar(
                  selected: _sector,
                  onSelect: (s) => setState(() => _sector = s),
                ),
              ),
              mentors.when(
                loading: () => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('Failed to load mentors:\n$e')),
                ),
                data: (list) {
                  final others = list
                      .where((m) => m.id != myId)
                      .where((m) => _sector == null || m.sector == _sector)
                      .toList()
                    ..sort((a, b) {
                      final ao = online.contains(a.id) ? 0 : 1;
                      final bo = online.contains(b.id) ? 0 : 1;
                      return ao.compareTo(bo);
                    });
                  final onlineCount =
                      others.where((m) => online.contains(m.id)).length;

                  if (others.isEmpty) {
                    return _EmptyState(filtered: _sector != null);
                  }

                  return SliverList.builder(
                    itemCount: others.length + 1,
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        return Padding(
                          padding:
                              const EdgeInsets.fromLTRB(20, 4, 20, 12),
                          child: Row(
                            children: [
                              Text(
                                  _sector == null
                                      ? 'Available mentors'
                                      : '${sectorLabel(_sector!)} mentors',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Brand.ink)),
                              const Spacer(),
                              TintChip(
                                icon: Icons.circle,
                                label: '$onlineCount online',
                                color: const Color(0xFF22C55E),
                              ),
                            ],
                          ),
                        );
                      }
                      final m = others[i - 1];
                      return Padding(
                        padding:
                            const EdgeInsets.fromLTRB(20, 0, 20, 14),
                        child: _MentorCard(
                          mentor: m,
                          isOnline: online.contains(m.id),
                          onCall: online.contains(m.id)
                              ? () => _handleCall(m)
                              : null,
                        ),
                      );
                    },
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class _Header extends StatelessWidget {
  final bool isGuest;
  final String name;
  final int balance;
  final VoidCallback onLogin;
  final VoidCallback onLogout;
  final VoidCallback onWallet;
  final VoidCallback onTopUp;
  const _Header({
    required this.isGuest,
    required this.name,
    required this.balance,
    required this.onLogin,
    required this.onLogout,
    required this.onWallet,
    required this.onTopUp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: Brand.primaryGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Brand.indigo.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: isGuest ? _guest() : _member(),
    );
  }

  Widget _guest() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Find your mentor',
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Explore experts by field. Log in when you’re ready to talk.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9), fontSize: 14)),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Brand.indigo,
            ),
            onPressed: onLogin,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Log in / Sign up'),
          ),
        ),
      ],
    );
  }

  Widget _member() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hello, $name 👋',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('Who do you want to talk to?',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 14)),
                  ],
                ),
              ),
              IconButton(
                onPressed: onLogout,
                tooltip: 'Log out',
                icon: const Icon(Icons.logout_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: onWallet,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Text('$balance coins',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded,
                      color: Colors.white70, size: 20),
                  const Spacer(),
                  GestureDetector(
                    onTap: onTopUp,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text('Top up',
                          style: TextStyle(
                              color: Brand.indigo,
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
  }
}

// ---------------------------------------------------------------------------
class _CategoryBar extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelect;
  const _CategoryBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final items = <String?>[null, ...kSectors];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final s = items[i];
          final sel = s == selected;
          final label = s == null ? 'All' : sectorLabel(s);
          final style = s == null
              ? const SectorStyle(Icons.grid_view_rounded, Brand.indigo)
              : SectorStyle.of(s);
          return Center(
            child: GestureDetector(
            onTap: () => onSelect(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: sel ? Brand.primaryGradient : null,
                color: sel ? null : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: sel ? Colors.transparent : const Color(0xFFE5E7EB),
                ),
              ),
              child: Row(
                children: [
                  Icon(style.icon,
                      size: 15, color: sel ? Colors.white : style.color),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: sel ? Colors.white : Brand.ink)),
                ],
              ),
            ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class _MentorCard extends StatelessWidget {
  final Profile mentor;
  final bool isOnline;
  final VoidCallback? onCall;

  const _MentorCard({
    required this.mentor,
    required this.isOnline,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final sector = SectorStyle.of(mentor.sector);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GradientAvatar(
            seed: mentor.id,
            initials: mentor.initials,
            radius: 28,
            online: isOnline,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mentor.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Brand.ink)),
                if (mentor.headline != null && mentor.headline!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(mentor.headline!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF6B7280))),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    RatingBadge(
                        average: mentor.ratingAvg, count: mentor.ratingCount),
                    if (mentor.sector != null && mentor.sector!.isNotEmpty)
                      TintChip(
                        icon: sector.icon,
                        label: mentor.sector!,
                        color: sector.color,
                      ),
                    TintChip(
                      icon: Icons.monetization_on_rounded,
                      label: '${mentor.coinsPerMinute}/min',
                      color: const Color(0xFFF59E0B),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CallButton(enabled: onCall != null, onTap: onCall),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;
  const _CallButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: enabled ? Brand.primaryGradient : null,
          color: enabled ? null : const Color(0xFFEDEFF4),
          shape: BoxShape.circle,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: Brand.indigo.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Icon(
          Icons.videocam_rounded,
          color: enabled ? Colors.white : const Color(0xFFB0B6C3),
          size: 24,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class _RatingDialog extends StatefulWidget {
  final Profile mentor;
  const _RatingDialog({required this.mentor});

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  int _stars = 0;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GradientAvatar(
                seed: widget.mentor.id,
                initials: widget.mentor.initials,
                radius: 34),
            const SizedBox(height: 14),
            Text('How was your session with',
                style: const TextStyle(color: Color(0xFF6B7280))),
            Text(widget.mentor.displayName,
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Brand.ink)),
            const SizedBox(height: 16),
            StarPicker(
              value: _stars,
              onChanged: (v) => setState(() => _stars = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _comment,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Leave a comment (optional)',
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      foregroundColor: const Color(0xFF6B7280),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _stars == 0
                        ? null
                        : () => Navigator.pop(
                            context, (stars: _stars, comment: _comment.text)),
                    child: const Text('Submit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class _EmptyState extends StatelessWidget {
  final bool filtered;
  const _EmptyState({this.filtered = false});

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.groups_rounded, size: 72, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 16),
            Text(filtered ? 'No mentors in this category yet' : 'No mentors yet',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Brand.ink)),
            const SizedBox(height: 8),
            Text(
              filtered
                  ? 'Try another category, or check back soon.'
                  : 'Mentors will appear here as they join. Sign up as a Mentor to be one.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
