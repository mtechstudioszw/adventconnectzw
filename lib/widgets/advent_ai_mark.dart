import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Advent AI's identity in one place.
///
/// # Why this file exists
///
/// The glyph and the disclaimer were each written out at six call sites —
/// the floating bubble, the transcript, the empty state, the Premium
/// offer card, the Premium allowance row and the paywall sheet. Changing
/// the mark meant finding all six, and the 25 Aug 2026 change ("the icon
/// of Advent AI is ugly, put another one") found five of them. One
/// constant is the fix.
///
/// # The mark
///
/// [icon] was `Icons.auto_awesome_rounded` — the four-point sparkle every
/// AI feature shipped in 2024-2026 uses. The founder's call, and it is
/// the right one: it says "generic AI product" rather than "the assistant
/// in my church app", and it collides with nothing this app does.
///
/// `Icons.assistant_rounded` is a speech bubble with the spark **inside**
/// it. It reads as a conversation first and as AI second, which is the
/// order this feature wants — and a bubble is a shape nothing else in the
/// app claims. The Bible and EGW tabs already own the book glyphs
/// (`menu_book_rounded`, `auto_stories_rounded`), so a book was never
/// available here.
abstract final class AdventAiBrand {
  static const IconData icon = Icons.assistant_rounded;

  static const String name = 'Advent AI';

  /// Shown under **every** answer (founder rule, 25 Aug 2026).
  ///
  /// The empty state already said this once, but a member who has scrolled
  /// into a long answer about depression or divorce is not looking at the
  /// empty state. The claim has to sit where the claim is made.
  static const String disclaimer =
      'Advent AI can make mistakes. Double-check the answer.';
}

/// The one-line "this can be wrong" note that sits under an answer.
class AdventAiDisclaimer extends StatelessWidget {
  const AdventAiDisclaimer({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Text(
        AdventAiBrand.disclaimer,
        style: TextStyle(
          fontSize: 11,
          height: 1.35,
          color: color ?? Theme.of(context).textTheme.bodySmall?.color,
        ),
      ),
    );
  }
}
