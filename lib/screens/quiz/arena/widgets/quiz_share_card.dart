import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../config/share_config.dart';
import '../../../../models/quiz_round.dart';
import '../../../../theme/app_text_styles.dart';
import '../arena_theme.dart';

/// Renders a result as a branded image and shares it.
///
/// The card is built off-screen rather than screenshotting the results
/// screen: a screenshot would be the wrong aspect ratio for WhatsApp, would
/// capture whatever animation frame happened to be showing, and would leak
/// the buttons. This draws a purpose-made 1080×1350 card instead.
class QuizShareCard {
  QuizShareCard._();

  /// Portrait 4:5 — what WhatsApp and Instagram render largest.
  static const Size cardSize = Size(1080, 1350);

  /// Build, capture and open the share sheet. Returns false if the capture
  /// failed, so the caller can fall back to plain text.
  static Future<bool> share(
    BuildContext context,
    QuizRoundResult result, {
    String? playerName,
  }) async {
    try {
      final bytes = await _capture(
        _ShareCardView(result: result, playerName: playerName),
        context,
      );
      if (bytes == null) return false;

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/quiz_score_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: '${_headline(result)}\n\n'
            'Play the Bible Quiz on Adventist Super App:\n$appDownloadUrl',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _headline(QuizRoundResult result) {
    if (result.mode == QuizMode.survival) {
      return 'I survived ${result.correctCount} questions in the '
          'Adventist Super App Bible Quiz!';
    }
    return 'I scored ${result.points} points '
        '(${result.correctCount}/${result.total}) in the '
        'Adventist Super App Bible Quiz!';
  }

  /// Rasterises [child] at [cardSize] without ever attaching it to the
  /// visible tree.
  ///
  /// This is the fiddly part: a widget that was never laid out has no
  /// RenderObject to capture, so we spin up our own pipeline owner and
  /// drive layout/paint by hand.
  static Future<Uint8List?> _capture(
    Widget child,
    BuildContext context,
  ) async {
    final repaintBoundary = RenderRepaintBoundary();
    final view = View.of(context);

    final renderView = RenderView(
      view: view,
      child: RenderPositionedBox(
        alignment: Alignment.center,
        child: repaintBoundary,
      ),
      configuration: ViewConfiguration(
        physicalConstraints: BoxConstraints.tight(cardSize) * view.devicePixelRatio,
        logicalConstraints: BoxConstraints.tight(cardSize),
        devicePixelRatio: 1.0,
      ),
    );

    final pipelineOwner = PipelineOwner()..rootNode = renderView;
    final buildOwner = BuildOwner(focusManager: FocusManager());
    renderView.prepareInitialFrame();

    final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
      container: repaintBoundary,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: child,
        ),
      ),
    ).attachToRenderTree(buildOwner);

    buildOwner
      ..buildScope(rootElement)
      ..finalizeTree();
    pipelineOwner
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();

    final image = await repaintBoundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }
}

/// The card itself. Sized for [QuizShareCard.cardSize], so every dimension
/// here is in "card pixels", not screen pixels.
class _ShareCardView extends StatelessWidget {
  const _ShareCardView({required this.result, this.playerName});

  final QuizRoundResult result;
  final String? playerName;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: QuizShareCard.cardSize.width,
      height: QuizShareCard.cardSize.height,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: ArenaTheme.canvas),
        child: Stack(
          children: [
            // Soft brand glow behind the score.
            Positioned(
              left: -180,
              top: 120,
              child: _Glow(
                  color: const Color(0xFF2B7FE0), size: 760, alpha: 0.30),
            ),
            Positioned(
              right: -200,
              bottom: 80,
              child: _Glow(color: ArenaTheme.gold, size: 700, alpha: 0.16),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(80, 90, 80, 76),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BIBLE QUIZ',
                    style: AppTextStyles.headlineSmall.copyWith(
                      color: ArenaTheme.textOnNavy,
                      fontSize: 46,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 7,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'ADVENTIST SUPER APP',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: ArenaTheme.gold,
                      fontSize: 26,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: Icon(
                            i < result.stars
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 92,
                            color: i < result.stars
                                ? ArenaTheme.gold
                                : Colors.white.withValues(alpha: 0.20),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Text(
                    '${result.points}',
                    style: AppTextStyles.displayLarge.copyWith(
                      color: ArenaTheme.goldBright,
                      fontSize: 200,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'POINTS',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: ArenaTheme.textMutedOnNavy,
                      fontSize: 30,
                      letterSpacing: 6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 44),
                  Row(
                    children: [
                      _Stat(
                        value: '${result.correctCount}/${result.total}',
                        label: 'CORRECT',
                      ),
                      const SizedBox(width: 26),
                      _Stat(value: '${result.accuracyPct}%', label: 'ACCURACY'),
                      const SizedBox(width: 26),
                      _Stat(value: '${result.bestCombo}', label: 'BEST STREAK'),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 34, vertical: 22),
                    decoration: BoxDecoration(
                      color: ArenaTheme.glass,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                          color: ArenaTheme.glassBorder, width: 2),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.emoji_events_rounded,
                            color: ArenaTheme.gold, size: 40),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Text(
                            playerName == null || playerName!.trim().isEmpty
                                ? result.mode.label
                                : '${playerName!.trim()} · ${result.mode.label}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleLarge.copyWith(
                              color: ArenaTheme.textOnNavy,
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
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

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTextStyles.headlineMedium.copyWith(
              color: ArenaTheme.textOnNavy,
              fontSize: 54,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: ArenaTheme.textFaintOnNavy,
              fontSize: 22,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size, required this.alpha});

  final Color color;
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
