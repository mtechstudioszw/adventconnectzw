import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../models/church_model.dart';
import '../../services/church_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/church_card.dart';
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
  Position? _position;
  static const _nearMeLimit = 5;

  @override
  void initState() {
    super.initState();
    _bootstrap();
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
      });
      return;
    }
    setState(() {
      _locating = true;
      _locationError = null;
    });
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    if (pos == null) {
      setState(() {
        _locating = false;
        _locationError =
            'Couldn\'t get your location. Check location permission and try again.';
      });
      return;
    }
    setState(() {
      _position = pos;
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
      _loading = true;
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
          const AdBanner(),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
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
