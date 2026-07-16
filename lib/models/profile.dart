class Profile {
  final String id;
  final String? fullName;
  final String? role; // 'client' | 'mentor' | null (not yet chosen)
  final String? headline;
  final String? bio;
  final String? sector;
  final int coinsPerMinute;
  final String? avatarUrl;
  final double ratingAvg;
  final int ratingCount;

  const Profile({
    required this.id,
    this.fullName,
    this.role,
    this.headline,
    this.bio,
    this.sector,
    this.coinsPerMinute = 0,
    this.avatarUrl,
    this.ratingAvg = 0,
    this.ratingCount = 0,
  });

  bool get isMentor => role == 'mentor';
  bool get hasRole => role == 'client' || role == 'mentor';

  String get displayName =>
      (fullName != null && fullName!.trim().isNotEmpty) ? fullName! : 'User';

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final w = parts.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        fullName: m['full_name'] as String?,
        role: m['role'] as String?,
        headline: m['headline'] as String?,
        bio: m['bio'] as String?,
        sector: m['sector'] as String?,
        coinsPerMinute: (m['coins_per_minute'] as int?) ?? 0,
        avatarUrl: m['avatar_url'] as String?,
        ratingAvg: _toDouble(m['rating_avg']),
        ratingCount: (m['rating_count'] as int?) ?? 0,
      );

  // PostgREST can return numeric as either a num or a string.
  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
