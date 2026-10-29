import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/library_reminders.dart';
import '../../services/sabbath_places.dart';
import '../../services/sabbath_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/screen_shell.dart';
import 'sabbath_place_picker.dart';

/// The Sabbath window this week, as two UTC instants.
typedef SabbathWindow = ({DateTime start, DateTime end});

/// Sundown to sundown: when this Sabbath starts and ends, the next few
/// Fridays, a Friday reminder and the existing Sabbath mode.
///
/// Times are calculated on the phone (SabbathService's NOAA sunset) for
/// the member's province, country or — if they choose — their location.
/// Nothing is fetched.
class SabbathHoursScreen extends StatefulWidget {
  const SabbathHoursScreen({super.key, this.now});

  /// Fixed clock for tests and screenshots.
  final DateTime? now;

  /// The Sabbath in progress, or else the next one, for [now].
  /// [sunsetOn] is injectable for tests.
  static SabbathWindow window(
    DateTime now, {
    DateTime Function(DateTime localDate)? sunsetOn,
  }) {
    final sunset = sunsetOn ?? SabbathService.sunsetOn;
    final local = now.toLocal();
    final utc = now.toUtc();
    // The Friday of this Sabbath: back to Friday if it's Saturday (or
    // Friday), otherwise forward.
    var friday = DateTime(local.year, local.month, local.day);
    if (friday.weekday == DateTime.saturday) {
      friday = friday.subtract(const Duration(days: 1));
    } else {
      while (friday.weekday != DateTime.friday) {
        friday = friday.add(const Duration(days: 1));
      }
    }
    var start = sunset(friday);
    var end = sunset(friday.add(const Duration(days: 1)));
    if (!utc.isBefore(end)) {
      // Saturday after sundown: the next one.
      final next = DateTime(friday.year, friday.month, friday.day + 7);
      start = sunset(next);
      end = sunset(next.add(const Duration(days: 1)));
    }
    return (start: start, end: end);
  }

  @override
  State<SabbathHoursScreen> createState() => _SabbathHoursScreenState();
}

