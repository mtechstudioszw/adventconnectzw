import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Layout tokens — the single source of truth for spacing, corner radii
/// and elevation shadows. Screens must read these instead of hard-coding
/// numbers so the whole app shares one visual rhythm (master reference
/// Part 3: sections breathe at 24, related items sit at 8–12, padding is
/// always 16 or 24 — never random numbers).
class AppSpace {
  AppSpace._();

  /// Hairline gaps inside a tight cluster (icon ↔ label).
  static const double xs = 4;

  /// Related elements inside one section.
  static const double sm = 8;

  /// Default gap between sibling items in a list/section.
  static const double md = 12;

  /// Screen edge padding + gap between distinct blocks.
  static const double lg = 16;

  /// Breathing room between sections.
  static const double xl = 24;

  /// Hero moments — above a headline, around an empty state.
  static const double xxl = 32;

  /// Screen edge inset used by almost every scaffold body.
  static const EdgeInsets screen = EdgeInsets.all(lg);
  static const EdgeInsets screenH = EdgeInsets.symmetric(horizontal: lg);
}

class AppRadius {
  AppRadius._();

  /// Small controls — badges, tiny chips, text-field internals.
  static const double sm = 10;

  /// Buttons + inputs (master reference: BorderRadius.circular(14)).
  static const double button = 14;

  /// Cards (master reference: 16–20).
  static const double card = 16;

  /// Large cards, hero media, bottom sheets.
  static const double lg = 20;

  /// Modal sheets' top corners.
  static const double sheet = 24;

  /// Fully rounded — pills, avatars, chips.
  static const double pill = 100;

  static final BorderRadius smAll = BorderRadius.circular(sm);
  static final BorderRadius buttonAll = BorderRadius.circular(button);
  static final BorderRadius cardAll = BorderRadius.circular(card);
  static final BorderRadius lgAll = BorderRadius.circular(lg);
  static final BorderRadius sheetTop = const BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
  static final BorderRadius pillAll = BorderRadius.circular(pill);
}

/// Shadow recipes derived from the brand navy so elevation reads as a
/// soft tint of the palette instead of generic grey. Dark mode swaps to
/// deeper black shadows automatically via [of].
class AppShadows {
  AppShadows._();

  static const Color _inkLight = Color(0xFF0D1B3E); // darkNavy
  static const Color _inkDark = Color(0xFF000000);

  /// Resting card.
  static List<BoxShadow> card(BuildContext context) => _of(
        context,
        lightAlpha: 0.06,
        darkAlpha: 0.35,
        blur: 16,
        offset: const Offset(0, 6),
      );

  /// Lifted / pressed-adjacent surfaces: FABs, floating bars, dialogs.
  static List<BoxShadow> floating(BuildContext context) => _of(
        context,
        lightAlpha: 0.14,
        darkAlpha: 0.5,
        blur: 24,
        offset: const Offset(0, 10),
      );

  /// Brand-blue glow for the one hero element on a screen (use sparingly
  /// — same rule as gold: one per screen max).
  static List<BoxShadow> glow(BuildContext context) => [
        BoxShadow(
          color: AppColors.primaryBlue.withValues(alpha: 0.30),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> _of(
    BuildContext context, {
    required double lightAlpha,
    required double darkAlpha,
    required double blur,
    required Offset offset,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: (dark ? _inkDark : _inkLight)
            .withValues(alpha: dark ? darkAlpha : lightAlpha),
        blurRadius: blur,
        offset: offset,
      ),
    ];
  }
}
