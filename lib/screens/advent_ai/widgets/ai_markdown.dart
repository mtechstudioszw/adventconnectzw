import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../../theme/app_tokens.dart';

/// Renders an Advent AI answer.
///
/// # Why this is hand-written and not a package
///
/// `flutter_markdown` was discontinued in 2025, and the community
/// replacements each bring a parser far larger than this needs. What a
/// model actually emits in this app is a small, predictable subset:
/// headings, paragraphs, bold, italics, bullets, numbered lists, the
/// occasional block quote for scripture, and rarely inline code. That
/// subset is ~200 lines, has no dependency to age out, and — the part
/// that matters — is styled in this app's own tokens rather than fought
/// into them through a theme-mapping layer.
///
/// It renders a *subset* deliberately. Anything unsupported degrades to
/// plain text rather than showing the member raw syntax, which is the
/// one outcome the brief forbids: `**forgiveness**` on screen is worse
/// than no bold at all.
///
/// # Scripture references
///
/// Verse references are detected and tapped through to the Bible reader,
/// because an assistant that names a passage in a Bible app and makes
/// you go and type it in has wasted the best thing it can do.
class AiMarkdown extends StatefulWidget {
  const AiMarkdown({
    super.key,
    required this.text,
    this.onVerseTap,
  });

  final String text;

  /// Called with a reference like "John 3:16". Null disables linking.
  final void Function(String reference)? onVerseTap;

  @override
  State<AiMarkdown> createState() => _AiMarkdownState();
}

/// Stateful only to own the tap recognisers.
///
/// `TapGestureRecognizer` holds native resources and must be disposed.
/// Built from `build()` on a StatelessWidget it never is — and this
/// widget rebuilds on EVERY streamed chunk, so one long answer with a
/// few verse references leaks hundreds of them. The recognisers are
/// therefore cached per reference and torn down with the State.
class _AiMarkdownState extends State<AiMarkdown> {
  final Map<String, TapGestureRecognizer> _recognizers = {};

