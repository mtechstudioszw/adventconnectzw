import 'package:flutter/material.dart';

import '../../services/library_reminders.dart';
import '../../services/location_service.dart';
import '../../services/sabbath_places.dart';
import '../../services/sabbath_service.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/screen_shell.dart';

/// Opens the picker and applies the choice — the one way every screen
/// changes where Sabbath times are calculated (Sabbath hours, Settings).
/// Returns true when something changed.
Future<bool> pickSabbathPlace(BuildContext context) async {
  final pick = await Navigator.of(context, rootNavigator: true)
      .push<SabbathPlacePick>(
        MaterialPageRoute<SabbathPlacePick>(
          builder: (_) => SabbathPlacePicker(
            homeCountry: SabbathService.profileCountryCode(),
          ),
        ),
      );
  if (pick == null) return false;
  if (pick.useGps) {
    final pos = await LocationService.getCurrentPosition();
    if (pos == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't get your location. Check that location is "
              'on and allowed for the app.',
            ),
          ),
        );
      }
      return false;
    }
    await SabbathService.setGps(pos.latitude, pos.longitude);
  } else {
    final c = pick.country!;
    final r = pick.region!;
    await SabbathService.setPlace(
      country: c.code,
      countryName: c.name,
      region: c.regions.length == 1 ? c.name : r.name,
      city: r.city,
      lat: r.lat,
      lon: r.lon,
      timeZone: r.timeZone,
    );
  }
  await LibraryReminders.rearmSabbath();
  return true;
}

/// What the member picked.
class SabbathPlacePick {
  const SabbathPlacePick.gps() : useGps = true, country = null, region = null;
  const SabbathPlacePick.place(
    SabbathCountry this.country,
    SabbathRegion this.region,
  ) : useGps = false;

  final bool useGps;
  final SabbathCountry? country;
  final SabbathRegion? region;
}

AppBar _bar(String title) => AppBar(
  backgroundColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
  title: Text(
    title,
    style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 19),
  ),
);

InputDecoration _search(BuildContext context, String hint) {
  final palette = context.palette;
  return InputDecoration(
    hintText: hint,
    prefixIcon: Icon(Icons.search_rounded, color: palette.textMuted),
    filled: true,
    fillColor: palette.inputFill,
    isDense: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
      borderSide: BorderSide.none,
    ),
  );
}

/// Country → state/province, for where sundown is calculated. Pops a
/// [SabbathPlacePick], or null if the member backs out.
class SabbathPlacePicker extends StatefulWidget {
  const SabbathPlacePicker({super.key, this.homeCountry});

  /// The profile's country, pinned at the top.
  final String? homeCountry;

  @override
  State<SabbathPlacePicker> createState() => _SabbathPlacePickerState();
}

class _SabbathPlacePickerState extends State<SabbathPlacePicker> {
  List<SabbathCountry> _all = const [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    SabbathPlaces.all().then((c) {
      if (mounted) setState(() => _all = c);
    });
  }

  Future<void> _openCountry(SabbathCountry c) async {
    if (c.regions.length == 1) {
      Navigator.of(context).pop(SabbathPlacePick.place(c, c.regions.first));
      return;
    }
    final region = await Navigator.of(context).push<SabbathRegion>(
      MaterialPageRoute<SabbathRegion>(
        builder: (_) => _RegionPicker(country: c),
      ),
    );
    if (region != null && mounted) {
      Navigator.of(context).pop(SabbathPlacePick.place(c, region));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? _all
        : _all.where((c) => c.name.toLowerCase().contains(q)).toList();
    SabbathCountry? home;
    for (final c in _all) {
      if (c.code == widget.homeCountry?.toUpperCase()) home = c;
    }
    return FlatStatusBar(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _bar('Where do you keep Sabbath?'),
        body: SafeArea(
          top: false,
          child: _all.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.lg,
                        AppSpace.sm,
                        AppSpace.lg,
                        AppSpace.sm,
                      ),
                      child: TextField(
                        onChanged: (v) => setState(() => _q = v),
                        decoration: _search(context, 'Search countries'),
                      ),
                    ),
                    if (q.isEmpty) ...[
                      ListTile(
                        leading: Icon(
                          Icons.my_location_rounded,
                          color: palette.brandBlue,
                        ),
                        title: const Text('Use my location'),
                        subtitle: const Text(
                          'Exact sundown where you are. Kept on this phone.',
                        ),
                        onTap: () => Navigator.of(
                          context,
                        ).pop(const SabbathPlacePick.gps()),
                      ),
                      if (home != null) ...[
                        _label(context, 'YOUR COUNTRY'),
                        _countryTile(context, home),
                      ],
                      _label(context, 'ALL COUNTRIES'),
                    ],
                    for (final c in list) _countryTile(context, c),
                    Padding(
                      padding: const EdgeInsets.all(AppSpace.lg),
                      child: Text(
                        'Places from GeoNames (geonames.org), CC BY 4.0.',
                        style: AppTextStyles.caption.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _countryTile(BuildContext context, SabbathCountry c) {
    final palette = context.palette;
    return ListTile(
      title: Text(c.name, style: TextStyle(color: palette.text)),
      subtitle: c.regions.length > 1
          ? Text(
              c.spansTimeZones
                  ? '${c.regions.length} regions · several time zones'
                  : '${c.regions.length} regions',
              style: AppTextStyles.caption.copyWith(color: palette.textMuted),
            )
          : null,
      trailing: c.regions.length > 1
          ? Icon(Icons.chevron_right_rounded, color: palette.textMuted)
          : null,
      onTap: () => _openCountry(c),
    );
  }

  static Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpace.lg,
      AppSpace.lg,
      AppSpace.lg,
      4,
    ),
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

class _RegionPicker extends StatefulWidget {
  const _RegionPicker({required this.country});
  final SabbathCountry country;

  @override
  State<_RegionPicker> createState() => _RegionPickerState();
}

class _RegionPickerState extends State<_RegionPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final q = _q.trim().toLowerCase();
    final list = widget.country.regions
        .where(
          (r) =>
              q.isEmpty ||
              r.name.toLowerCase().contains(q) ||
              r.city.toLowerCase().contains(q),
        )
        .toList();
    return FlatStatusBar(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _bar(widget.country.name),
        body: SafeArea(
          top: false,
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  AppSpace.sm,
                  AppSpace.lg,
                  AppSpace.sm,
                ),
                child: TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: _search(
                    context,
                    'Search states, provinces, cities',
                  ),
                ),
              ),
              for (final r in list)
                ListTile(
                  title: Text(r.name, style: TextStyle(color: palette.text)),
                  subtitle: Text(
                    r.city == r.name
                        ? r.timeZone.replaceAll('_', ' ')
                        : '${r.city} · ${r.timeZone.replaceAll('_', ' ')}',
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(r),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
