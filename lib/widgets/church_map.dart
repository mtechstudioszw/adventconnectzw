import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/church_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Tappable preview card that hints at the church's location. We don't
/// embed an in-app map (the flutter_map dependency tree is currently
/// broken on Dart 3 via proj4dart → wkt_parser). Tapping the card opens
/// the device's full Maps app at the church location.
class ChurchMapPreview extends StatelessWidget {
  const ChurchMapPreview({
    super.key,
    required this.church,
    this.height = 160,
  });

  final Church church;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => MapsLauncher.openLocation(church: church),
          child: Container(
            height: height,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: AppColors.appBarGradient,
            ),
            child: Stack(
              children: [
                // Subtle radial highlight
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-0.4, -0.6),
                          radius: 1.2,
                          colors: [
                            AppColors.white.withValues(alpha: 0.10),
                            AppColors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Decorative concentric pin "rings" hinting at a map
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _RingPainter()),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.goldAccent, Color(0xFFE0C780)],
                          ),
                          border: Border.all(
                            color: AppColors.white,
                            width: 2.5,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color.fromRGBO(13, 27, 62, 0.45),
                              blurRadius: 14,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: AppColors.darkNavy,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tap to open in Maps',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        church.hasLocation
                            ? 'View this church on the map'
                            : 'Search this address on the map',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.70),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.white.withValues(alpha: 0.10);
    for (var r = 28.0; r < size.width; r += 28) {
      canvas.drawCircle(centre, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ────────────────────────────────────────────────────────────────────
//  Launcher helpers — open external Maps app for view / directions.
// ────────────────────────────────────────────────────────────────────

class MapsLauncher {
  MapsLauncher._();

  /// Opens the church location in the device's default Maps app.
  /// Uses Google Maps universal URLs which fall back to the web on
  /// devices without a Maps app installed.
  static Future<bool> openLocation({required Church church}) async {
    final url = _viewUrl(church);
    if (url == null) return false;
    return _launch(url);
  }

  /// Opens turn-by-turn directions to the church.
  static Future<bool> openDirections({required Church church}) async {
    final url = _directionsUrl(church);
    if (url == null) return false;
    return _launch(url);
  }

  static Uri? _viewUrl(Church church) {
    if (church.hasLocation) {
      return Uri.parse(
        'https://www.google.com/maps/search/?api=1'
        '&query=${church.latitude},${church.longitude}',
      );
    }
    final query = _fallbackQuery(church);
    if (query == null) return null;
    return Uri.parse(
      'https://www.google.com/maps/search/?api=1'
      '&query=${Uri.encodeQueryComponent(query)}',
    );
  }

  static Uri? _directionsUrl(Church church) {
    if (church.hasLocation) {
      return Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=${church.latitude},${church.longitude}',
      );
    }
    final query = _fallbackQuery(church);
    if (query == null) return null;
    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${Uri.encodeQueryComponent(query)}',
    );
  }

  static String? _fallbackQuery(Church church) {
    final parts = <String>[
      church.name,
      if ((church.address ?? '').trim().isNotEmpty) church.address!.trim(),
      if (church.city.trim().isNotEmpty) church.city.trim(),
      'Zimbabwe',
    ];
    final joined = parts.where((p) => p.isNotEmpty).join(', ');
    return joined.isEmpty ? null : joined;
  }

  static Future<bool> _launch(Uri url) async {
    if (!await canLaunchUrl(url)) return false;
    return launchUrl(url, mode: LaunchMode.externalApplication);
  }
}
