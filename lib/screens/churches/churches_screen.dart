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
import '../../widgets/church_map.dart';
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
  String? _error;
  Position? _position;
  bool _mapView = false;

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
      body: Column(
        children: [
          _buildSearchBar(),
          _buildViewToggle(),
          if (_cities.isNotEmpty && !_mapView) _buildCityFilters(),
          Expanded(
            child: _mapView ? _buildMap() : _buildList(),
          ),
          const AdBanner(),
        ],
      ),
    );
  }

  Widget _buildViewToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color.fromRGBO(26, 26, 46, 0.06),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: _ToggleSegment(
                icon: Icons.view_list_rounded,
                label: 'List',
                selected: !_mapView,
                onTap: () => setState(() => _mapView = false),
              ),
            ),
            Expanded(
              child: _ToggleSegment(
                icon: Icons.map_rounded,
                label: 'Map',
                selected: _mapView,
                onTap: () => setState(() => _mapView = true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    final located =
        _churches.where((c) => c.hasLocation).toList(growable: false);
    if (located.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.map_outlined,
                size: 56,
                color: Color.fromRGBO(26, 26, 46, 0.3),
              ),
              const SizedBox(height: 12),
              Text(
                'No churches with coordinates yet',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleMedium.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.7),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Pins appear here as churches add their location.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.55),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ChurchesMapView(
          churches: located,
          userLatitude: _position?.latitude,
          userLongitude: _position?.longitude,
          onTapChurch: _showChurchSheet,
        ),
      ),
    );
  }

  Future<void> _showChurchSheet(Church church) async {
    final distance = _distanceLabelFor(church);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(26, 26, 46, 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.primaryGradient,
                    ),
                    child: const Icon(
                      Icons.church_rounded,
                      color: AppColors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                church.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.titleLarge.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (church.isVerified) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.verified,
                                size: 16,
                                color: AppColors.goldAccent,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            church.city,
                            if (distance != null) distance,
                          ].where((s) => s.isNotEmpty).join('  ·  '),
                          style: AppTextStyles.bodySmall.copyWith(
                            color:
                                const Color.fromRGBO(26, 26, 46, 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        MapsLauncher.openDirections(church: church);
                      },
                      icon: const Icon(Icons.directions_rounded, size: 18),
                      label: const Text('Directions'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        context.pushNamed(
                          'church_details',
                          pathParameters: {'id': church.id},
                          extra: church,
                        );
                      },
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: const Text('View details'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
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

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _churches.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final c = _churches[i];
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

class _ToggleSegment extends StatelessWidget {
  const _ToggleSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.primaryGradient : null,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected
                    ? AppColors.white
                    : const Color.fromRGBO(26, 26, 46, 0.55),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: selected
                      ? AppColors.white
                      : const Color.fromRGBO(26, 26, 46, 0.65),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
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
