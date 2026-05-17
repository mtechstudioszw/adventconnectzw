import 'dart:math' as math;

import 'cache_service.dart';

/// Sabbath sundown helper. Mirrors Part 16 of the master reference:
/// off by default, opt-in via Settings, auto-computes Friday sundown
/// based on the user's province.
///
/// The sunset algorithm is the standard NOAA equation; accurate to
/// ~1 minute for Zimbabwe latitudes, which is plenty for Sabbath
/// observance. No external API calls — runs entirely on-device.
class SabbathService {
  SabbathService._();

  static const _enabledKey = 'pref:sabbath_enabled';
  static const _provinceKey = 'pref:sabbath_province';

  /// Whether the user has opted in. Default: false (off).
  static bool isEnabled() => CacheService.readPref(_enabledKey) == 'true';

  static Future<void> setEnabled(bool value) async {
    await CacheService.writePref(_enabledKey, value ? 'true' : 'false');
  }

  /// User-selected province (used to pick lat/lon). Returns null if
  /// they haven't picked one; the home widget then defaults to Harare.
  static String? province() => CacheService.readPref(_provinceKey);

  static Future<void> setProvince(String name) async {
    await CacheService.writePref(_provinceKey, name);
  }

  // -- Province coordinates ----------------------------------------------
  // Approximate centroids; ±1 minute of sunset accuracy is well within
  // anything a Sabbath observer cares about.
  static const Map<String, ({double lat, double lon})> _provinceCoords = {
    'Harare':                ( lat: -17.83, lon: 31.05 ),
    'Bulawayo':              ( lat: -20.15, lon: 28.58 ),
    'Manicaland':            ( lat: -18.97, lon: 32.66 ),
    'Mashonaland Central':   ( lat: -17.00, lon: 31.00 ),
    'Mashonaland East':      ( lat: -17.83, lon: 31.50 ),
    'Mashonaland West':      ( lat: -17.65, lon: 30.20 ),
    'Masvingo':              ( lat: -20.07, lon: 30.83 ),
    'Matabeleland North':    ( lat: -19.15, lon: 28.50 ),
    'Matabeleland South':    ( lat: -21.00, lon: 29.00 ),
    'Midlands':              ( lat: -19.45, lon: 29.82 ),
  };

  static List<String> get provinces => _provinceCoords.keys.toList();

  /// The next Friday sundown after [from] in Africa/Harare local time.
  /// Returns null if the province isn't recognised.
  static DateTime? nextSabbathStart({DateTime? from, String? overrideProvince}) {
    final coordKey = overrideProvince ?? province() ?? 'Harare';
    final coords = _provinceCoords[coordKey];
    if (coords == null) return null;

    final now = (from ?? DateTime.now()).toUtc();
    // Africa/Harare is fixed UTC+2 — no DST. Cheap to do math in.
    final hararet = now.add(const Duration(hours: 2));

    // Find the next Friday's date (CAT calendar). If today is Friday
    // and sunset hasn't passed yet, use today.
    DateTime candidate = DateTime(hararet.year, hararet.month, hararet.day);
    while (candidate.weekday != DateTime.friday) {
      candidate = candidate.add(const Duration(days: 1));
    }

    var sunsetCat = _sunsetLocal(
      date: candidate,
      latDeg: coords.lat,
      lonDeg: coords.lon,
    );
    // If today is Friday but the sun has already set, jump to next Friday.
    if (sunsetCat.isBefore(hararet)) {
      candidate = candidate.add(const Duration(days: 7));
      sunsetCat = _sunsetLocal(
        date: candidate,
        latDeg: coords.lat,
        lonDeg: coords.lon,
      );
    }

    // Convert back to UTC so the caller's `.difference(DateTime.now())`
    // works regardless of device timezone.
    return sunsetCat.subtract(const Duration(hours: 2)).toUtc();
  }

