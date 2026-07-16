import 'package:flutter/material.dart';

import 'brand.dart';

/// A circular avatar filled with a person-specific gradient and their initials,
/// optionally showing a live online/offline status dot.
class GradientAvatar extends StatelessWidget {
  final String seed;
  final String initials;
  final double radius;
  final bool? online; // null = don't show a status dot

  const GradientAvatar({
    super.key,
    required this.seed,
    required this.initials,
    this.radius = 26,
    this.online,
  });

  @override
  Widget build(BuildContext context) {
    final dot = radius * 0.42;
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        children: [
          Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              gradient: Brand.avatarGradient(seed),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Brand.avatarGradient(seed).colors.first.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.7,
              ),
            ),
          ),
          if (online != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: online! ? const Color(0xFF22C55E) : const Color(0xFFCBD5E1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Full-screen brand gradient, used behind auth screens.
class GradientBackground extends StatelessWidget {
  final Widget child;
  const GradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: Brand.primaryGradient),
      child: SafeArea(child: child),
    );
  }
}

/// Compact read-only rating: a star + average, or "New" when unrated.
class RatingBadge extends StatelessWidget {
  final double average;
  final int count;
  const RatingBadge({super.key, required this.average, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return const TintChip(
        icon: Icons.auto_awesome_rounded,
        label: 'New',
        color: Color(0xFF10B981),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
        const SizedBox(width: 3),
        Text(
          average.toStringAsFixed(1),
          style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 13, color: Brand.ink),
        ),
        const SizedBox(width: 3),
        Text('($count)',
            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
      ],
    );
  }
}

/// Interactive 1–5 star picker used in the post-session rating dialog.
class StarPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const StarPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final filled = i < value;
        return IconButton(
          onPressed: () => onChanged(i + 1),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          constraints: const BoxConstraints(),
          icon: Icon(
            filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 40,
            color: filled ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
          ),
        );
      }),
    );
  }
}

/// Small rounded label chip (icon + text) with a tinted background.
class TintChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const TintChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
