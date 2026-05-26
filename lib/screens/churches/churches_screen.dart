import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/church_model.dart';
import '../../services/cache_service.dart';
import '../../services/church_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/church_card.dart';
import '../../widgets/last_updated_strip.dart';
import '../../widgets/offline_inline_notice.dart';
import '../widgets/main_scaffold.dart';

class ChurchesScreen extends StatefulWidget {
  const ChurchesScreen({super.key});

  @override
  State<ChurchesScreen> createState() => _ChurchesScreenState();
}

/// Filter chip identifiers per master reference Part 15.
/// All — show every church (sorted alphabetically, or by distance
///       if location is granted).
/// Nearby — top 5 churches by GPS distance. Tapping requests
///          location permission if not already granted.
/// Verified — churches that have at least one approved admin
///            (church.is_verified = true).
/// My Province — churches whose province matches the viewer's
///               profiles.province. Hidden if the viewer hasn't
///               set a province yet.
enum _ChurchFilter { all, nearby, verified, myProvince }

class _ChurchesScreenState extends State<ChurchesScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Church> _churches = [];
  bool _loading = true;
  bool _locating = false;
  String? _error;
  String? _locationError;
  LocationFailure? _locationFailure;
  Position? _position;
  static const _nearMeLimit = 5;
  _ChurchFilter _activeFilter = _ChurchFilter.all;
  String? _myProvince;

  @override
  void initState() {
    super.initState();
    _hydrateFromCache();
    _bootstrap();
  }

  static const _cacheKey = 'churches_list';

  void _hydrateFromCache() {
    try {
      final raw = CacheService.readString(_cacheKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => Church.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted || list.isEmpty) return;
      setState(() {
        _churches = list;
        _loading = false;
      });
    } catch (_) {}
  }

  Future<void> _writeCache(List<Church> list) async {
    try {
      final payload = jsonEncode(list.map((e) => e.toJson()).toList());
      await CacheService.writeString(_cacheKey, payload);
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Derived from _activeFilter so the rest of the screen (banner,
  /// distance labels) keeps reading a single source of truth without
  /// having to know about the chip enum.
  bool get _nearMode => _activeFilter == _ChurchFilter.nearby;

  Future<void> _bootstrap() async {
    // Kick off location lookup + viewer's province in parallel — both
    // can take a few seconds and we don't want to block list paint.
    _resolveLocation();
    _loadMyProvince();
    await _loadChurches();
  }

  Future<void> _loadMyProvince() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final row = await Supabase.instance.client
          .from('profiles')
          .select('province')
          .eq('id', user.id)
          .maybeSingle();
      final province = (row?['province'] as String?)?.trim();
      if (!mounted || province == null || province.isEmpty) return;
      setState(() => _myProvince = province);
    } catch (_) {
      // Best-effort — chip just stays hidden if we can't read it.
    }
  }

  Future<void> _resolveLocation() async {
    final pos = await LocationService.getCurrentPosition();
    if (!mounted || pos == null) return;
    setState(() {
      _position = pos;
      _sortByDistance();
    });
  }

  void _sortByDistance() {
    final pos = _position;
    if (pos == null) return;
    _churches.sort((a, b) {
      final ad = a.hasLocation
          ? LocationService.distanceMeters(
              fromLat: pos.latitude,
              fromLng: pos.longitude,
              toLat: a.latitude!,
              toLng: a.longitude!,
            )
          : double.infinity;
      final bd = b.hasLocation
          ? LocationService.distanceMeters(
              fromLat: pos.latitude,
              fromLng: pos.longitude,
              toLat: b.latitude!,
              toLng: b.longitude!,
            )
          : double.infinity;
      return ad.compareTo(bd);
    });
  }

  String? _distanceLabelFor(Church c) {
    final pos = _position;
    if (pos == null || !c.hasLocation) return null;
    final m = LocationService.distanceMeters(
      fromLat: pos.latitude,
      fromLng: pos.longitude,
      toLat: c.latitude!,
      toLng: c.longitude!,
    );
    return LocationService.formatDistance(m);
  }

  /// Visible list — composes the active chip filter with the loaded
  /// _churches. Falls back to the full list if a chip's data isn't
  /// available yet (e.g. location not granted while Nearby is
  /// selected, or no churches have province set).
  List<Church> _visibleChurches() {
    switch (_activeFilter) {
      case _ChurchFilter.all:
        return _churches;
      case _ChurchFilter.nearby:
        final pos = _position;
        if (pos == null) return _churches;
        // Lightweight, offline-friendly fallback chain so we always
        // return up to 5 results even when the dataset has little
        // GPS coverage:
        //
        //   1. Real GPS-tagged churches sorted by distance.
        //   2. If too few, top up with churches in the viewer's
        //      province (using profiles.province if we have it).
        //   3. If still empty, top up with whatever else is loaded
        //      so the chip never returns an empty list.
        //
        // Avoids any external geocoding (no Google Maps API) — pure
        // client-side filter over data we already have on screen.
        final geo = _churches.where((c) => c.hasLocation).toList()
          ..sort((a, b) {
            final ad = LocationService.distanceMeters(
              fromLat: pos.latitude,
              fromLng: pos.longitude,
              toLat: a.latitude!,
              toLng: a.longitude!,
            );
            final bd = LocationService.distanceMeters(
              fromLat: pos.latitude,
              fromLng: pos.longitude,
              toLat: b.latitude!,
              toLng: b.longitude!,
            );
            return ad.compareTo(bd);
          });
        final picked = <Church>[...geo.take(_nearMeLimit)];
        final seen = picked.map((c) => c.id).toSet();
        if (picked.length < _nearMeLimit && _myProvince != null) {
          for (final c in _churches) {
            if (picked.length >= _nearMeLimit) break;
            if (seen.contains(c.id)) continue;
            if ((c.province ?? '').toLowerCase() ==
                _myProvince!.toLowerCase()) {
              picked.add(c);
              seen.add(c.id);
            }
          }
        }
        if (picked.length < _nearMeLimit) {
          for (final c in _churches) {
            if (picked.length >= _nearMeLimit) break;
            if (seen.contains(c.id)) continue;
            picked.add(c);
            seen.add(c.id);
          }
        }
        return picked;
      case _ChurchFilter.verified:
        return _churches.where((c) => c.isVerified).toList();
      case _ChurchFilter.myProvince:
        final p = _myProvince;
        if (p == null || p.isEmpty) return _churches;
        return _churches
            .where((c) => (c.province ?? '').toLowerCase() == p.toLowerCase())
            .toList();
    }
  }

  /// Switch the active filter chip. Nearby is special-cased — if the
  /// user hasn't granted location yet, tapping the chip kicks off the
  /// permission request, then enables the filter only if granted.
  Future<void> _setFilter(_ChurchFilter filter) async {
    if (filter == _activeFilter) {
      // Tapping the active chip again just clears the location
      // error banner; otherwise it's a no-op.
      if (_locationError != null) {
        setState(() {
          _locationError = null;
          _locationFailure = null;
        });
      }
      return;
    }
    if (filter == _ChurchFilter.nearby && _position == null) {
      setState(() {
        _locating = true;
        _locationError = null;
        _locationFailure = null;
      });
      final result = await LocationService.getCurrentPositionDetailed();
      if (!mounted) return;
      if (!result.isSuccess) {
        setState(() {
          _locating = false;
          _locationFailure = result.failure;
          _locationError = switch (result.failure!) {
            LocationFailure.servicesDisabled =>
              'Location is turned off on this device. Turn it on in Settings, then tap Nearby again.',
            LocationFailure.permissionDenied =>
              'Advent Connect needs location permission to find nearby churches. Tap Nearby again to grant access.',
            LocationFailure.permissionDeniedForever =>
              'Location permission is blocked for Advent Connect. Open Settings to allow it.',
            LocationFailure.timeout =>
              'Took too long to get a GPS fix. Move to a window or outdoors and try again.',
            LocationFailure.unknown =>
              'Couldn\'t get your location. Please try again.',
          };
        });
        return;
      }
      setState(() {
        _position = result.position;
        _locating = false;
        _activeFilter = filter;
        _sortByDistance();
      });
      return;
    }
    setState(() {
      _activeFilter = filter;
      _locationError = null;
      _locationFailure = null;
    });
  }

  Future<void> _loadChurches() async {
    setState(() {
      if (_churches.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final list = await ChurchService.fetchChurches(
        search: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _churches = list;
        _loading = false;
        _sortByDistance();
      });
      if (_searchController.text.isEmpty) {
        unawaited(_writeCache(list));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load churches. Pull to retry.';
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _loadChurches);
  }

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      title: 'Churches',
      currentIndex: 1,
      body: Column(
        children: [
          _buildSearchBar(),
          _buildFilterChips(),
          if (_nearMode) _buildNearModeBanner(),
          if (_locationError != null) _buildLocationErrorBanner(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildNearModeBanner() {
    // Pick a label that matches whatever fallback level the
    // _visibleChurches getter is actually using right now — so the
    // user knows whether they're seeing real GPS distances or a
    // province-based estimate.
    final hasGeo = _churches.any((c) => c.hasLocation);
    final hasProvincePool = _myProvince != null &&
        _churches.any((c) =>
            (c.province ?? '').toLowerCase() == _myProvince!.toLowerCase());
    final String label;
    if (hasGeo) {
      label = 'Showing the 5 churches closest to you';
    } else if (hasProvincePool) {
      label = 'No mapped churches in your area yet — '
          'showing nearby ones in $_myProvince';
    } else {
      label = 'We\'re showing churches near your region based on '
          'available data.';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.location_on,
              color: AppColors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _loadChurches(),
        style: AppTextStyles.bodyLarge,
        decoration: InputDecoration(
          hintText: 'Search by name or city',
          prefixIcon: const Icon(
            Icons.search,
            color: AppColors.primaryBlue,
          ),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close,
                      color: Color.fromRGBO(26, 26, 46, 0.5)),
                  onPressed: () {
                    _searchController.clear();
                    _loadChurches();
                  },
                ),
          filled: true,
          fillColor: AppColors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    );
  }

  Widget _buildLocationErrorBanner() {
    // Pick the right action button for the failure type. permission-
    // deniedForever → Settings (the OS won't show the prompt again).
    // servicesDisabled → Location toggle. Everything else → just a
    // dismiss button since "try again" reopens the picker via the FAB.
    final (String? actionLabel, VoidCallback? action) = switch (
        _locationFailure) {
      LocationFailure.permissionDeniedForever => (
          'Open Settings',
          () => LocationService.openAppSettings(),
        ),
      LocationFailure.servicesDisabled => (
          'Turn On Location',
          () => LocationService.openLocationSettings(),
        ),
      _ => (null, null),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.red,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _locationError!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.red,
                  ),
                  onPressed: () => setState(() {
                    _locationError = null;
                    _locationFailure = null;
                  }),
                ),
              ],
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: action,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryBlue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    actionLabel,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Master reference Part 15 — fixed filter chip row.
  /// All / Nearby / Verified / My Province (My Province only renders
  /// when the viewer's profile has a province set).
  Widget _buildFilterChips() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _FilterChip(
            label: 'All',
            icon: Icons.apps,
            selected: _activeFilter == _ChurchFilter.all,
            onTap: () => _setFilter(_ChurchFilter.all),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Nearby',
            icon: Icons.my_location,
            selected: _activeFilter == _ChurchFilter.nearby,
            busy: _locating,
            onTap: () => _setFilter(_ChurchFilter.nearby),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Verified',
            icon: Icons.verified_outlined,
            selected: _activeFilter == _ChurchFilter.verified,
            onTap: () => _setFilter(_ChurchFilter.verified),
          ),
          if (_myProvince != null) ...[
            const SizedBox(width: 8),
            _FilterChip(
              label: 'My Province',
              icon: Icons.place_outlined,
              selected: _activeFilter == _ChurchFilter.myProvince,
              onTap: () => _setFilter(_ChurchFilter.myProvince),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: _bootstrap,
      child: _buildListContent(),
    );
  }

  Widget _buildListContent() {
    if (_loading && _churches.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }

    if (_error != null && _churches.isEmpty) {
      final isOffline = !ConnectivityService.isOnline;
      if (isOffline) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            OfflineInlineNotice(onRetry: _bootstrap),
            const SizedBox(height: 60),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'No churches cached yet.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.55),
                  ),
                ),
              ),
            ),
          ],
        );
      }
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    size: 56,
                    color: Color.fromRGBO(26, 26, 46, 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (_churches.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Icon(
                    Icons.church_outlined,
                    size: 56,
                    color: Color.fromRGBO(26, 26, 46, 0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No churches found',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Try a different search or city.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final list = _visibleChurches();
    final cachedAt = CacheService.cachedAt(_cacheKey);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: list.length + (cachedAt != null ? 1 : 0),
      separatorBuilder: (_, i) {
        if (cachedAt != null && i == 0) return const SizedBox(height: 6);
        return const SizedBox(height: 12);
      },
      itemBuilder: (context, rawIndex) {
        if (cachedAt != null && rawIndex == 0) {
          return LastUpdatedStrip(
            timestamp: cachedAt,
            isOnline: ConnectivityService.isOnline,
            onRefresh: _loadChurches,
          );
        }
        final i = cachedAt != null ? rawIndex - 1 : rawIndex;
        final c = list[i];
        return ChurchCard(
          church: c,
          distanceLabel: _distanceLabelFor(c),
          onTap: () => context.pushNamed(
            'church_details',
            pathParameters: {'id': c.id},
            extra: c,
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.white : AppColors.textDark;
    return Material(
      color: selected ? AppColors.primaryBlue : AppColors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.primaryBlue
                  : const Color.fromRGBO(26, 26, 46, 0.1),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              busy
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: fg,
                      ),
                    )
                  : Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
