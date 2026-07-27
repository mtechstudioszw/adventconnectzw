import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../motion/pressable.dart';

/// Everything a member can put into the app from Home.
enum CreateKind { post, story, event, prayer, news, notice, job, product }

/// Facebook-style "what do you want to share?" chooser, as a full screen.
///
/// The composer row used to go straight to a text post, which quietly hid
/// seven other things a member can create — events, prayer requests, news
/// submissions, notices, jobs and marketplace listings all lived behind
/// separate tabs most people never opened.
///
/// Presented as a blurred full-screen overlay rather than a bottom sheet so
/// it reads as a deliberate moment: Home stays visible but recedes behind the
/// blur, the tiles spring in on a stagger, and the whole thing reverses on
/// the way out. Every animation is driven by the route's own animation, so
/// dismissing plays the entrance backwards instead of cutting.
///
/// Returns the chosen kind, or null if dismissed. Deliberately presentational
/// — the caller owns navigation, because posts and stories come back with a
/// value the feed needs and the rest are plain route pushes.
Future<CreateKind?> showCreateSheet(BuildContext context) {
  return showGeneralDialog<CreateKind>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close create menu',
    // We paint our own scrim so it can fade in step with the blur.
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (context, animation, _) =>
        _CreateScreen(animation: animation),
  );
}

@immutable
class _Option {
  const _Option(this.kind, this.icon, this.title, this.subtitle);
  final CreateKind kind;
  final IconData icon;
  final String title;
  final String subtitle;
}

class _CreateScreen extends StatelessWidget {
  const _CreateScreen({required this.animation});

  final Animation<double> animation;

  static const _options = <_Option>[
    _Option(CreateKind.post, Icons.edit_outlined, 'Post', 'Share an update'),
    _Option(
      CreateKind.story,
      Icons.auto_awesome_outlined,
      'Story',
      'Gone in 24 hours',
    ),
    _Option(
      CreateKind.event,
      Icons.event_outlined,
      'Event',
      'Invite people along',
    ),
    _Option(
      CreateKind.prayer,
      Icons.volunteer_activism_outlined,
      'Prayer request',
      'Ask for prayer',
    ),
    _Option(
      CreateKind.notice,
      Icons.campaign_outlined,
      'Church notice',
      'Tell your local church',
    ),
    _Option(
      CreateKind.news,
      Icons.newspaper_outlined,
      'Advent News',
      'Reviewed before it goes live',
    ),
    _Option(
      CreateKind.product,
      Icons.storefront_outlined,
      'Sell something',
      'List on the marketplace',
    ),
    _Option(
      CreateKind.job,
      Icons.work_outline_rounded,
      'Job opening',
      'Post an opportunity',
    ),
  ];

  /// Per-tile progress: tile [i] starts [i * 0.05] into the route animation
  /// and takes 55% of it to land. Capped so the last tile isn't still
  /// arriving after the route has settled.
  double _tileT(int i) {
    final start = (i * 0.05).clamp(0.0, 0.40);
    return ((animation.value - start) / 0.55).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final animate = AppMotion.enabled(context);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animate
            ? Curves.easeOutCubic.transform(animation.value.clamp(0.0, 1.0))
            : 1.0;

        return Stack(
          children: [
            // Scrim + blur. Tapping anywhere off the tiles closes.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18 * t, sigmaY: 18 * t),
                  child: ColoredBox(
                    color: AppColors.darkNavy.withValues(alpha: 0.55 * t),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, -16 * (1 - t)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.xl,
                          AppSpace.lg,
                          AppSpace.lg,
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
                                    'CREATE',
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: AppColors.white.withValues(
                                        alpha: 0.7,
                                      ),
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.8,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpace.xs),
                                  Text(
                                    'What would you\nlike to share?',
                                    style: AppTextStyles.displayMedium.copyWith(
                                      color: AppColors.white,
                                      height: 1.15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpace.md),
                            _CloseButton(
                              onTap: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.lg,
                        AppSpace.md,
                        AppSpace.lg,
                        AppSpace.xl,
                      ),
                      child: Wrap(
                        spacing: AppSpace.md,
                        runSpacing: AppSpace.md,
                        children: [
                          for (var i = 0; i < _options.length; i++)
                            _Tile(
                              option: _options[i],
                              // Two per row, minus the spacing between them.
                              width: (MediaQuery.sizeOf(context).width -
                                      AppSpace.lg * 2 -
                                      AppSpace.md) /
                                  2,
                              t: animate ? _tileT(i) : 1.0,
                              palette: palette,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.option,
    required this.width,
    required this.t,
    required this.palette,
  });

  final _Option option;
  final double width;
  final double t;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    // Springs up and settles, rather than simply fading.
    final eased = Curves.easeOutBack.transform(t.clamp(0.0, 1.0));
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 28 * (1 - t)),
        child: Transform.scale(
          scale: 0.88 + 0.12 * eased,
          child: SizedBox(
            width: width,
            child: Pressable(
              haptics: true,
              pressedScale: 0.94,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop(option.kind);
              },
              child: Container(
                padding: const EdgeInsets.all(AppSpace.lg),
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(AppRadius.button),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryBlue.withValues(
                              alpha: 0.32,
                            ),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        option.icon,
                        size: 22,
                        color: AppColors.white,
                      ),
                    ),
                    const SizedBox(height: AppSpace.md),
                    Text(
                      option.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: palette.textMuted,
                        height: 1.3,
                      ),
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

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close',
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.88,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.16),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.white.withValues(alpha: 0.24),
            ),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.close_rounded,
            color: AppColors.white,
            size: 21,
          ),
        ),
      ),
    );
  }
}
