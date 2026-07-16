class CoinTransaction {
  final String id;
  final int amount; // +credit, -debit
  final String type; // topup | spend | earn | refund
  final DateTime createdAt;

  const CoinTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.createdAt,
  });

  bool get isCredit => amount >= 0;

  factory CoinTransaction.fromMap(Map<String, dynamic> m) => CoinTransaction(
        id: m['id'] as String,
        amount: (m['amount'] as int?) ?? 0,
        type: (m['type'] as String?) ?? 'spend',
        createdAt:
            DateTime.tryParse(m['created_at']?.toString() ?? '')?.toLocal() ??
                DateTime.now(),
      );

  String get label {
    switch (type) {
      case 'topup':
        return 'Top up';
      case 'spend':
        return 'Session payment';
      case 'earn':
        return 'Session earnings';
      case 'refund':
        return 'Refund';
      default:
        return type;
    }
  }
}
