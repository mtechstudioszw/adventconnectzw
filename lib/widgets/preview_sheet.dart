import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'motion/pressable.dart';
import 'studio/artboard.dart';

/// One line of the "before you publish" checklist under a preview —
/// who sees it, who it's from, what's attached.
@immutable
class PreviewNote {
  const PreviewNote(this.icon, this.label, {this.warn = false});

  final IconData icon;
  final String label;

  /// Worth a second look before publishing (no photo on a listing, a
  /// post right at the length limit). Shown muted with an info glyph —
  /// red is for errors only, and none of these are errors.
  final bool warn;
}

/// "See it before you send it", for anything a member can publish.
///
/// The post composer already had a preview and it was the most-praised
/// thing on that screen — so stories, events, products and news get the
/// same deal rather than one privileged content type.
///
/// The rule that makes a preview worth having: **render the REAL card**,
/// on the real background it will sit on. A lookalike drifts from the
/// thing it stands in for the moment either changes, and then it quietly
/// lies about the two things people actually check — where the text wraps
/// and how the photos crop.
///
/// ## Studio redesign (28 Oct 2026)
///
/// Same promise, now a proofing desk rather than a plain sheet:
/// - the card sits on the studio's dot-grid artboard;
/// - **Light / Dark** re-renders it in the other theme, because about half
///   the people who see it will be in the one you're not using;
/// - **Large text** re-renders it at 1.3× — what members with bigger
///   system fonts will get, and where long titles break;
/// - [notes] list what the card can't show: audience, identity, what's
///   attached.
///
/// Returns `true` when the member confirms from here, so the composer can
/// publish without making them go back first.
Future<bool> showEntityPreview(
  BuildContext context, {

  /// What is being previewed — "How your event will look".
  required String title,

  /// The real card, built from what's in the composer right now.
  required Widget child,

  /// The confirm button. "Post it" / "List it" / "Publish".
  required String confirmLabel,

  /// Background behind the card. Defaults to the feed's scaffold colour
  /// in whichever theme is being previewed; pass the surface the card will
  /// really sit on if it differs. A fixed colour also hides the theme
  /// switch — a story looks the same in both.
  Color? canvasColor,

  /// The checklist under the card.
  List<PreviewNote> notes = const [],
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PreviewSheet(
      title: title,
      confirmLabel: confirmLabel,
      canvasColor: canvasColor,
      notes: notes,
      child: child,
    ),
  );
  return result ?? false;
}

class _PreviewSheet extends StatefulWidget {
  const _PreviewSheet({
    required this.title,
    required this.confirmLabel,
    required this.child,
    required this.notes,
    this.canvasColor,
  });

  final String title;
  final String confirmLabel;
  final Widget child;
  final Color? canvasColor;
  final List<PreviewNote> notes;

  @override
  State<_PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends State<_PreviewSheet> {
  /// Null until the first build, then the app's own brightness.
  bool? _dark;
  bool _large = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final media = MediaQuery.of(context);
    final appDark = Theme.of(context).brightness == Brightness.dark;
    final dark = _dark ?? appDark;
    final previewTheme = dark ? AppTheme.dark : AppTheme.light;
    final previewPalette = dark ? AppPalette.dark : AppPalette.light;
    final baseScale = media.textScaler;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: AppRadius.sheetTop,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpace.md),
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.sm,
                AppSpace.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'PREVIEW',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: palette.brandBlue,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.title,
                          style: AppTextStyles.titleLarge.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Back to editing',
                    icon: Icon(Icons.close_rounded, color: palette.text),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            // The proofing controls.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                0,
                AppSpace.lg,
                AppSpace.md,
              ),
              child: Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  if (widget.canvasColor == null)
                    _Segmented(
                      semanticsLabel: 'Preview theme',
                      options: const [
                        (Icons.light_mode_outlined, 'Light'),
                        (Icons.dark_mode_outlined, 'Dark'),
                      ],
                      selected: dark ? 1 : 0,
                      onSelect: (i) => setState(() => _dark = i == 1),
                    ),
                  _Segmented(
                    semanticsLabel: 'Preview text size',
                    options: const [
                      (Icons.text_fields_rounded, 'Normal'),
                      (Icons.format_size_rounded, 'Large text'),
                    ],
                    selected: _large ? 1 : 0,
                    onSelect: (i) => setState(() => _large = i == 1),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StudioArtboard(
                      background:
                          widget.canvasColor ?? previewPalette.scaffoldBg,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpace.lg,
                      ),
                      // Deliberately NOT wrapped in IgnorePointer. Blanket-
                      // blocking pointers here is what stopped a multi-photo
                      // post's carousel from paging — the preview showed
                      // photo one and there was no way to reach the rest,
                      // which is precisely what the preview exists to check.
                      child: Theme(
                        data: previewTheme,
                        child: MediaQuery(
                          data: media.copyWith(
                            textScaler: _large
                                ? TextScaler.linear(
                                    (baseScale.scale(14) / 14) * 1.3,
                                  )
                                : baseScale,
                          ),
                          child: DefaultTextStyle(
                            style:
                                previewTheme.textTheme.bodyMedium ??
                                const TextStyle(),
                            child: widget.child,
                          ),
                        ),
                      ),
                    ),
                    if (widget.notes.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.md),
                      _Checklist(notes: widget.notes),
                    ],
                    const SizedBox(height: AppSpace.sm),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                AppSpace.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Pressable(
                      onTap: () => Navigator.of(context).pop(false),
                      pressedScale: 0.97,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.card,
                          borderRadius: AppRadius.buttonAll,
                          border: Border.all(color: palette.divider),
                        ),
                        child: Text(
                          'Keep editing',
                          style: AppTextStyles.buttonText.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Pressable(
                      onTap: () => Navigator.of(context).pop(true),
                      haptics: true,
                      pressedScale: 0.97,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: AppRadius.buttonAll,
                          boxShadow: AppShadows.glow(context),
                        ),
                        child: Text(
                          widget.confirmLabel,
                          style: AppTextStyles.buttonText.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A two-way pill switch.
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.semanticsLabel,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final String semanticsLabel;
  final List<(IconData, String)> options;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: semanticsLabel,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: palette.chipBg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++)
              Semantics(
                button: true,
                selected: i == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: i == selected ? palette.card : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: i == selected
                          ? AppShadows.card(context)
                          : const [],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          options[i].$1,
                          size: 15,
                          color: i == selected
                              ? palette.brandBlue
                              : palette.textMuted,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          options[i].$2,
                          style: AppTextStyles.caption.copyWith(
                            color: i == selected
                                ? palette.text
                                : palette.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist({required this.notes});

  final List<PreviewNote> notes;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BEFORE YOU PUBLISH',
            style: AppTextStyles.labelSmall.copyWith(
              color: palette.textMuted,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    n.warn ? Icons.info_outline_rounded : n.icon,
                    size: 18,
                    color: n.warn ? palette.textMuted : palette.brandBlue,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      n.label,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.text,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
