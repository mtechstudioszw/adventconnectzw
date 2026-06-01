import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/seller_model.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';

/// Friday-sundown to Saturday-sundown countdown with a province
/// picker. Times are an astronomical approximation good enough for a
/// community app (within a few minutes of the real solar sundown for
/// Zimbabwean latitudes year-round).
class SabbathTimerScreen extends StatefulWidget {
  const SabbathTimerScreen({super.key});

  @override
  State<SabbathTimerScreen> createState() => _SabbathTimerScreenState();
}

class _SabbathTimerScreenState extends State<SabbathTimerScreen> {
  Timer? _ticker;
  DateTime _now = DateTime.now();
  String _province = 'Harare';

  @override
  void initState() {
    super.initState();
    final stored =
        AuthService.currentUser?.userMetadata?['province'] as String?;
    if (stored != null && sellerProvinces.contains(stored)) {
      _province = stored;
    }
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = _sabbathStart(_now, _province);
    final end = _sabbathEnd(_now, _province);
    final inSabbath = _now.isAfter(start) && _now.isBefore(end);
    final target = inSabbath ? end : start;
    final remaining = target.difference(_now);

    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            ScreenHero(
              title: 'Sabbath timer',
              tagline: inSabbath ? 'Sabbath is in progress' : 'Counting down',
              subtitle: inSabbath
                  ? 'Time until Sabbath ends — Saturday sundown.'
                  : 'Time until Sabbath begins — Friday sundown.',
              fallbackRoute: 'profile',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CountdownCard(
                    remaining: remaining,
                    inSabbath: inSabbath,
                  ),
                  const SizedBox(height: 16),
                  _SundownTimes(start: start, end: end, province: _province),
                  const SizedBox(height: 16),
                  ScreenCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PROVINCE',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: context.palette.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 38,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final p in sellerProvinces) ...[
                                _Chip(
                                  label: p,
                                  active: _province == p,
                                  onTap: () => setState(() => _province = p),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Times are an approximation based on average sundown for the province. For exact local times consult a sundown calendar.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: context.palette.textMuted,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  InfoBanner(
                    icon: Icons.brightness_3,
                    message:
                        'Enable the Sabbath countdown in Settings → Preferences to show this on the home screen.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Astronomical helpers -------------------------------------------------

  static const _provinceCoords = <String, ({double lat, double lon})>{
    'Harare': (lat: -17.83, lon: 31.05),
    'Bulawayo': (lat: -20.15, lon: 28.58),
    'Manicaland': (lat: -18.97, lon: 32.67),
    'Mashonaland Central': (lat: -17.36, lon: 30.95),
    'Mashonaland East': (lat: -18.20, lon: 31.55),
    'Mashonaland West': (lat: -17.65, lon: 30.20),
    'Masvingo': (lat: -20.07, lon: 30.83),
    'Matabeleland North': (lat: -19.55, lon: 27.50),
    'Matabeleland South': (lat: -20.85, lon: 28.65),
    'Midlands': (lat: -19.45, lon: 29.82),
  };

  /// Returns the next (or current) Friday-sundown for the given province.
  DateTime _sabbathStart(DateTime ref, String province) {
    // Walk forward day by day until we land on a Friday whose sundown
    // is still in the future. Cheap because we only iterate up to 7 times.
    var d = DateTime(ref.year, ref.month, ref.day);
    for (var i = 0; i < 8; i++) {
      final candidate = d.add(Duration(days: i));
      if (candidate.weekday != DateTime.friday) continue;
      final sundown = _sundown(candidate, province);
      if (sundown.isAfter(ref) || _isSameDay(candidate, ref)) {
        // If today is Friday and sundown already passed, fall through to
        // next Friday on the following iteration.
        if (sundown.isAfter(ref)) return sundown;
      }
    }
    return _sundown(d.add(const Duration(days: 7)), province);
  }

  DateTime _sabbathEnd(DateTime ref, String province) {
    final start = _sabbathStart(ref, province);
    // If we're currently inside the Sabbath (after Friday sundown but
    // before Saturday sundown), `start` is in the future — back up.
    final candidate = start.subtract(const Duration(days: 1));
    final inSabbath = ref.isAfter(_sundown(candidate, province));
    final saturday =
        inSabbath ? candidate.add(const Duration(days: 1)) : start.add(const Duration(days: 1));
    return _sundown(saturday, province);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Approximate sundown for the given date and Zimbabwean province.
  ///
  /// Uses the standard solar-noon + hour-angle formula simplified for
  /// civil sunset (zenith ≈ 90.83°). Accurate to within a few minutes
  /// for latitudes in Zimbabwe (-15° to -22°), which is plenty for a
  /// Sabbath countdown UI.
  DateTime _sundown(DateTime date, String province) {
    final coord = _provinceCoords[province] ?? _provinceCoords['Harare']!;
    final dayOfYear =
        date.difference(DateTime(date.year, 1, 1)).inDays + 1;

    final lat = coord.lat * math.pi / 180;
    final lon = coord.lon;

    // Equation of time + solar declination (NOAA simplified).
    final gamma = 2 * math.pi / 365 * (dayOfYear - 1 + 0.5);
    final eqTime = 229.18 *
        (0.000075 +
            0.001868 * math.cos(gamma) -
            0.032077 * math.sin(gamma) -
            0.014615 * math.cos(2 * gamma) -
            0.040849 * math.sin(2 * gamma));
    final declination = 0.006918 -
        0.399912 * math.cos(gamma) +
        0.070257 * math.sin(gamma) -
        0.006758 * math.cos(2 * gamma) +
        0.000907 * math.sin(2 * gamma) -
        0.002697 * math.cos(3 * gamma) +
        0.00148 * math.sin(3 * gamma);

    final zenith = 90.833 * math.pi / 180;
    final cosH = (math.cos(zenith) - math.sin(lat) * math.sin(declination)) /
        (math.cos(lat) * math.cos(declination));
    // Hour angle clamps for latitudes that never see sunset/sunrise —
    // doesn't happen in Zimbabwe but defend against floating-point
    // overshoot anyway.
    final clamped = cosH.clamp(-1.0, 1.0);
    final hourAngle = math.acos(clamped) * 180 / math.pi;

    // Minutes from UTC midnight to sunset.
    final sunsetMinutes = 720 - 4 * (lon - hourAngle) - eqTime;
    // Zimbabwe is UTC+2 year-round (CAT, no DST).
    final localMinutes = sunsetMinutes + 120;
    final hours = (localMinutes / 60).floor();
    final minutes = localMinutes.round() % 60;
    return DateTime(date.year, date.month, date.day, hours, minutes);
  }
}

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({required this.remaining, required this.inSabbath});
  final Duration remaining;
  final bool inSabbath;

  @override
  Widget build(BuildContext context) {
    final accent = inSabbath ? AppColors.goldAccent : AppColors.primaryBlue;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        gradient: AppColors.appBarGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            inSabbath ? Icons.nights_stay : Icons.brightness_3,
            color: accent,
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            inSabbath ? 'SABBATH ENDS IN' : 'SABBATH BEGINS IN',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.white.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Unit(value: _days(remaining), label: 'DAYS'),
              const SizedBox(width: 8),
              _Unit(value: _hours(remaining), label: 'HRS'),
              const SizedBox(width: 8),
              _Unit(value: _minutes(remaining), label: 'MIN'),
              const SizedBox(width: 8),
              _Unit(value: _seconds(remaining), label: 'SEC'),
            ],
          ),
        ],
      ),
    );
  }

  String _two(int n) => n.toString().padLeft(2, '0');
  String _days(Duration d) => '${d.inDays}';
  String _hours(Duration d) => _two(d.inHours.remainder(24));
  String _minutes(Duration d) => _two(d.inMinutes.remainder(60));
  String _seconds(Duration d) => _two(d.inSeconds.remainder(60));
}

class _Unit extends StatelessWidget {
  const _Unit({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: AppTextStyles.displayMedium.copyWith(
              color: AppColors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.white.withValues(alpha: 0.65),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SundownTimes extends StatelessWidget {
  const _SundownTimes({
    required this.start,
    required this.end,
    required this.province,
  });

  final DateTime start;
  final DateTime end;
  final String province;

  String _fmt(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _date(DateTime d) {
    const days = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NEXT SABBATH · ${province.toUpperCase()}',
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          _TimeRow(
            icon: Icons.brightness_3,
            label: 'Begins · Friday sundown',
            value: '${_fmt(start)}  ·  ${_date(start)}',
          ),
          const SizedBox(height: 12),
          _TimeRow(
            icon: Icons.wb_twilight,
            label: 'Ends · Saturday sundown',
            value: '${_fmt(end)}  ·  ${_date(end)}',
          ),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.primaryBlue, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.labelSmall.copyWith(
                  color: context.palette.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppTextStyles.titleSmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: active ? AppColors.primaryGradient : null,
            color: active ? null : context.palette.chipBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active
                  ? AppColors.primaryBlue
                  : context.palette.divider,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color: active ? AppColors.white : context.palette.text,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}
