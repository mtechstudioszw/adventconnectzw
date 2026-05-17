import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/church_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Small non-interactive map preview centred on a single church. Tapping
/// the map opens the device's default Maps app at the same location.
///
/// Renders OpenStreetMap tiles — free, no API key. Per the OSM tile
/// usage policy we include attribution and identify the app via the
/// User-Agent header.
class ChurchMapPreview extends StatelessWidget {
  const ChurchMapPreview({
    super.key,
    required this.church,
    this.height = 180,
    this.zoom = 15,
  });

  final Church church;
  final double height;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(church.latitude!, church.longitude!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          SizedBox(
            height: height,
            width: double.infinity,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: zoom,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
                onTap: (_, _) =>
                    MapsLauncher.openLocation(church: church),
              ),
              children: [
                TileLayer(
                  urlTemplate: _osmTileUrl,
                  userAgentPackageName: _userAgent,
                  maxZoom: 19,
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 44,
                      height: 52,
                      alignment: Alignment.topCenter,
                      child: const _PinMarker(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // OSM attribution overlay — required by the tile usage policy.
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '© OpenStreetMap',
                style: AppTextStyles.labelSmall.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.7),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          // Tap layer — flutter_map's onTap requires the map to be
          // interactive, so we add a transparent InkWell over the top.
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => MapsLauncher.openLocation(church: church),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen interactive map showing a list of churches as pins.
/// Tapping a pin invokes [onTapChurch] (typically opens a bottom sheet).
class ChurchesMapView extends StatelessWidget {
  const ChurchesMapView({
    super.key,
    required this.churches,
    required this.onTapChurch,
    this.userLatitude,
    this.userLongitude,
  });

  final List<Church> churches;
  final ValueChanged<Church> onTapChurch;
  final double? userLatitude;
  final double? userLongitude;

  @override
  Widget build(BuildContext context) {
    final located =
        churches.where((c) => c.hasLocation).toList(growable: false);
    final LatLng center;
    if (userLatitude != null && userLongitude != null) {
      center = LatLng(userLatitude!, userLongitude!);
    } else if (located.isNotEmpty) {
      center = LatLng(located.first.latitude!, located.first.longitude!);
    } else {
      // Default to Zimbabwe centre when nothing else is known.
      center = const LatLng(-19.0, 29.85);
    }

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: located.isEmpty ? 6 : 11,
        minZoom: 4,
        maxZoom: 18,
      ),
      children: [
        TileLayer(
          urlTemplate: _osmTileUrl,
          userAgentPackageName: _userAgent,
          maxZoom: 19,
        ),
        if (userLatitude != null && userLongitude != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(userLatitude!, userLongitude!),
                width: 22,
                height: 22,
                child: const _UserDot(),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (final c in located)
              Marker(
                point: LatLng(c.latitude!, c.longitude!),
                width: 44,
                height: 52,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  onTap: () => onTapChurch(c),
                  child: _PinMarker(verified: c.isVerified),
                ),
              ),
          ],
        ),
        const _AttributionBadge(),
      ],
    );
  }
}

class _PinMarker extends StatelessWidget {
  const _PinMarker({this.verified = false});
  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: verified
                  ? const [AppColors.goldAccent, Color(0xFFE0C780)]
                  : const [AppColors.primaryBlue, Color(0xFF1976D2)],
            ),
            border: Border.all(color: AppColors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(13, 27, 62, 0.35),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.church_rounded,
            color: AppColors.white,
            size: 20,
          ),
        ),
        Container(
          width: 3,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(2),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(13, 27, 62, 0.30),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryBlue,
        border: Border.all(color: AppColors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.35),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}

class _AttributionBadge extends StatelessWidget {
  const _AttributionBadge();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 8,
      bottom: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '© OpenStreetMap contributors',
          style: AppTextStyles.labelSmall.copyWith(
            color: const Color.fromRGBO(26, 26, 46, 0.75),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
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

const String _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String _userAgent = 'com.adventconnect.zw';
