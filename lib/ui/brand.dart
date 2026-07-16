import 'package:flutter/material.dart';

/// Central design tokens: colors, gradients, and per-sector styling.
class Brand {
  static const indigo = Color(0xFF6366F1);
  static const violet = Color(0xFF8B5CF6);
  static const purple = Color(0xFFA855F7);
  static const pink = Color(0xFFEC4899);
  static const ink = Color(0xFF14142B);
  static const mist = Color(0xFFF5F6FB);

  static const primaryGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFA855F7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const _avatarPalette = <List<Color>>[
    [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    [Color(0xFFEC4899), Color(0xFFF472B6)],
    [Color(0xFF06B6D4), Color(0xFF3B82F6)],
    [Color(0xFF10B981), Color(0xFF34D399)],
    [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    [Color(0xFFEF4444), Color(0xFFFB7185)],
    [Color(0xFF8B5CF6), Color(0xFFD946EF)],
  ];

  /// Deterministic gradient per person, so an avatar's colors stay stable.
  static LinearGradient avatarGradient(String seed) {
    final pair = _avatarPalette[seed.hashCode.abs() % _avatarPalette.length];
    return LinearGradient(
      colors: pair,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}

/// The mentoring sectors, in display order. Shared by onboarding + browse.
const List<String> kSectors = [
  'education',
  'health',
  'law',
  'tech',
  'agriculture',
  'services',
];

String sectorLabel(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Icon + color for each mentoring sector.
class SectorStyle {
  final IconData icon;
  final Color color;
  const SectorStyle(this.icon, this.color);

  static const _map = <String, SectorStyle>{
    'education': SectorStyle(Icons.school_rounded, Color(0xFF6366F1)),
    'health': SectorStyle(Icons.favorite_rounded, Color(0xFFEF4444)),
    'law': SectorStyle(Icons.gavel_rounded, Color(0xFF8B5CF6)),
    'tech': SectorStyle(Icons.terminal_rounded, Color(0xFF06B6D4)),
    'agriculture': SectorStyle(Icons.eco_rounded, Color(0xFF10B981)),
    'services': SectorStyle(Icons.handshake_rounded, Color(0xFFF59E0B)),
  };

  static SectorStyle of(String? sector) =>
      _map[sector?.toLowerCase()] ??
      const SectorStyle(Icons.category_rounded, Color(0xFF94A3B8));
}
