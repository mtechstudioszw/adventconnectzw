import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Renders [text] with any URLs turned into tappable, underlined links.
/// Detects http(s):// and www. URLs; trailing punctuation is left out of
/// the link. [onTapLink] receives the cleaned URL (with https:// added for
/// bare www. links) so the caller can route in-app join links vs external.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText({
    super.key,
    required this.text,
    required this.style,
    required this.linkColor,
    required this.onTapLink,
  });

  final String text;
  final TextStyle style;
  final Color linkColor;
  final void Function(String url) onTapLink;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _recognizers = [];

  static final RegExp _urlRegex =
      RegExp(r'((https?:\/\/|www\.)[^\s]+)', caseSensitive: false);
  static final RegExp _trailing = RegExp(r'[.,!?)\]]+$');

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final text = widget.text;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _urlRegex.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      var url = match.group(0)!;
      var suffix = '';
      final tm = _trailing.firstMatch(url);
      if (tm != null) {
        suffix = tm.group(0)!;
        url = url.substring(0, url.length - suffix.length);
      }
      final target = url.toLowerCase().startsWith('www.') ? 'https://$url' : url;
      final tap = TapGestureRecognizer()
        ..onTap = () => widget.onTapLink(target);
      _recognizers.add(tap);
      spans.add(TextSpan(
        text: url,
        style: widget.style.copyWith(
          color: widget.linkColor,
          decoration: TextDecoration.underline,
          decorationColor: widget.linkColor,
        ),
        recognizer: tap,
      ));
      if (suffix.isNotEmpty) spans.add(TextSpan(text: suffix));
      last = match.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    if (spans.isEmpty) spans.add(TextSpan(text: text));
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
