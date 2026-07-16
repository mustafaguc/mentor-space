import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/coin_transaction.dart';
import '../providers/providers.dart';
import '../ui/brand.dart';

/// Opens the top-up bottom sheet. Returns true if coins were added.
Future<bool> showTopUpSheet(BuildContext context, WidgetRef ref) async {
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _TopUpSheet(),
  );
  if (added == true) {
    ref.invalidate(walletProvider);
    ref.invalidate(transactionsProvider);
  }
  return added == true;
}

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(walletProvider).value ?? 0;
    final txns = ref.watch(transactionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(walletProvider);
          ref.invalidate(transactionsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _BalanceCard(
              balance: balance,
              onTopUp: () => showTopUpSheet(context, ref),
            ),
            const SizedBox(height: 24),
            const Text('History',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Brand.ink)),
            const SizedBox(height: 8),
            txns.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not load history:\n$e'),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text('No transactions yet.',
                          style: TextStyle(color: Color(0xFF6B7280))),
                    ),
                  );
                }
                return Column(
                  children: list.map((t) => _TxnTile(txn: t)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final int balance;
  final VoidCallback onTopUp;
  const _BalanceCard({required this.balance, required this.onTopUp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your balance',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.monetization_on_rounded,
                  color: Colors.white, size: 34),
              const SizedBox(width: 8),
              Text('$balance',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text('coins',
                    style: TextStyle(color: Colors.white70, fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Brand.indigo,
              ),
              onPressed: onTopUp,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Top up'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  final CoinTransaction txn;
  const _TxnTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final credit = txn.isCredit;
    final color = credit ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final icon = switch (txn.type) {
      'topup' => Icons.add_card_rounded,
      'earn' => Icons.call_received_rounded,
      'spend' => Icons.videocam_rounded,
      'refund' => Icons.undo_rounded,
      _ => Icons.swap_horiz_rounded,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(txn.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: Brand.ink)),
                Text(_fmt(txn.createdAt),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
          Text('${credit ? '+' : ''}${txn.amount}',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16, color: color)),
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
  }
}

class _TopUpSheet extends ConsumerStatefulWidget {
  const _TopUpSheet();

  @override
  ConsumerState<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends ConsumerState<_TopUpSheet> {
  static const _presets = [100, 500, 1000, 2500];
  int _selected = 500;
  bool _loading = false;

  Future<void> _topUp() async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client
          .rpc('topup_coins', params: {'p_amount': _selected});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Top up failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Add coins',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Brand.ink)),
          const SizedBox(height: 4),
          const Text('Choose an amount to add to your wallet.',
              style: TextStyle(color: Color(0xFF6B7280))),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _presets.map((amount) {
              final sel = amount == _selected;
              return GestureDetector(
                onTap: () => setState(() => _selected = amount),
                child: Container(
                  width: (MediaQuery.of(context).size.width - 40 - 12) / 2,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    gradient: sel ? Brand.primaryGradient : null,
                    color: sel ? null : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color:
                          sel ? Colors.transparent : const Color(0xFFE5E7EB),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.monetization_on_rounded,
                          size: 20,
                          color: sel ? Colors.white : const Color(0xFFF59E0B)),
                      const SizedBox(width: 8),
                      Text('$amount',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: sel ? Colors.white : Brand.ink)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading ? null : _topUp,
            child: _loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white))
                : Text('Add $_selected coins'),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('Demo top-up — no real charge.',
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          ),
        ],
      ),
    );
  }
}
