import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Why a location lookup failed — surfaced so the UI can offer the
/// right action button (Open Settings vs Turn On Location vs Retry).
enum LocationFailure {
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  timeout,
  unknown,
}

class LocationResult {
  const LocationResult._(this.position, this.failure);

  factory LocationResult.success(Position p) => LocationResult._(p, null);
  factory LocationResult.failed(LocationFailure f) =>
      LocationResult._(null, f);

  final Position? position;
  final LocationFailure? failure;

  bool get isSuccess => position != null;
}

/// Geolocation for the Churches tab — request permission, fetch the
/// current position, compute distance to a church row. Soft-fails to
/// null on permission denial so the list falls back to alphabetical
/// order (per Part 15 of the master reference).
class LocationService {
  LocationService._();

  /// Returns the device's current position, or null if location is
  /// unavailable / denied. Never throws.
  ///
  /// For callers that need to know *why* it failed (e.g. to surface a
  /// targeted error UI with the right action button), use
  /// [getCurrentPositionDetailed] instead.
  static Future<Position?> getCurrentPosition() async {
    final result = await getCurrentPositionDetailed();
    return result.position;
  }

  /// Same as [getCurrentPosition] but returns the failure reason when
  /// it can't get a fix — so the UI can offer "Open Settings",
  /// "Enable location", or "Try again" depending on what actually
  /// went wrong.
  static Future<LocationResult> getCurrentPositionDetailed() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationResult.failed(LocationFailure.servicesDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return LocationResult.failed(
          LocationFailure.permissionDeniedForever,
        );
      }
      if (permission == LocationPermission.denied) {
        return LocationResult.failed(LocationFailure.permissionDenied);
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          // Bound the wait — without this the call sits forever when
          // the user is indoors with no GPS lock, leaving the FAB
          // spinning and the user thinking the button is broken.
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LocationResult.success(pos);
    } catch (e, st) {
      debugPrint('LocationService: getCurrentPosition failed: $e\n$st');
      final message = e.toString().toLowerCase();
      if (message.contains('timeout')) {
        return LocationResult.failed(LocationFailure.timeout);
      }
      return LocationResult.failed(LocationFailure.unknown);
    }
  }

  /// Open the OS-level app settings so the user can grant location
  /// permission after denying it earlier. Returns true if the system
  /// reports the settings page was opened.
  static Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Open the OS-level location services toggle so the user can flip
  /// it on. Use this when [LocationFailure.servicesDisabled] is hit.
  static Future<bool> openLocationSettings() =>
      Geolocator.openLocationSettings();

  /// Forward-geocode a free-text address into coordinates using OpenStreetMap's
  /// free Nominatim service (no API key). Used so a church admin only has to
  /// type the church's address and "Near me" can then rank it by real distance.
  ///
  /// Biased to Zimbabwe. Returns null when the address can't be resolved or the
  /// request fails — callers fall back to saving without coordinates.
  static Future<({double lat, double lng})?> geocodeAddress(
    String address,
  ) async {
    final q = address.trim();
    if (q.length < 3) return null;
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=${Uri.encodeQueryComponent(q)}'
      '&format=json&limit=1&countrycodes=zw',
    );
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
      final req = await client.getUrl(uri);
      // Nominatim's usage policy requires a descriptive User-Agent.
      req.headers.set(HttpHeaders.userAgentHeader,
          'AdventConnectZW/1.0 (church-locator)');
      final resp = await req.close().timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data is! List || data.isEmpty) return null;
      final first = data.first as Map<String, dynamic>;
      final lat = double.tryParse('${first['lat']}');
      final lng = double.tryParse('${first['lon']}');
      if (lat == null || lng == null) return null;
      return (lat: lat, lng: lng);
    } catch (e) {
      debugPrint('LocationService.geocodeAddress failed: $e');
      return null;
    } finally {
      client?.close(force: true);
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