  /// Returns sunset on the given date at (lat, lon), expressed in
  /// Africa/Harare wall-clock time (UTC+2). Uses the standard NOAA
  /// sunset equation. [date] should be at midnight local.
  static DateTime _sunsetLocal({
    required DateTime date,
    required double latDeg,
    required double lonDeg,
  }) {
    // 1) Julian day for the given UTC date at noon.
    //    Convert the local-noon date to UTC first by subtracting +2.
    final dateUtcMidday = DateTime.utc(date.year, date.month, date.day, 12);
    // Subtract 2h to get equivalent CAT-local-noon-in-UTC.
    final adjUtc = dateUtcMidday.subtract(const Duration(hours: 2));
    final jd = _julianDay(adjUtc);

    // 2) Days since J2000 + meridian shift for longitude.
    final n = jd - 2451545.0 + 0.0008;
    final jStar = n - lonDeg / 360.0;

    // 3) Solar mean anomaly.
    final m = _wrap360(357.5291 + 0.98560028 * jStar);
    final mRad = _rad(m);

    // 4) Equation of the center.
    final c = 1.9148 * math.sin(mRad) +
              0.0200 * math.sin(2 * mRad) +
              0.0003 * math.sin(3 * mRad);

    // 5) Ecliptic longitude.
    final lambda = _wrap360(m + c + 180 + 102.9372);
    final lambdaRad = _rad(lambda);

    // 6) Solar transit (true noon).
    final jTransit = 2451545.0 + jStar +
        0.0053 * math.sin(mRad) -
        0.0069 * math.sin(2 * lambdaRad);

    // 7) Declination.
    final sinDelta = math.sin(lambdaRad) * math.sin(_rad(23.4397));
    final delta = math.asin(sinDelta);

    // 8) Hour angle for sunset (sun center -0.83° below horizon).
    final phi = _rad(latDeg);
    final cosOmega =
        (math.sin(_rad(-0.83)) - math.sin(phi) * math.sin(delta)) /
            (math.cos(phi) * math.cos(delta));

    // No sunset (polar) — fall back to a safe 18:00 local. Doesn't
    // happen at Zimbabwe latitudes, but guard anyway.
    if (cosOmega.abs() > 1.0) {
      return DateTime(date.year, date.month, date.day, 18, 0);
    }

    final omegaDeg = _deg(math.acos(cosOmega));
    final jSet = jTransit + omegaDeg / 360.0;

    // Convert Julian Day → UTC DateTime → Africa/Harare wall-clock.
    final sunsetUtc = _fromJulianDay(jSet);
    return sunsetUtc.add(const Duration(hours: 2));
  }

  static double _julianDay(DateTime utc) {
    // Astronomical Julian Day from a UTC instant (fractional).
    final y = utc.year;
    final m = utc.month;
    final d = utc.day +
        (utc.hour + utc.minute / 60.0 + utc.second / 3600.0) / 24.0;
    int yy = y;
    int mm = m;
    if (mm <= 2) {
      yy -= 1;
      mm += 12;
    }
    final a = (yy / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (yy + 4716)).floor() +
        (30.6001 * (mm + 1)).floor() +
        d + b - 1524.5;
  }

  static DateTime _fromJulianDay(double jd) {
    final j = jd + 0.5;
    final z = j.floor();
    final f = j - z;
    int a = z;
    if (z >= 2299161) {
      final alpha = ((z - 1867216.25) / 36524.25).floor();
      a = z + 1 + alpha - (alpha / 4).floor();
    }
    final b = a + 1524;
    final c = ((b - 122.1) / 365.25).floor();
    final d = (365.25 * c).floor();
    final e = ((b - d) / 30.6001).floor();
    final dayFrac = b - d - (30.6001 * e).floor() + f;
    final day = dayFrac.floor();
    final hoursFrac = (dayFrac - day) * 24;
    final hour = hoursFrac.floor();
    final minutesFrac = (hoursFrac - hour) * 60;
    final minute = minutesFrac.floor();
    final second = ((minutesFrac - minute) * 60).round();
    final month = e < 14 ? e - 1 : e - 13;
    final year = month > 2 ? c - 4716 : c - 4715;
    return DateTime.utc(year, month, day, hour, minute, second.clamp(0, 59));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
  static double _deg(double rad) => rad * 180.0 / math.pi;
  static double _wrap360(double v) {
    final r = v % 360.0;
    return r < 0 ? r + 360.0 : r;
  }
}