class _SabbathHoursScreenState extends State<SabbathHoursScreen> {
  Timer? _tick;
  bool _locating = false;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    SabbathPlaces.byCode(SabbathService.profileCountryCode()).then((c) {
      if (mounted) setState(() => _home = c);
    });
    if (widget.now == null) {
      _tick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _pickPlace() async {
    setState(() => _locating = true);
    await pickSabbathPlace(context);
    if (mounted) setState(() => _locating = false);
  }

  /// The profile country, to know whether a state must be chosen.
  SabbathCountry? _home;

  /// Why the times may not be exact here, or null when they are.
  String? _placeHint() {
    if (SabbathService.usingGps() || SabbathService.place() != null) {
      return null;
    }
    final place = SabbathService.locationLabel();
    if (SabbathService.timeZoneMismatchHours() > 2) {
      return "Your phone's time zone doesn't match $place. Tap above to "
          'choose where you are.';
    }
    if (SabbathService.usingProvince) return null;
    final home = _home;
    if (home != null && home.spansTimeZones) {
      return '${home.name} has several time zones. Tap above and choose '
          'your state or province for the right sundown.';
    }
    if (home != null && home.regions.length > 1) {
      return 'These times are for the middle of $place. Tap above and '
          'choose your state or province for times closer to you.';
    }
    return null;
  }

  Future<void> _setReminder(int? minutes) async {
    final ok = await LibraryReminders.setSabbathLead(minutes);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Allow notifications in Settings to get reminders.'),
        ),
      );
    }
    if (mounted) setState(() {});
  }

  /// In the chosen place's time zone (see [SabbathService.placeTime]).
  static String _time(BuildContext context, DateTime utc) =>
      TimeOfDay.fromDateTime(SabbathService.placeTime(utc)).format(context);

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
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

  static String _date(DateTime utc) {
    final d = SabbathService.placeTime(utc);
    return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
  }

  static String _span(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h >= 48) return '${d.inDays} days ${h % 24}h';
    if (h >= 1) return '${h}h ${m}m';
    return '${d.inMinutes.clamp(1, 59)} min';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final now = _now;
    final w = SabbathHoursScreen.window(now);
    final inSabbath = !now.toUtc().isBefore(w.start);
    final lead = LibraryReminders.sabbathLead();

    final upcoming = <SabbathWindow>[];
    var cursor = w.end.add(const Duration(hours: 1));
    for (var i = 0; i < 4; i++) {
      final next = SabbathHoursScreen.window(cursor);
      upcoming.add(next);
      cursor = next.end.add(const Duration(hours: 1));
    }

    return FlatStatusBar(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'Sabbath hours',
            style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 19),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.sm,
              AppSpace.lg,
              AppSpace.xxl,
            ),
            children: [
              // The one gold mark on this screen: the horizon line, as on
              // Home's Sabbath header.
              Container(
                padding: const EdgeInsets.all(AppSpace.lg),
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: AppShadows.card(context),
                  border: const Border(
                    bottom: BorderSide(color: AppColors.goldAccent, width: 3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inSabbath ? 'HAPPY SABBATH' : 'SABBATH BEGINS',
                      style: AppTextStyles.overline.copyWith(
                        color: palette.brandBlue,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      inSabbath
                          ? 'Ends at ${_time(context, w.end)}'
                          : '${_date(w.start)} at ${_time(context, w.start)}',
                      style: AppTextStyles.headlineSmall.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      inSabbath
                          ? 'Sundown is in ${_span(w.end.difference(now.toUtc()))}'
                          : 'In ${_span(w.start.difference(now.toUtc()))} · '
                                'ends ${_date(w.end)} at ${_time(context, w.end)}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Material(
                color: Colors.transparent,
                child: ListTile(
                  onTap: _pickPlace,
                  tileColor: palette.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  leading: _locating
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          SabbathService.usingGps()
                              ? Icons.my_location_rounded
                              : Icons.place_rounded,
                          color: palette.brandBlue,
                        ),
                  title: Text(
                    'Sundown for ${SabbathService.locationLabel()}',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    SabbathService.placeClockDiffers()
                        ? 'Times in ${SabbathService.place()!.city} time · '
                              'tap to change'
                        : 'Tap to change',
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ),
              if (_placeHint() case final hint?)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: palette.textMuted,
                      ),
                      const SizedBox(width: AppSpace.xs),
                      Expanded(
                        child: Text(
                          hint,
                          style: AppTextStyles.caption.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              _label(context, 'COMING SABBATHS'),
              Container(
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  boxShadow: AppShadows.card(context),
                ),
                child: Column(
                  children: [
                    for (final s in upcoming)
                      ListTile(
                        dense: true,
                        title: Text(
                          _date(s.start),
                          style: AppTextStyles.labelMedium.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Text(
                          'Fri ${_time(context, s.start)} – Sat ${_time(context, s.end)}',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _label(context, 'REMINDER'),
              Container(
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  boxShadow: AppShadows.card(context),
                ),
                padding: const EdgeInsets.all(AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Remind me on Friday before sundown',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        for (final (label, value) in const [
                          ('Off', null),
                          ('30 min', 30),
                          ('1 hour', 60),
                          ('2 hours', 120),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: lead == value,
                            showCheckmark: false,
                            selectedColor: AppColors.primaryBlue,
                            backgroundColor: palette.card,
                            side: BorderSide(
                              color: lead == value
                                  ? AppColors.primaryBlue
                                  : palette.divider,
                            ),
                            labelStyle: AppTextStyles.labelMedium.copyWith(
                              color: lead == value
                                  ? AppColors.white
                                  : palette.text,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) => _setReminder(value),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Container(
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  boxShadow: AppShadows.card(context),
                ),
                child: SwitchListTile(
                  value: SabbathService.sabbathModeEnabled(),
                  onChanged: (v) async {
                    await SabbathService.setSabbathMode(v);
                    if (mounted) setState(() {});
                  },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  title: Text(
                    'Sabbath mode',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Quiets non-essential notifications from sundown to '
                    'sundown.',
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Text(
                'Times are calculated on your phone from the sun\'s position '
                'and can differ by a minute or two from local tables.',
                style: AppTextStyles.caption.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: AppSpace.xl, bottom: AppSpace.sm),
    child: Text(
      text,
      style: AppTextStyles.overline.copyWith(
        color: context.palette.textMuted,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
