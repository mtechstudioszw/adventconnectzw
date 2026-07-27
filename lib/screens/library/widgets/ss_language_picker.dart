import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/sabbath_school_model.dart';
import '../../../services/sabbath_school_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text_styles.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/motion/brand_spinner.dart';

/// Cinematic Sabbath School language switcher.
///
/// Deliberately the same object as [TranslationPicker], the Bible version
/// switcher: blurred navy overlay, gold overline, glass cards that rise on a
/// stagger, and the chosen card pulsing before the overlay dissolves. Choosing
/// the language you'll read a whole quarter in should feel like the same kind
/// of decision as choosing a Bible translation — it previously used a plain
/// `ListTile` bottom sheet, which read as a settings menu.
///
/// Adventech publishes in ~90 languages, so unlike the translation picker this
/// one carries a search field. Shona leads, then the other priority languages,
/// then everything else alphabetically — the order the service returns.
class SsLanguagePicker extends StatefulWidget {
  const SsLanguagePicker({super.key, required this.current});

  /// Currently selected language code, e.g. `sn`.
  final String current;

  /// Pushes the picker. Resolves to the chosen language code, or null on
  /// dismiss.
  static Future<String?> show(
    BuildContext context, {
    required String current,
  }) {
    return Navigator.of(context).push<String>(
      PageRouteBuilder<String>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) => SsLanguagePicker(current: current),
        transitionsBuilder: (context, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: AppMotion.easeOut,
            reverseCurve: AppMotion.easeIn,
          );
          return FadeTransition(opacity: curved, child: child);
        },
      ),
    );
  }

  @override
  State<SsLanguagePicker> createState() => _SsLanguagePickerState();
}

class _SsLanguagePickerState extends State<SsLanguagePicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  final _searchCtrl = TextEditingController();
  late final Future<List<SsLanguage>> _future =
      SabbathSchoolService.languages();

  String _query = '';
  String? _chosen;

  @override
  void dispose() {
    _c.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _choose(SsLanguage l) async {
    if (_chosen != null) return;
    HapticFeedback.mediumImpact();
    setState(() => _chosen = l.code);
    // Let the selected card's pulse read before the overlay leaves.
    if (AppMotion.enabled(context)) {
      await Future<void>.delayed(const Duration(milliseconds: 240));
    }
    if (!mounted) return;
    Navigator.of(context).pop(l.code);
  }

  List<SsLanguage> _filter(List<SsLanguage> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((l) =>
            l.name.toLowerCase().contains(q) ||
            l.code.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final animate = AppMotion.enabled(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = animate ? _c.value : 1.0;
                  return BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18 * t, sigmaY: 18 * t),
                    child: ColoredBox(
                      color: AppColors.darkNavy.withValues(alpha: 0.82 * t),
                      child: const SizedBox.expand(),
                    ),
                  );
                },
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _header(context),
                _search(context),
                Expanded(
                  child: FutureBuilder<List<SsLanguage>>(
                    future: _future,
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(child: BrandSpinner(size: 28));
                      }
                      final langs = _filter(snap.data!);
                      if (langs.isEmpty) return _noMatches();
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
                        itemCount: langs.length,
                        itemBuilder: (context, i) =>
                            _card(langs[i], i, animate),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STUDY IT IN',
                  style: AppTextStyles.overline.copyWith(
                    color: AppColors.goldAccent,
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Choose a language',
                  style: AppTextStyles.headlineSmall.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, color: AppColors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _search(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        cursorColor: AppColors.goldAccent,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search 90+ languages',
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.white.withValues(alpha: 0.45),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: AppColors.white.withValues(alpha: 0.6),
          ),
          filled: true,
          fillColor: AppColors.white.withValues(alpha: 0.07),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
            borderSide: BorderSide(
              color: AppColors.white.withValues(alpha: 0.16),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
            borderSide: const BorderSide(color: AppColors.goldAccent),
          ),
        ),
      ),
    );
  }

  Widget _noMatches() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'No language matches "${_searchCtrl.text.trim()}".',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.white.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  Widget _card(SsLanguage l, int index, bool animate) {
    final isCurrent = l.code == widget.current;
    final isChosen = l.code == _chosen;

    // Staggered rise: each card starts a beat after the one above it. Capped
    // low so a filtered list of 80 doesn't trickle in forever.
    final start = (index * 0.05).clamp(0.0, 0.6);
    final anim = CurvedAnimation(
      parent: _c,
      curve: Interval(
        start,
        (start + 0.5).clamp(0.0, 1.0),
        curve: AppMotion.easeOut,
      ),
    );

    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final v = animate ? anim.value : 1.0;
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 26 * (1 - v)),
            child: child,
          ),
        );
      },
      child: AnimatedScale(
        scale: isChosen ? 1.04 : 1.0,
        duration: AppMotion.quick,
        curve: AppMotion.spring,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _choose(l),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isChosen || isCurrent
                        ? AppColors.goldAccent
                        : AppColors.white.withValues(alpha: 0.16),
                    width: isChosen || isCurrent ? 2 : 1,
                  ),
                  boxShadow: isChosen
                      ? [
                          BoxShadow(
                            color:
                                AppColors.goldAccent.withValues(alpha: 0.45),
                            blurRadius: 22,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    // The code as a script tile — the same "this is a distinct
                    // book" device the translation picker uses for א / Ω / KJV.
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        l.code.toUpperCase(),
                        style: AppTextStyles.titleSmall.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleSmall.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (l.code == SabbathSchoolService.defaultLanguage)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Default',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.white
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isCurrent && !isChosen)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.goldAccent,
                      ),
                    if (isChosen)
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: AppColors.goldAccent,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