  @override
  void dispose() {
    for (final r in _recognizers.values) {
      r.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  /// One recogniser per reference, reused across rebuilds.
  TapGestureRecognizer _recognizerFor(String ref) {
    return _recognizers.putIfAbsent(ref, () {
      return TapGestureRecognizer()
        ..onTap = () => widget.onVerseTap?.call(ref);
    });
  }

  String get text => widget.text;
  void Function(String)? get onVerseTap => widget.onVerseTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final blocks = <Widget>[];
    final lines = text.replaceAll('\r\n', '\n').split('\n');

    var paragraph = <String>[];
    var listItems = <(String marker, String body)>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: _inline(context, paragraph.join(' ')),
      ));
      paragraph = [];
    }

    void flushList() {
      if (listItems.isEmpty) return;
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (marker, body) in listItems)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        marker,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: palette.textMuted,
                          height: 1.5,
                        ),
                      ),
                    ),
                    Expanded(child: _inline(context, body)),
                  ],
                ),
              ),
          ],
        ),
      ));
      listItems = [];
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        flushParagraph();
        flushList();
        continue;
      }

      // Headings. Levels collapse to two sizes — a model asked for a
      // short answer will happily emit an h4, and rendering six
      // distinct scales in a chat bubble looks like a document, not a
      // reply.
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        flushParagraph();
        flushList();
        final level = heading.group(1)!.length;
        blocks.add(Padding(
          padding: const EdgeInsets.only(
            top: AppSpace.sm,
            bottom: AppSpace.sm,
          ),
          child: _inline(
            context,
            heading.group(2)!,
            base: (level <= 2
                    ? AppTextStyles.titleMedium
                    : AppTextStyles.titleSmall)
                .copyWith(color: palette.text),
          ),
        ));
        continue;
      }

      // Block quote — what scripture usually arrives as.
      if (trimmed.startsWith('>')) {
        flushParagraph();
        flushList();
        blocks.add(Container(
          margin: const EdgeInsets.only(bottom: AppSpace.md),
          padding: const EdgeInsets.fromLTRB(
              AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
          decoration: BoxDecoration(
            color: palette.chipBg,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border(
              left: BorderSide(color: AppColors.goldAccent, width: 3),
            ),
          ),
          child: _inline(
            context,
            trimmed.replaceFirst(RegExp(r'^>\s?'), ''),
            base: AppTextStyles.bodyMedium.copyWith(
              color: palette.text,
              fontStyle: FontStyle.italic,
              height: 1.55,
            ),
          ),
        ));
        continue;
      }

      // Bullets.
      final bullet = RegExp(r'^[-*•]\s+(.*)$').firstMatch(trimmed);
      if (bullet != null) {
        flushParagraph();
        listItems.add(('•', bullet.group(1)!));
        continue;
      }

      // Numbered.
      final numbered = RegExp(r'^(\d{1,2})[.)]\s+(.*)$').firstMatch(trimmed);
      if (numbered != null) {
        flushParagraph();
        listItems.add(('${numbered.group(1)}.', numbered.group(2)!));
        continue;
      }

      flushList();
      paragraph.add(trimmed);
    }

    flushParagraph();
    flushList();

    if (blocks.isEmpty) return _inline(context, text);

    // The last block's bottom padding is trimmed so a bubble does not
    // carry a gap under its final line.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...blocks.take(blocks.length - 1),
        MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: blocks.last,
        ),
      ],
    );
  }

  /// Inline spans: **bold**, *italic*, `code`, and verse references.
  Widget _inline(BuildContext context, String source, {TextStyle? base}) {
    final palette = context.palette;
    final style = base ??
        AppTextStyles.bodyMedium.copyWith(color: palette.text, height: 1.55);

    return RichText(
      text: TextSpan(
        style: style,
        children: _spans(context, source, style),
      ),
    );
  }

  /// One pass, longest-token-first, so `**bold**` is never mistaken for
  /// two italics.
  List<InlineSpan> _spans(
    BuildContext context,
    String source,
    TextStyle style,
  ) {
    final palette = context.palette;
    final spans = <InlineSpan>[];

    // Bold, italic, code, and a verse reference — matched together so
    // the scan stays single-pass and precedence is explicit.
    final pattern = RegExp(
      r'(\*\*|__)(.+?)\1'                       // bold
      r'|(\*|_)(.+?)\3'                         // italic
      r'|`([^`]+)`'                             // code
      r'|\b((?:[123]\s*)?[A-Z][a-z]+(?:\s+of\s+[A-Z][a-z]+)?'
      r'\.?\s+\d{1,3}(?::\d{1,3}(?:\s*[-–]\s*\d{1,3})?)?)\b',
    );

    var index = 0;
    for (final m in pattern.allMatches(source)) {
      if (m.start > index) {
        spans.add(TextSpan(text: source.substring(index, m.start)));
      }

      if (m.group(2) != null) {
        spans.add(TextSpan(
          text: m.group(2),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ));
      } else if (m.group(4) != null) {
        spans.add(TextSpan(
          text: m.group(4),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else if (m.group(5) != null) {
        spans.add(TextSpan(
          text: m.group(5),
          style: AppTextStyles.bodySmall.copyWith(
            fontFamily: 'monospace',
            color: palette.text,
            backgroundColor: palette.chipBg,
          ),
        ));
      } else if (m.group(6) != null) {
        final ref = m.group(6)!;
        final tap = onVerseTap;
        spans.add(TextSpan(
          text: ref,
          style: TextStyle(
            color: tap == null ? null : AppColors.primaryBlue,
            fontWeight: FontWeight.w600,
          ),
          recognizer: tap == null ? null : _recognizerFor(ref),
        ));
      }

      index = m.end;
    }

    if (index < source.length) {
      spans.add(TextSpan(text: source.substring(index)));
    }
    return spans;
  }
}
