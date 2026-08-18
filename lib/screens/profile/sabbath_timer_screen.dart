import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/countries.dart';
import '../../models/seller_model.dart';
import '../../services/sabbath_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/motion/pressable.dart';

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

  String get _countryCode =>
      (AuthService.currentUser?.userMetadata?['country'] as String?) ??
      Countries.defaultCode;

  /// True when the member is in Zimbabwe, which is the only country whose
  /// provinces this screen can offer. Everyone else gets country-level
  /// sundown and no province chips — offering a Zimbabwean province to a
  /// member in Kenya is worse than offering nothing.
  bool get _isZw => _countryCode == 'ZW';

  @override
  Widget build(BuildContext context) {
    // Delegates to SabbathService rather than computing sundown here.
    //
    // This screen used to carry its OWN copy of the solar equation, its own
    // province table and its own hardcoded `+120` minutes for UTC+2 — so a
    // member abroad saw Harare's sundown on the one screen dedicated to
    // getting it right. Two implementations of the same physics is one
    // too many; the service is now the only one.
    final start =
        SabbathService.nextSabbathStart(
          from: _now,
          overrideProvince: _isZw ? _province : null,
        )!.toLocal();
    final end =
        (SabbathService.currentSabbathEnd(
              from: _now,
              overrideProvince: _isZw ? _province : null,
            ) ??
            start.add(const Duration(hours: 24)).toUtc())
            .toLocal();
    final inSabbath = _now.isAfter(start) && _now.isBefore(end);
    final target = inSabbath ? end : start;
    final remaining = target.difference(_now);
    // Ring sweep: how far along we are — through the week toward Friday
    // sundown, or through the Sabbath hours themselves.
    final horizon = inSabbath
        ? end.difference(start).inSeconds
        : const Duration(days: 7).inSeconds;
    final ringProgress = (1 - remaining.inSeconds / horizon)
        .clamp(0.0, 1.0)
        .toDouble();

    return Scaffold(
      backgroundColor: Colors.transparent,
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
                  StaggeredReveal(
                    index: 0,
                    child: _CountdownCard(
                      remaining: remaining,
                      inSabbath: inSabbath,
                      progress: ringProgress,
                    ),
                  ),
                  const SizedBox(height: 16),
                  StaggeredReveal(
                    index: 1,
                    child: _SundownTimes(
                      start: start,
                      end: end,
                      province: _province,
                    ),
                  ),
                  const SizedBox(height: 16),
                  StaggeredReveal(
                    index: 2,
                    child: ScreenCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isZw ? 'PROVINCE' : 'LOCATION',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: context.palette.textMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Province chips are Zimbabwe-only. For everyone
                          // else the location is their profile country, set
                          // in Edit profile — so this reads it out rather
                          // than offering a picker that belongs elsewhere.
                          if (_isZw)
                            SizedBox(
                              height: 38,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  for (final p in sellerProvinces) ...[
                                    _Chip(
                                      label: p,
                                      active: _province == p,
                                      onTap: () =>
                                          setState(() => _province = p),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                ],
                              ),
                            )
                          else
                            Text(
                              Countries.byCode(_countryCode)?.labelWithFlag ??
                                  'Not set',
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: context.palette.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          const SizedBox(height: 10),
                          Text(
                            _isZw
                                ? 'Times are an approximation based on average sundown for the province. For exact local times consult a sundown calendar.'
                                : 'Times are an approximation based on average sundown for your country, shown in your device\'s time zone. Change your country in Edit profile. For exact local times consult a sundown calendar.',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: context.palette.textMuted,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  StaggeredReveal(
                    index: 3,
                    child: InfoBanner(
                      icon: Icons.brightness_3,
                      message:
                          'Enable the Sabbath countdown in Settings → Preferences to show this on the home screen.',
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

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({
    required this.remaining,
    required this.inSabbath,
    required this.progress,
  });
  final Duration remaining;
  final bool inSabbath;

  /// 0→1 sweep of the gold ring — the week running toward Friday
  /// sundown (or the Sabbath hours themselves once it has begun).
  final double progress;

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
          // The Sabbath ring — same gold-ring motif as the intro film
          // and the unlock screen, sweeping as sundown approaches.
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(92, 92),
                  painter: _SabbathRingPainter(progress: progress),
                ),
                Icon(
                  inSabbath ? Icons.nights_stay : Icons.brightness_3,
                  color: accent,
                  size: 34,
                ),
              ],
            ),
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
          // Digits roll upward when they change instead of snapping.
          AnimatedSwitcher(
            duration: AppMotion.maybe(context, AppMotion.quick),
            switchInCurve: AppMotion.easeOut,
            switchOutCurve: AppMotion.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.35),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              value,
              key: ValueKey(value),
              style: AppTextStyles.displayMedium.copyWith(
                color: AppColors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
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
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
  const _Chip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressEffect(
      child: Material(
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
                color: active ? AppColors.primaryBlue : context.palette.divider,
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
      ),
    );
  }
}

/// Gold progress ring around the countdown moon: a faint white track
/// with the gold sweep drawing clockwise from the top as sundown nears.
class _SabbathRingPainter extends CustomPainter {
  _SabbathRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 3;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = AppColors.white.withValues(alpha: 0.14),
    );
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      progress * 2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = AppColors.goldAccent,
    );
    // The comet head marking "now" on the ring.
    final angle = -math.pi / 2 + progress * 2 * math.pi;
    canvas.drawCircle(
      Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      ),
      4,
      Paint()..color = AppColors.goldAccent,
    );
  }

  @override
  bool shouldRepaint(_SabbathRingPainter old) => old.progress != progress;
}
