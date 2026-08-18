import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/share_config.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Share a verse as a designed IMAGE, not a wall of text.
///
/// This is the single feature people screenshot and post — a plain text share
/// gets lost in a chat, a branded card gets reposted and carries the app name
/// with it. The card is rendered offscreen via [RepaintBoundary] and handed to
/// the OS share sheet as a PNG.
class VerseShareSheet extends StatefulWidget {
  const VerseShareSheet({
    super.key,
    required this.reference,
    required this.text,
    this.attribution = 'KJV',
  });

  /// e.g. "John 3:16", or a book title for an EGW quote.
  final String reference;

  /// The verse body, already cleaned of KJV editorial markup.
  final String text;

  /// The source credit shown in the card's footer, opposite the app mark.
  ///
  /// Defaults to `KJV` because the Bible was the first caller. Parameterised
  /// (founder, 17 Aug) so the same card serves Sabbath School and EGW
  /// quotes — an Ellen White quote has to say **Ellen G. White**, not KJV.
  final String attribution;

  /// Opens the sheet.
  static Future<void> open(
    BuildContext context, {
    required String reference,
    required String text,
    String attribution = 'KJV',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VerseShareSheet(
        reference: reference,
        text: text,
        attribution: attribution,
      ),
    );
  }

  @override
  State<VerseShareSheet> createState() => _VerseShareSheetState();
}

class _VerseShareSheetState extends State<VerseShareSheet> {
  final _boundaryKey = GlobalKey();
  int _style = 0;
  bool _busy = false;

  /// Card backgrounds. All are on-brand (navy / blue / gold / paper) so a
  /// shared card is recognisably from this app.
  static const _styles = <_CardStyle>[
    _CardStyle(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0D1B3E), Color(0xFF1A2F5A)],
      ),
      foreground: AppColors.white,
      accent: AppColors.goldAccent,
    ),
    _CardStyle(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
      ),
      foreground: AppColors.white,
      accent: AppColors.white,
    ),
    _CardStyle(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF7F1E3), Color(0xFFEADFC8)],
      ),
      foreground: Color(0xFF2A2418),
      accent: Color(0xFF9A7B2F),
    ),
    _CardStyle(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF12100E), Color(0xFF2B2622)],
      ),
      foreground: Color(0xFFF2E7D0),
      accent: AppColors.goldAccent,
    ),
  ];

  Future<void> _shareImage() async {
    setState(() => _busy = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('card not laid out');

      // 3x so the PNG stays crisp when a messaging app re-compresses it.
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('encode failed');

      final dir = await getTemporaryDirectory();
      final safeRef = widget.reference.replaceAll(RegExp(r'[^\w]+'), '_');
      final file = File('${dir.path}/verse_$safeRef.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: '${widget.reference} — Adventist Super App\n$appDownloadUrl',
      );
    } catch (_) {
      if (!mounted) return;
      // Falling back to text is strictly better than telling the user it
      // failed — they still get to share the verse.
      await Share.share(_plainText);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareText() => Share.share(_plainText);

  /// The quote as plain text, credited to whoever actually said it.
  ///
  /// The credit used to be the literal string `(KJV)` in both places, which
  /// was right when the Bible was the only caller and became wrong the day
  /// [VerseShareSheet.attribution] was added for Sabbath School and EGW: a
  /// shared Ellen White quote went out attributed to the King James Bible.
  /// The CARD had always been right; only the text share was lying.
  String get _plainText =>
      '"${widget.text}"\n— ${widget.reference} (${widget.attribution})\n\n'
      'Shared from Adventist Super App:\n$appDownloadUrl';

  @override
  Widget build(BuildContext context) {
    final style = _styles[_style];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: RepaintBoundary(
                  key: _boundaryKey,
                  child: _card(style),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _styleRow(),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _shareText,
                    icon: const Icon(Icons.notes_rounded, size: 18),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.white,
                      side: BorderSide(
                          color: AppColors.white.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    label: const Text('Text'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _shareImage,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : const Icon(Icons.image_rounded, size: 18),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    label: Text(_busy ? 'Preparing…' : 'Share image'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The card itself. Square (1:1) because that is what every social surface
  /// crops to without loss.
  ///
  /// Rendered at a FIXED text scale, deliberately ignoring the phone's
  /// font setting. This is an image, not UI: the person receiving it does
  /// not share the sender's accessibility settings, so honouring them
  /// would mean the same verse produced a different picture on every
  /// phone — and at 2.5x the KJV/brand footer row overflowed the square
  /// by 25px, which is what a widget test caught. Font size inside the
  /// card is chosen below, from the verse's own length.
  Widget _card(_CardStyle style) {
    return MediaQuery.withNoTextScaling(child: _cardBody(style));
  }

  Widget _cardBody(_CardStyle style) {
    // Long verses need to step down or they overflow the fixed square.
    final length = widget.text.length;
    final fontSize = length > 320
        ? 15.0
        : length > 220
            ? 17.0
            : length > 130
                ? 19.5
                : 22.0;
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: style.gradient,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.fromLTRB(26, 26, 26, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.format_quote_rounded, color: style.accent, size: 30),
            Expanded(
              child: Center(
                child: Text(
                  widget.text,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: style.foreground,
                    fontSize: fontSize,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(height: 2, width: 34, color: style.accent),
            const SizedBox(height: 10),
            Text(
              widget.reference.toUpperCase(),
              style: AppTextStyles.labelMedium.copyWith(
                color: style.accent,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Flexible: an EGW attribution ("Ellen G. White") is far
                // longer than "KJV", and an unflexed Text in a Row throws
                // rather than clipping.
                Flexible(
                  child: Text(
                    widget.attribution,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: style.foreground.withValues(alpha: 0.55),
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // The app mark. A shared card travels far beyond the app —
                // WhatsApp statuses, church groups — so it has to carry the
                // logo, not just the name (founder, 17 Aug).
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: 0.85,
                      child: Image.asset(
                        'assets/icon/logo.png',
                        width: 16,
                        height: 16,
                        // The mark is a WHITE silhouette, and this is the one
                        // place it is drawn with no navy tile behind it. On
                        // the paper style (#F7F1E3) white-on-cream is
                        // invisible, so tint it to the card's own foreground
                        // — white on the navy/blue/dark cards, dark brown on
                        // paper. srcIn keeps the mark's alpha edges.
                        color: style.foreground,
                        colorBlendMode: BlendMode.srcIn,
                        filterQuality: FilterQuality.high,
                        // Never let a missing asset break the card — it is
                        // rendered to an image, so a broken-image glyph
                        // would ship inside somebody's shared quote.
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Adventist Super App',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: style.foreground.withValues(alpha: 0.55),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _styleRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _styles.length; i++)
          GestureDetector(
            onTap: () => setState(() => _style = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: _styles[i].gradient,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _style == i
                      ? AppColors.white
                      : Colors.white.withValues(alpha: 0.25),
                  width: _style == i ? 2.5 : 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CardStyle {
  const _CardStyle({
    required this.gradient,
    required this.foreground,
    required this.accent,
  });

  final LinearGradient gradient;
  final Color foreground;
  final Color accent;
}
