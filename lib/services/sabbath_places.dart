import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// A state, province or region, represented by its largest city.
@immutable
class SabbathRegion {
  const SabbathRegion({
    required this.name,
    required this.city,
    required this.lat,
    required this.lon,
    required this.timeZone,
  });

  final String name;
  final String city;
  final double lat;
  final double lon;

  /// IANA zone, e.g. America/Los_Angeles. Sundown is shown in this zone,
  /// so a phone in New York set to California shows California time.
  final String timeZone;
}

@immutable
class SabbathCountry {
  const SabbathCountry({
    required this.code,
    required this.name,
    required this.regions,
  });

  /// ISO 3166-1 alpha-2, same codes as `Countries` and the profile.
  final String code;
  final String name;
  final List<SabbathRegion> regions;

  /// More than one zone — a state MUST be chosen for correct times.
  bool get spansTimeZones => regions.map((r) => r.timeZone).toSet().length > 1;
}

/// Every country and its states/provinces, for picking where sundown is
/// calculated (owner, 29 Oct 2026: "fix the Sabbath timer across the
/// entire world … states differ in terms of time").
///
/// Bundled from GeoNames (geonames.org, CC BY 4.0 — credited on the
/// Sabbath hours screen): each first-level region is represented by its
/// most populous city, with that city's time zone. Regenerate with
/// scratchpad make_places.py if it ever needs updating.
class SabbathPlaces {
  SabbathPlaces._();

  static const asset = 'assets/geo/sabbath_places.json';

  static List<SabbathCountry>? _cache;

  static Future<List<SabbathCountry>> all() async {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(asset);
    return _cache = parse(raw);
  }

  /// Public for the tests.
  static List<SabbathCountry> parse(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return [
      for (final c in json['countries'] as List)
        SabbathCountry(
          code: c['c'] as String,
          name: c['n'] as String,
          regions: [
            for (final r in c['r'] as List)
              SabbathRegion(
                name: r[0] as String,
                city: r[1] as String,
                lat: (r[2] as num).toDouble(),
                lon: (r[3] as num).toDouble(),
                timeZone: r[4] as String,
              ),
          ],
        ),
    ];
  }

  static Future<SabbathCountry?> byCode(String code) async {
    for (final c in await all()) {
      if (c.code == code.toUpperCase()) return c;
    }
    return null;
  }
}
