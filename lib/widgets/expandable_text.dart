import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';
import 'linkified_text.dart';

/// Long text that collapses to [collapsedLines] with a **Read more** /
/// **Read less** toggle under it.
///
/// ## Why this exists
///
/// Three surfaces had three different answers to "what happens when someone
/// writes a wall of text", and none of them was right (founder, 25 Aug
/// 2026):
///
///   * **Posts** had "See more" and nothing to undo it. Once a post was
///     expanded it stayed expanded for the life of the card, so a 2,000
///     character post permanently ate the feed you were trying to scroll.
///   * **Comments** had no truncation at all — one long comment pushed
///     every reply under it off the sheet.
///   * **Chat messages** had none either, so a pasted paragraph filled the
///     whole conversation and buried the messages around it.
///
/// One widget, one behaviour, one pair of labels.
///
/// ## It measures, it does not guess
///
/// The old post card decided the toggle was needed when the body was over
/// 220 characters. That is wrong in both directions — 220 characters of
/// short lines does not clip on a tablet, and 180 characters of one
/// unbroken URL does. This lays the text out with a [TextPainter] at the
/// real width and asks it whether it actually overflowed, so the toggle
/// appears exactly when there is something hidden behind it.
///
/// The measure needs a bounded width. In an unbounded parent (a Row with
/// no Expanded) there is nothing to measure against, so it falls back to
/// the character-count heuristic rather than throwing.
class ExpandableText extends StatefulWidget {
  const ExpandableText({
    super.key,
    required this.text,
    required this.style,
    this.collapsedLines = 6,
    this.toggleColor,
    this.onTapLink,
    this.linkColor,
    this.textAlign,
  });

  final String text;
  final TextStyle style;

  /// How much shows before the fold.
  final int collapsedLines;

  /// Colour of the Read more / Read less label. Defaults to brand blue;
  /// the outgoing chat bubble passes white because blue on that gradient
  /// is unreadable.
  final Color? toggleColor;

  /// Set to linkify URLs in the body. When null the text renders as a
  /// plain [Text] and no link recognisers are built at all.
  final void Function(String url)? onTapLink;
  final Color? linkColor;

  final TextAlign? textAlign;

  /// Fallback for an unbounded width: roughly the point at which
  /// [collapsedLines] of body text stops fitting on a phone.
  static const int _fallbackThreshold = 220;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;

  /// True when the collapsed text would clip at [width].
  bool _overflows(BuildContext context, double width) {
    if (!width.isFinite) {
      return widget.text.length > ExpandableText._fallbackThreshold;
    }
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: widget.collapsedLines,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final exceeded = painter.didExceedMaxLines;
    painter.dispose();
    return exceeded;
  }

  Widget _body() {
    final maxLines = _expanded ? null : widget.collapsedLines;
    final overflow = _expanded ? TextOverflow.clip : TextOverflow.ellipsis;
    final onTapLink = widget.onTapLink;
    if (onTapLink == null) {
      return Text(
        widget.text,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: widget.textAlign,
        style: widget.style,
      );
    }
    return LinkifiedText(
      text: widget.text,
      style: widget.style,
      linkColor: widget.linkColor ?? AppColors.primaryBlue,
      onTapLink: onTapLink,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: widget.textAlign,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final clipped = _overflows(context, constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: AppMotion.maybe(context, AppMotion.standard),
              curve: AppMotion.ease,
              alignment: Alignment.topCenter,
              child: _body(),
            ),
            // Nothing to toggle on text that fits. Once expanded the
            // toggle has to stay — it is the only way back.
            if (clipped)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    _expanded ? 'Read less' : 'Read more',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: widget.toggleColor ?? AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
