import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';

/// Renders the small HTML subset used by Sabbath School lesson content as
/// native Flutter text.
///
/// WHY NOT a package: the lesson body only ever uses
/// `h1–h4, p, blockquote, a, em/i, strong/b, sup, small, hr, br, ul/ol/li`.
/// A native renderer is a fraction of the size of a general HTML engine,
/// inherits the app's Poppins/type scale and dark mode for free, and — the
/// real reason — lets `<a class="verse" verse="1Cor1031">` become a TAPPABLE
/// reference that opens the passage inline. A WebView could not do that
/// without breaking the native feel.
///
/// Anything unrecognised degrades to its text content, so a new tag in a
/// future quarterly can never render as blank or as raw markup.
///
/// **Stateful because of the tap recognizers.** A `TextSpan.recognizer` is not
/// owned by the framework — whoever creates it must dispose it. This widget
/// used to be stateless and built `TapGestureRecognizer()` inline for every
/// verse link on every rebuild, leaking one recognizer per reference per
/// frame. Changing the font-size slider on a lesson page with a few dozen
/// references leaks them by the hundred, and the abandoned recognizers stay
/// registered with the gesture arena, which is what surfaced as framework
/// assertions while tearing the reader down. Recognizers are now cached per
/// verse reference and disposed with the widget.
class SsHtmlText extends StatefulWidget {
  const SsHtmlText({
    super.key,
    required this.html,
    required this.fontScale,
    this.textColor,
    this.onVerseTap,
  });

  final String html;
  final double fontScale;
  final Color? textColor;

  /// Called with the raw `verse` attribute (e.g. "1Cor1031") when the reader
  /// taps an inline scripture reference.
  final void Function(String verseRef, String label)? onVerseTap;

  @override
  State<SsHtmlText> createState() => _SsHtmlTextState();
}

class _SsHtmlTextState extends State<SsHtmlText> {
  /// One recognizer per verse reference, reused across rebuilds and disposed
  /// in [dispose]. Keyed by the raw `verse` attribute.
  final Map<String, TapGestureRecognizer> _recognizers = {};

  double get fontScale => widget.fontScale;

  TapGestureRecognizer _recognizerFor(String verseRef, String label) {
    return _recognizers.putIfAbsent(verseRef, TapGestureRecognizer.new)
      // Rebound every build: the callback closes over the current label and
      // the latest onVerseTap, both of which can change between builds.
      ..onTap = () => widget.onVerseTap?.call(verseRef, label);
  }

