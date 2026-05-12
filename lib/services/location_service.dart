import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Geolocation for the Churches tab — request permission, fetch the
/// current position, compute distance to a church row. Soft-fails to
/// null on permission denial so the list falls back to alphabetical
/// order (per Part 15 of the master reference).
class LocationService {
  LocationService._();

  /// Returns the device's current position, or null if location is
  /// unavailable / denied. Never throws.
  static Future<Position?> getCurrentPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
    } catch (e, st) {
      debugPrint('LocationService: getCurrentPosition failed: $e\n$st');
      return null;
    }
  }

  /// Great-circle distance in metres between two points.
  static double distanceMeters({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    return Geolocator.distanceBetween(fromLat, fromLng, toLat, toLng);
  }

  /// Human-friendly distance label. < 1 km shows metres, >= 1 km shows
  /// one decimal of km. Returns null for invalid inputs so the UI can
  /// hide the chip cleanly.
  static String? formatDistance(double meters) {
    if (meters.isNaN || meters.isInfinite || meters < 0) return null;
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}
