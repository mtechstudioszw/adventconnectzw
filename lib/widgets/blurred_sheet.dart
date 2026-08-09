import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// A modal bottom sheet whose backdrop is blurred rather than dimmed flat.
///
/// `showModalBottomSheet` paints `Colors.black54` behind the sheet: an opaque
/// grey wash over whatever you were reading. On a white sheet that reads as a
/// dialog stuck onto a screenshot — it is the single thing that makes an
/// otherwise well-built sheet look cheap, because every surface in the app is
/// carefully lit and then the moment a sheet opens the whole screen goes flat.
///
/// Blurring instead keeps the page underneath *present*: you can still see
/// your feed, out of focus, so the sheet reads as a layer above your content
/// rather than a replacement for it. That is the difference iOS has shipped
/// since 2013 and it is most of what "premium sheet" means.
///
/// The tint is navy at low alpha rather than black. Black over a light grey
/// page turns it muddy; the brand navy keeps it cool and deliberate.
Future<T?> showBlurredSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: false);
  return navigator.push(
    _BlurredSheetRoute<T>(
      builder: builder,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: Colors.transparent,
      // Low alpha because the blur is doing the separating. A heavy scrim on
      // top of a blur just makes the blur invisible.
      modalBarrierColor: AppColors.darkNavy.withValues(alpha: 0.34),
      // Themes do not cross a route boundary on their own, so a sheet pushed
      // this way would otherwise lose the app's palette and text styles.
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel:
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      // Blur is expensive on the low-end Androids most of this audience is
      // on, and it is decoration. Anyone who has asked the system to reduce
      // motion gets the plain scrim.
      blur: AppMotion.enabled(context),
    ),
  );
}

class _BlurredSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _BlurredSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    required this.blur,
    super.capturedThemes,
    super.backgroundColor,
    super.modalBarrierColor,
    super.barrierLabel,
    super.isDismissible,
    super.enableDrag,
  });

  final bool blur;

  @override
  Widget buildModalBarrier() {
    final barrier = super.buildModalBarrier();
    if (!blur) return barrier;

    // Ramped with the sheet's own animation so the page settles out of focus
    // as the sheet rises, instead of snapping. Capped at 12: past that the
    // cost climbs and the effect stops reading as focus and starts reading
    // as fog.
    return AnimatedBuilder(
      animation: animation!,
      builder: (context, child) {
        final t = Curves.easeOut.transform(animation!.value.clamp(0.0, 1.0));
        if (t == 0) return child!;
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12 * t, sigmaY: 12 * t),
          child: child,
        );
      },
      child: barrier,
    );
  }
}
