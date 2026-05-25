import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
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

class _ChurchesScreenState extends State<ChurchesScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Church> _churches = [];
  List<String> _cities = [];
  String? _selectedCity;
  bool _loading = true;
  bool _locating = false;
  bool _nearMode = false;
  String? _error;
  String? _locationError;
  LocationFailure? _locationFailure;
  Position? _position;
  static const _nearMeLimit = 5;

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

  Future<void> _bootstrap() async {
    // Kick off location lookup in parallel — it can take a few seconds
    // on a cold start and we don't want to block the list rendering.
    _resolveLocation();
    await Future.wait([_loadCities(), _loadChurches()]);
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

  /// Visible list — when "Near me" is active and we have a location,
  /// trims to the closest [_nearMeLimit] churches that carry lat/lng.
  /// If no churches in the database have coordinates yet, we still
  /// return the top of the full list so the screen isn't empty — the
  /// banner above the list explains the situation.
  List<Church> _visibleChurches() {
    if (!_nearMode) return _churches;
    final pos = _position;
    if (pos == null) return _churches;
    final geo = _churches.where((c) => c.hasLocation).toList();
    if (geo.isEmpty) {
      // No mapped churches yet — return the first few so the list
      // still feels alive. The banner explains why distance chips are
      // missing.
      return _churches.take(_nearMeLimit).toList();
    }
    geo.sort((a, b) {
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
    return geo.take(_nearMeLimit).toList();
  }

  /// Toggle the "5 churches near me" filter. When turning ON, fetch a
  /// fresh location (the bootstrap one may be stale or denied). When
  /// turning OFF, just go back to the full list.
  Future<void> _toggleNearMe() async {
    if (_nearMode) {
      setState(() {
        _nearMode = false;
        _locationError = null;
        _locationFailure = null;
      });
      return;
    }
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
            'Location is turned off on this device. Turn it on in Settings, then tap Near me again.',
          LocationFailure.permissionDenied =>
            'Advent Connect needs location permission to find nearby churches. Try Near me again to grant access.',
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
      _nearMode = true;
      _sortByDistance();
    });
  }

  Future<void> _loadCities() async {
    try {
      final cities = await ChurchService.fetchAvailableCities();
      if (mounted) setState(() => _cities = cities);
    } catch (_) {}
  }

  Future<void> _loadChurches() async {
    setState(() {
      if (_churches.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final list = await ChurchService.fetchChurches(
        search: _searchController.text,
        city: _selectedCity,
      );
      if (!mounted) return;
      setState(() {
        _churches = list;
        _loading = false;
        _sortByDistance();
      });
      if (_searchController.text.isEmpty && _selectedCity == null) {
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

  void _onCitySelected(String? city) {
    setState(() => _selectedCity = city);
    _loadChurches();
  }

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      title: 'Churches',
      currentIndex: 1,
      floatingActionButton: _buildNearMeFab(),
      body: Column(
        children: [
          _buildSearchBar(),
          if (_cities.isNotEmpty) _buildCityFilters(),
          if (_nearMode) _buildNearModeBanner(),
          if (_locationError != null) _buildLocationErrorBanner(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildNearMeFab() {
    final label = _nearMode ? 'Clear' : 'Near me';
    final iconData =
        _locating ? null : (_nearMode ? Icons.close : Icons.my_location);
    return FloatingActionButton.extended(
      onPressed: _locating ? null : _toggleNearMe,
      backgroundColor: AppColors.primaryBlue,
      foregroundColor: AppColors.white,
      elevation: 6,
      icon: _locating
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppColors.white,
              ),
            )
          : Icon(iconData, size: 20),
      label: Text(
        label,
        style: AppTextStyles.buttonText.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildNearModeBanner() {
    final hasGeo = _churches.any((c) => c.hasLocation);
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
                hasGeo
                    ? 'Showing the 5 churches closest to you'
                    : 'No mapped churches in your area yet — showing all',
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

  Widget _buildCityFilters() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _CityChip(
            label: 'All cities',
            selected: _selectedCity == null,
            onTap: () => _onCitySelected(null),
          ),
          const SizedBox(width: 8),
          for (final city in _cities) ...[
            _CityChip(
              label: city,
              selected: _selectedCity == city,
              onTap: () => _onCitySelected(city),
            ),
            const SizedBox(width: 8),
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

class _CityChip extends StatelessWidget {
  const _CityChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryBlue : AppColors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
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
          child: Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color: selected ? AppColors.white : AppColors.textDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
