import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../../../../services/quiz_sfx.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text_styles.dart';
import '../arena_theme.dart';
import 'arena_backdrop.dart';

/// The shell every arena screen sits in.
///
/// No `AppBar`, no scaffold background from the palette — the arena owns
/// the whole surface, edge to edge, with light system icons over navy. The
/// `AnnotatedRegion` reverts the system bars automatically the moment the
/// arena is popped, so the rest of the app is untouched.
class ArenaScaffold extends StatelessWidget {
  const ArenaScaffold({
    super.key,
    required this.child,
    this.title,
    this.onClose,
    this.closeIcon = Icons.close_rounded,
    this.trailing = const [],
    this.showMute = true,
    this.flash,
    this.flashColor = ArenaTheme.correctOnNavy,
    this.backdropIntensity = 1.0,
    this.showTopBar = true,
  });

  final Widget child;
  final String? title;

  /// Defaults to popping the route.
  final VoidCallback? onClose;
  final IconData closeIcon;
  final List<Widget> trailing;
  final bool showMute;
  final Animation<double>? flash;
  final Color flashColor;
  final double backdropIntensity;
  final bool showTopBar;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: ArenaTheme.canvasBottom,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: ArenaTheme.canvasTop,
        // The arena keeps its layout when the keyboard is irrelevant.
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            ArenaBackdrop(
              flash: flash,
              flashColor: flashColor,
              intensity: backdropIntensity,
            ),
            SafeArea(
              child: Column(
                children: [
                  if (showTopBar)
                    ArenaTopBar(
                      title: title,
                      onClose: onClose,
                      closeIcon: closeIcon,
                      trailing: trailing,
                      showMute: showMute,
                    ),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Close · title · actions, in glass over the canvas.
class ArenaTopBar extends StatefulWidget {
  const ArenaTopBar({
    super.key,
    this.title,
    this.onClose,
    this.closeIcon = Icons.close_rounded,
    this.trailing = const [],
    this.showMute = true,
  });

  final String? title;
  final VoidCallback? onClose;
  final IconData closeIcon;
  final List<Widget> trailing;
  final bool showMute;

  @override
  State<ArenaTopBar> createState() => _ArenaTopBarState();
}

class _ArenaTopBarState extends State<ArenaTopBar> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          ArenaIconButton(
            icon: widget.closeIcon,
            tooltip: 'Close',
            onTap: widget.onClose ?? () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: widget.title == null
                ? const SizedBox.shrink()
                : Text(
                    widget.title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: ArenaTheme.textOnNavy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          ...widget.trailing,
          if (widget.showMute) ...[
            if (widget.trailing.isNotEmpty) const SizedBox(width: 8),
            ArenaIconButton(
              icon: QuizSfx.muted
                  ? Icons.volume_off_rounded
                  : Icons.volume_up_rounded,
              tooltip: QuizSfx.muted ? 'Unmute' : 'Mute',
              onTap: () async {
                await QuizSfx.toggleMute();
                if (!QuizSfx.muted) QuizSfx.play(QuizSound.tap);
                if (mounted) setState(() {});
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Circular glass icon button — the arena's answer to [HeaderIconButton].
class ArenaIconButton extends StatelessWidget {
  const ArenaIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 20,
    this.accent,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? ArenaTheme.textOnNavy;
    Widget button = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: ArenaTheme.glass,
            shape: BoxShape.circle,
            border: Border.all(color: ArenaTheme.glassBorder),
          ),
          child: Icon(icon, color: color, size: size),
        ),
      ),
    );
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return Semantics(button: true, label: tooltip, child: button);
  }
}

/// A raised glass panel — the arena's card.
class ArenaPanel extends StatelessWidget {
  const ArenaPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderColor,
    this.gradient,
    this.glow,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Gradient? gradient;
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? ArenaTheme.glass : null,
        gradient: gradient,
        borderRadius: ArenaTheme.cardRadius,
        border: Border.all(color: borderColor ?? ArenaTheme.glassBorder),
        boxShadow: [
          ...ArenaTheme.panelShadow,
          if (glow != null) ...ArenaTheme.glow(glow!, strength: 0.6),
        ],
      ),
      child: child,
    );
  }
}

/// The arena's primary button — gold when it's the moment that matters,
/// blue for everything else.
class ArenaButton extends StatelessWidget {
  const ArenaButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.gold = false,
    this.busy = false,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool gold;
  final bool busy;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    final foreground = gold ? ArenaTheme.canvasTop : Colors.white;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: AnimatedScale(
        scale: 1,
        duration: AppMotion.maybe(context, AppMotion.quick),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient:
                gold ? ArenaTheme.goldGradient : ArenaTheme.actionGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: ArenaTheme.glow(
              gold ? ArenaTheme.gold : const Color(0xFF2B7FE0),
              strength: 0.8,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: enabled
                  ? () {
                      QuizSfx.tap();
                      onTap!();
                    }
                  : null,
              child: Center(
                child: busy
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: foreground,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, color: foreground, size: 19),
                            const SizedBox(width: 9),
                          ],
                          Text(
                            label,
                            style: AppTextStyles.buttonText.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                              letterSpacing: 0.3,
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
