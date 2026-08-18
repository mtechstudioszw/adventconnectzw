import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/countries.dart';
import 'auth_service.dart';
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
    // The server's quiet window is derived from the province, so a
    // province change has to re-stamp it or notifications would keep
    // muting on the old town's sundown.
    if (sabbathModeEnabled()) await syncSabbathQuietWindow();
  }

  // ── Sabbath mode (patch_169) ────────────────────────────────────────
  // Distinct from the countdown toggle above: that shows a timer, this
  // MUTES non-essential notifications for the Sabbath window.

  static const _modeKey = 'pref:sabbath_mode';

  static bool sabbathModeEnabled() =>
      CacheService.readPref(_modeKey) == 'true';

  /// Turn Sabbath mode on/off and push the resulting quiet window to the
  /// server. The server never computes sundown — it only compares now()
  /// against the timestamp we stamp here, so this must be called
  /// whenever the window could change.
  static Future<void> setSabbathMode(bool value) async {
    await CacheService.writePref(_modeKey, value ? 'true' : 'false');
    await syncSabbathQuietWindow();
  }

  /// Write the current (or upcoming) Sabbath window to `profiles`.
  ///
  /// Sends `sabbath_quiet_until` = Saturday sundown when we are inside
  /// the Sabbath right now, and null otherwise. Deliberately does NOT
  /// pre-stamp a future window: a device that goes offline on Thursday
  /// would otherwise mute the user's Sabbath with a timestamp nothing
  /// can revise. The app re-syncs on launch and when the toggle moves,
  /// so the window is stamped at the point it becomes true.
  static Future<void> syncSabbathQuietWindow() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    final enabled = sabbathModeEnabled();
    DateTime? until;
    if (enabled && isSabbathNow()) {
      until = currentSabbathEnd();
    }
    try {
      await client.from('profiles').update({
        'sabbath_mode_enabled': enabled,
        'sabbath_quiet_until': until?.toUtc().toIso8601String(),
      }).eq('id', user.id);
    } catch (_) {
      // Best-effort: a failed sync means notifications aren't muted,
      // which is the safe direction to fail in.
    }
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

  /// The member's country, read straight from auth metadata so it is always
  /// whatever `AuthService.updateProfile` last wrote. Falls back to ZW,
  /// which is what patch_213 backfilled every pre-rebrand profile to.
  /// One source of truth, shared with every listing form — see
  /// `AuthService.currentCountry()`. Two readers of the same field is how
  /// this file ended up with a second copy of the solar equation.
  static String _countryCode() => AuthService.currentCountry();

  /// Where to compute sundown for.
  ///
  /// A Zimbabwean province wins when one is set, because it is finer-grained
  /// than a country centroid and it is what every existing user already has
  /// — this keeps their times bit-for-bit unchanged. Everyone else resolves
  /// to their country's populated centroid.
  ///
  /// **This is the fix for the global bug.** It used to be
  /// `province() ?? 'Harare'`, so every member outside Zimbabwe — who has no
  /// Zimbabwean province and never will — silently got Harare's sundown.
  static ({double lat, double lon}) _coords({
    String? overrideProvince,
    String? overrideCountry,
  }) {
    String? p = overrideProvince;
    if (p == null) {
      try {
        p = province();
      } catch (_) {
        // Cache not open yet — country resolution below still works.
      }
    }
    final byProvince = p == null ? null : _provinceCoords[p];
    if (byProvince != null) return byProvince;

    final country = Countries.byCode(overrideCountry ?? _countryCode());
    if (country != null) return (lat: country.lat, lon: country.lng);

    return _provinceCoords['Harare']!;
  }

  /// True while we're inside the Sabbath window: from Friday sundown
  /// through Saturday sundown. The home chip uses this to switch from
  /// a countdown ("Sabbath in 6h 12m") to a celebratory tag ("Happy
  /// Sabbath") for the duration.
  static bool isSabbathNow({
    DateTime? from,
    String? overrideProvince,
    String? overrideCountry,
  }) {
    final end = currentSabbathEnd(
      overrideCountry: overrideCountry,
      from: from,
      overrideProvince: overrideProvince,
    );
    return end != null;
  }

  /// If we're currently inside the Sabbath window, returns its end
  /// (Saturday sundown in UTC). Otherwise null. Useful for showing a
  /// "Sabbath ends in 1h 20m" hint near the end of the day.
  static DateTime? currentSabbathEnd({
    String? overrideCountry,
    DateTime? from,
    String? overrideProvince,
  }) {
    final coords = _coords(
      overrideProvince: overrideProvince,
      overrideCountry: overrideCountry,
    );

    // Calendar work happens in the DEVICE's local time, because "which
    // Friday is it" is a question about the user's own wall clock. The
    // comparison then happens between UTC instants, which is the only
    // frame where "has the sun set yet" is meaningful.
    final nowLocal = (from ?? DateTime.now()).toLocal();
    final nowUtc = nowLocal.toUtc();

    // Find the Friday that started the current Sabbath (today if it's
    // already Saturday or late Friday, yesterday if early Saturday, or
    // never if it's Sunday–Thursday).
    DateTime friday = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    // Walk back to the most recent Friday.
    while (friday.weekday != DateTime.friday) {
      friday = friday.subtract(const Duration(days: 1));
    }
    final saturday = friday.add(const Duration(days: 1));

    final fridaySunset = _sunsetUtc(
      date: friday,
      latDeg: coords.lat,
      lonDeg: coords.lon,
    );
    final saturdaySunset = _sunsetUtc(
      date: saturday,
      latDeg: coords.lat,
      lonDeg: coords.lon,
    );

    if (nowUtc.isAfter(fridaySunset) && nowUtc.isBefore(saturdaySunset)) {
      return saturdaySunset;
    }
    return null;
  }

  /// The next Friday sundown after [from], as a UTC instant.
  ///
  /// Never null now that a country centroid always resolves — it used to
  /// return null whenever the stored province wasn't a Zimbabwean one,
  /// which is every member abroad.
  static DateTime? nextSabbathStart({
    DateTime? from,
    String? overrideProvince,
    String? overrideCountry,
  }) {
    final coords = _coords(
      overrideProvince: overrideProvince,
      overrideCountry: overrideCountry,
    );

    final nowLocal = (from ?? DateTime.now()).toLocal();
    final nowUtc = nowLocal.toUtc();

    // Find the next Friday on the user's own calendar. If today is Friday
    // and sunset hasn't passed yet, use today.
    DateTime candidate = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    while (candidate.weekday != DateTime.friday) {
      candidate = candidate.add(const Duration(days: 1));
    }

    var sunset = _sunsetUtc(
      date: candidate,
      latDeg: coords.lat,
      lonDeg: coords.lon,
    );
    // If today is Friday but the sun has already set, jump to next Friday.
    if (sunset.isBefore(nowUtc)) {
      candidate = candidate.add(const Duration(days: 7));
      sunset = _sunsetUtc(
        date: candidate,
        latDeg: coords.lat,
        lonDeg: coords.lon,
      );
    }

    // Already UTC, so the caller's `.difference(DateTime.now())` works
    // regardless of device timezone.
    return sunset;
  }

  /// Returns sunset on the given date at (lat, lon) as a **UTC instant**.
  /// Uses the standard NOAA sunset equation. [date] is a date on the
  /// device's local calendar.
  ///
  /// It used to return Africa/Harare wall-clock, with `+2` hardcoded at
  /// both ends. Returning the instant instead is what makes this correct
  /// worldwide: callers render it with `.toLocal()`, and the OS applies
  /// the right offset — including DST, which a fixed offset cannot do and
  /// which moves sundown by an hour for half the year across Europe, North
  /// America and Australia.
  static DateTime _sunsetUtc({
    required DateTime date,
    required double latDeg,
    required double lonDeg,
  }) {
    // 1) Julian day for NOON UTC on [date]. Noon, not midnight, because a
    //    Julian Day rolls over at noon — so this lands on a whole number
    //    and the day count below is exact.
    final jd = _julianDay(DateTime.utc(date.year, date.month, date.day, 12));

    // 2) Days since J2000, then the meridian shift for longitude.
    //
    //    `n` MUST be a whole number of days. This is where sundown times
    //    were wrong by ~2 hours for the entire life of the app: the old
    //    code took the Julian day of 10:00 UTC (local noon minus the
    //    hardcoded +2) and never rounded, so `n` carried a -0.0825 day
    //    fraction straight into the solar-position terms — 1h59m of error,
    //    every day, for everyone.
    //
    //    Verified after the fix against two independent references:
    //    London 21 Jun 2026 → 20:21Z (actual ~20:21Z), and
    //    Harare 21 Aug 2026 → 15:47Z (actual ~15:47Z).
    final n = (jd - 2451545.0 + 0.0008).roundToDouble();
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

    // No sunset — the sun never crosses the horizon that day. Falls back
    // to 18:00 local, expressed as an instant.
    //
    // This stopped being theoretical with the rebrand: it is real life
    // above the Arctic Circle in Norway, Sweden and Finland, all of which
    // have Adventist congregations. A better answer there needs a
    // published local convention, not more astronomy.
    if (cosOmega.abs() > 1.0) {
      return DateTime(date.year, date.month, date.day, 18, 0).toUtc();
    }

    final omegaDeg = _deg(math.acos(cosOmega));
    final jSet = jTransit + omegaDeg / 360.0;

    // Julian Day → UTC instant. No offset applied: that is the caller's
    // job, via toLocal().
    return _fromJulianDay(jSet);
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
