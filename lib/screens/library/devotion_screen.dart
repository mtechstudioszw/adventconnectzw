import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../models/devotion_model.dart';
import '../../services/bible_service.dart';
import '../../services/devotion_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/verse_share_card.dart';
import 'bible_tab.dart' show BibleReaderScreen;

/// Today's devotion, in full: the verse, its reference and the Ellen G.
/// White reading with its source.
///
/// Owner, 29 Oct 2026: tapping the devotion on Home (or Today in the
/// Library) opens this, not the Library's Bible tab. It shows exactly what
/// the `todays_devotion` row carries — nothing is padded out or invented —
/// and offers the two things people do next: read the chapter, share.
class DevotionScreen extends StatefulWidget {
  const DevotionScreen({super.key, this.devotion});

  /// Shown at once when the caller already has it; otherwise the cached
  /// copy, then a fetch.
  final Devotion? devotion;

  /// "John 3:16" → "John 3". Falls back to the whole reference.
  static String chapterLabel(String ref) {
    final m = RegExp(r'^(.*?\d+)\s*:').firstMatch(ref.trim());
    return m?.group(1) ?? ref.trim();
  }

  @override
  State<DevotionScreen> createState() => _DevotionScreenState();
}

class _DevotionScreenState extends State<DevotionScreen> {
  Devotion? _devotion;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _devotion = widget.devotion ?? DevotionService.cachedToday();
    if (_devotion == null) {
      _loading = true;
      DevotionService.fetchToday().then((d) {
        if (!mounted) return;
        setState(() {
          _devotion = d;
          _loading = false;
        });
      });
    }
  }

  /// "Read John 3" — the chapter the verse sits in, not just the verse.
  Future<void> _readChapter(Devotion d) async {
    final ref = await BibleService.resolveReference(d.bibleRef);
    if (!mounted) return;
    if (ref == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open ${d.bibleRef} in the Bible.")),
      );
      return;
    }
    // The reader counts chapters and verses from 0; a reference from 1.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BibleReaderScreen(
          book: ref.book,
          chapter: ref.chapter - 1,
          scrollToVerse: ref.verse == null ? null : ref.verse! - 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final d = _devotion;
    return FlatStatusBar(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            "Today's devotion",
            style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 19),
          ),
        ),
        body: SafeArea(
          top: false,
          child: d == null
              ? Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : Padding(
                          padding: AppSpace.screen,
                          child: Text(
                            "Today's devotion isn't available right now. "
                            'Check your connection and try again.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.lg,
                    AppSpace.sm,
                    AppSpace.lg,
                    AppSpace.xxl,
                  ),
                  children: [
                    if ((d.theme ?? '').trim().isNotEmpty) ...[
                      Text(
                        d.theme!.trim(),
                        style: AppTextStyles.headlineSmall.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpace.md),
                    ],
                    ScreenCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '"${d.bibleText}"',
                            style: AppTextStyles.bodyLarge.copyWith(
                              color: palette.text,
                              height: 1.6,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: AppSpace.md),
                          Text(
                            d.bibleRef,
                            style: AppTextStyles.labelLarge.copyWith(
                              color: palette.brandBlue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (d.egwQuote.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpace.lg),
                      ScreenCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ELLEN G. WHITE',
                              style: AppTextStyles.overline.copyWith(
                                color: palette.textMuted,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: AppSpace.sm),
                            Text(
                              d.egwQuote,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: palette.text,
                                height: 1.6,
                              ),
                            ),
                            if (d.egwSource.trim().isNotEmpty) ...[
                              const SizedBox(height: AppSpace.sm),
                              Text(
                                d.egwSource,
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: palette.textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpace.xl),
                    PrimaryGradientButton(
                      label: 'Read ${DevotionScreen.chapterLabel(d.bibleRef)}',
                      icon: Icons.menu_book_rounded,
                      onTap: () => _readChapter(d),
                    ),
                    const SizedBox(height: AppSpace.md),
                    OutlinedButton.icon(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        VerseShareSheet.open(
                          context,
                          reference: d.bibleRef,
                          text: d.bibleText,
                        );
                      },
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Share the verse'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryBlue,
                        minimumSize: const Size.fromHeight(50),
                        side: BorderSide(color: palette.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                        textStyle: AppTextStyles.labelLarge,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