  @override
  void dispose() {
    for (final r in _recognizers.values) {
      r.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(widget.html);
    final color = widget.textColor ?? context.palette.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks) _buildBlock(context, block, color),
      ],
    );
  }

  Widget _buildBlock(BuildContext context, _Block block, Color color) {
    final palette = context.palette;

    switch (block.kind) {
      case _BlockKind.rule:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Divider(color: palette.divider, height: 1),
        );

      case _BlockKind.heading:
        return Padding(
          padding: EdgeInsets.only(top: block.level <= 2 ? 24 : 20, bottom: 8),
          child: RichText(
            text: _spanFor(
              context,
              block.inlines,
              base: AppTextStyles.titleMedium.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: (block.level <= 2 ? 20.0 : 17.0) * fontScale,
                height: 1.35,
              ),
            ),
          ),
        );

      case _BlockKind.quote:
        // Memory text / pull quotes — the visual anchor of each day.
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 14),
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: AppColors.goldAccent.withValues(alpha: 0.09),
            border: const Border(
              left: BorderSide(color: AppColors.goldAccent, width: 3),
            ),
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(12)),
          ),
          child: RichText(
            text: _spanFor(
              context,
              block.inlines,
              base: AppTextStyles.bodyLarge.copyWith(
                color: color,
                fontSize: 16 * fontScale,
                height: 1.75,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        );

      case _BlockKind.listItem:
        return Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 7 * fontScale, right: 10),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryBlue,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(
                child: RichText(
                  text: _spanFor(
                    context,
                    block.inlines,
                    base: _bodyStyle(color),
                  ),
                ),
              ),
            ],
          ),
        );

      case _BlockKind.paragraph:
        if (block.inlines.every((i) => i.text.trim().isEmpty)) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: RichText(
            text: _spanFor(context, block.inlines, base: _bodyStyle(color)),
          ),
        );
    }
  }

  TextStyle _bodyStyle(Color color) => AppTextStyles.bodyLarge.copyWith(
        color: color,
        fontSize: 16 * fontScale,
        height: 1.78,
      );

  TextSpan _spanFor(
    BuildContext context,
    List<_Inline> inlines, {
    required TextStyle base,
  }) {
    return TextSpan(
      children: [
        for (final inline in inlines)
          if (inline.verseRef != null)
            TextSpan(
              text: inline.text,
              style: base.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w600,
              ),
              recognizer: _recognizerFor(inline.verseRef!, inline.text),
            )
          else
            TextSpan(
              text: inline.text,
              style: base.copyWith(
                fontWeight: inline.bold ? FontWeight.w700 : base.fontWeight,
                fontStyle: inline.italic ? FontStyle.italic : base.fontStyle,
                fontSize: inline.small
                    ? (base.fontSize ?? 16) * 0.82
                    : base.fontSize,
                // <sup> can't shift the baseline in a plain TextSpan, so
                // verse numbers are rendered small + bold + blue instead —
                // it reads as a verse marker without layout gymnastics.
                color: inline.superscript
                    ? AppColors.primaryBlue
                    : base.color,
              ),
            ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Parsing
// ---------------------------------------------------------------------------

enum _BlockKind { paragraph, heading, quote, rule, listItem }

class _Block {
  _Block(this.kind, this.inlines, {this.level = 3});
  final _BlockKind kind;
  final List<_Inline> inlines;
  final int level;
}

class _Inline {
  _Inline(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.small = false,
    this.superscript = false,
    this.verseRef,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool small;
  final bool superscript;
  final String? verseRef;
}

/// Splits the document into block-level chunks, then parses each one's
/// inline runs. Deliberately regex-based: the input is machine-generated by
/// one publisher, so a full HTML parser would be over-engineering.
List<_Block> _parseBlocks(String html) {
  final blocks = <_Block>[];

  // Normalise away wrappers and whitespace-only noise first.
  var doc = html
      .replaceAll(RegExp(r'<div[^>]*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'</div>', caseSensitive: false), '')
      .replaceAll('\r\n', '\n');

  final pattern = RegExp(
    r'<(h[1-6]|p|blockquote|li|hr)\b[^>]*>(.*?)</\1>|<hr\s*/?>',
    caseSensitive: false,
    dotAll: true,
  );

  var lastEnd = 0;
  for (final m in pattern.allMatches(doc)) {
    // Loose text between recognised blocks (the API emits some) becomes a
    // paragraph rather than vanishing.
    final between = doc.substring(lastEnd, m.start);
    final betweenText = _stripTags(between).trim();
    if (betweenText.isNotEmpty) {
      blocks.add(_Block(_BlockKind.paragraph, _parseInlines(between)));
    }
    lastEnd = m.end;

    final tag = (m.group(1) ?? 'hr').toLowerCase();
    final inner = m.group(2) ?? '';

    if (tag == 'hr') {
      blocks.add(_Block(_BlockKind.rule, const []));
    } else if (tag.startsWith('h')) {
      blocks.add(_Block(
        _BlockKind.heading,
        _parseInlines(inner),
        level: int.tryParse(tag.substring(1)) ?? 3,
      ));
    } else if (tag == 'blockquote') {
      // A blockquote usually wraps its own <p>s — flatten them so the quote
      // renders as one styled body instead of nesting boxes.
      blocks.add(_Block(_BlockKind.quote, _parseInlines(inner)));
    } else if (tag == 'li') {
      blocks.add(_Block(_BlockKind.listItem, _parseInlines(inner)));
    } else {
      blocks.add(_Block(_BlockKind.paragraph, _parseInlines(inner)));
    }
  }

  final tail = _stripTags(doc.substring(lastEnd)).trim();
  if (tail.isNotEmpty) {
    blocks.add(_Block(_BlockKind.paragraph, _parseInlines(doc.substring(lastEnd))));
  }

  if (blocks.isEmpty) {
    final plain = _stripTags(doc).trim();
    if (plain.isNotEmpty) {
      blocks.add(_Block(_BlockKind.paragraph, [_Inline(plain)]));
    }
  }
  return blocks;
}

/// Walks inline markup, carrying style flags down through nesting.
List<_Inline> _parseInlines(String html) {
  final out = <_Inline>[];

  final tagPattern = RegExp(
    r'<(/?)(a|em|i|strong|b|sup|small|br)\b([^>]*)>',
    caseSensitive: false,
  );

  var bold = 0;
  var italic = 0;
  var small = 0;
  var sup = 0;
  String? verseRef;

  void emit(String raw) {
    final text = _decodeEntities(raw);
    if (text.isEmpty) return;
    out.add(_Inline(
      text,
      bold: bold > 0,
      italic: italic > 0,
      small: small > 0,
      superscript: sup > 0,
      verseRef: verseRef,
    ));
  }

  var cursor = 0;
  for (final m in tagPattern.allMatches(html)) {
    emit(_stripTags(html.substring(cursor, m.start)));
    cursor = m.end;

    final closing = m.group(1) == '/';
    final tag = m.group(2)!.toLowerCase();
    final attrs = m.group(3) ?? '';

    switch (tag) {
      case 'br':
        out.add(_Inline('\n'));
      case 'em':
      case 'i':
        italic += closing ? -1 : 1;
      case 'strong':
      case 'b':
        bold += closing ? -1 : 1;
      case 'small':
        small += closing ? -1 : 1;
      case 'sup':
        sup += closing ? -1 : 1;
      case 'a':
        if (closing) {
          verseRef = null;
        } else {
          // Only `class="verse"` anchors are made tappable; the API also
          // emits plain links we render as ordinary text.
          final verse = RegExp('verse="([^"]*)"', caseSensitive: false)
              .firstMatch(attrs)
              ?.group(1);
          verseRef = (verse != null && verse.isNotEmpty) ? verse : null;
        }
    }
    // Clamp so malformed markup can't leave a style stuck on.
    bold = bold.clamp(0, 9);
    italic = italic.clamp(0, 9);
    small = small.clamp(0, 9);
    sup = sup.clamp(0, 9);
  }
  emit(_stripTags(html.substring(cursor)));

  return out.isEmpty ? [_Inline(_decodeEntities(_stripTags(html)))] : out;
}

String _stripTags(String html) =>
    html.replaceAll(RegExp(r'<[^>]*>'), '');

/// Lesson HTML as plain readable text.
///
/// Public because the share card needs it: a verse taken from the day's
/// `bible` map is HTML, and putting raw markup on a shared image would be
/// visible to everyone the member sends it to. Reuses the entity table
/// below rather than duplicating it — the feed uses named entities that a
/// naive tag-strip leaves as `&mdash;` in the middle of a sentence.
String ssPlainText(String html) =>
    _decodeEntities(_stripTags(html)).replaceAll(RegExp(r'\s+'), ' ').trim();

/// The lesson feed uses a handful of named entities plus numeric ones.
String _decodeEntities(String input) {
  var s = input
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&mdash;', '—')
      .replaceAll('&ndash;', '–')
      .replaceAll('&hellip;', '…')
      .replaceAll('&rsquo;', '’')
      .replaceAll('&lsquo;', '‘')
      .replaceAll('&ldquo;', '“')
      .replaceAll('&rdquo;', '”');
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });
  // Collapse the newlines the source uses for readability, but keep the
  // explicit ones <br> injected.
  return s.replaceAll(RegExp(r'[ \t]*\n[ \t]*'), ' ');
}
