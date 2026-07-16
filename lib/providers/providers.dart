import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/coin_transaction.dart';
import '../models/profile.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Emits on every auth change (login/logout/token refresh). The UI reads
/// `currentSession` directly; this just triggers rebuilds.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => _db.auth.onAuthStateChange,
);

/// The signed-in user's own profile (or null if not loaded yet).
final myProfileProvider = FutureProvider.autoDispose<Profile?>((ref) async {
  ref.watch(authStateProvider);
  final uid = _db.auth.currentUser?.id;
  if (uid == null) return null;
  final data = await _db.from('profiles').select().eq('id', uid).maybeSingle();
  return data == null ? null : Profile.fromMap(data);
});

/// All mentors, for the browse list.
final mentorsProvider = FutureProvider.autoDispose<List<Profile>>((ref) async {
  final data = await _db
      .from('profiles')
      .select()
      .eq('role', 'mentor')
      .order('full_name');
  return (data as List)
      .map((e) => Profile.fromMap(e as Map<String, dynamic>))
      .toList();
});

/// Current coin balance.
final walletProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(authStateProvider);
  final uid = _db.auth.currentUser?.id;
  if (uid == null) return 0;
  final data =
      await _db.from('wallets').select('balance').eq('user_id', uid).maybeSingle();
  return (data?['balance'] as int?) ?? 0;
});

/// The caller's coin ledger, newest first.
final transactionsProvider =
    FutureProvider.autoDispose<List<CoinTransaction>>((ref) async {
  ref.watch(authStateProvider);
  final uid = _db.auth.currentUser?.id;
  if (uid == null) return const [];
  final data = await _db
      .from('transactions')
      .select()
      .eq('user_id', uid)
      .order('created_at', ascending: false)
      .limit(100);
  return (data as List)
      .map((e) => CoinTransaction.fromMap(e as Map<String, dynamic>))
      .toList();
});

/// ---------------------------------------------------------------------------
/// PRESENCE — the "who is online right now" system.
///
/// Every signed-in device joins a shared realtime channel and `track()`s its
/// own user id. Supabase syncs the full presence roster to all members, so
/// this stream emits the live set of online user ids. The mentor list crosses
/// this set to show green dots. When a device disconnects (app closed, network
/// lost), Supabase removes it from the roster automatically — no stale "online".
/// ---------------------------------------------------------------------------
final onlineUsersProvider = StreamProvider.autoDispose<Set<String>>((ref) {
  final uid = _db.auth.currentUser?.id;
  final channel = _db.channel('online-users');
  final controller = StreamController<Set<String>>();

  void emit() {
    final ids = <String>{};
    for (final state in channel.presenceState()) {
      for (final presence in state.presences) {
        final id = presence.payload['user_id'];
        if (id is String) ids.add(id);
      }
    }
    controller.add(ids);
  }

  channel
      .onPresenceSync((_) => emit())
      .onPresenceJoin((_) => emit())
      .onPresenceLeave((_) => emit())
      .subscribe((status, error) async {
    if (status == RealtimeSubscribeStatus.subscribed && uid != null) {
      await channel.track({
        'user_id': uid,
        'online_at': DateTime.now().toIso8601String(),
      });
    }
  });

  ref.onDispose(() async {
    await channel.untrack();
    await _db.removeChannel(channel);
    await controller.close();
  });

  return controller.stream;
});
