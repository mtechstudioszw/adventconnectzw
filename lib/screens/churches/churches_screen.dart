import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/zimbabwe_cities.dart';
import '../../models/church_model.dart';
import '../../services/cache_service.dart';
import '../../services/church_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/church_card.dart';
import '../../widgets/last_updated_strip.dart';
import '../../widgets/offline_inline_notice.dart';
import '../widgets/main_scaffold.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/content_reveal.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/shimmer_loaders.dart';

class ChurchesScreen extends StatefulWidget {
  const ChurchesScreen({super.key});

  @override
  State<ChurchesScreen> createState() => _ChurchesScreenState();
}

/// Filter chip identifiers per master reference Part 15.
/// All â€” show every church (sorted alphabetically, or by distance
///       if location is granted).
/// Nearby â€” top 5 churches by GPS distance. Tapping requests
///          location permission if not already granted.
/// Verified â€” churches that have at least one approved admin
///            (church.is_verified = true).
/// My Province â€” churches whose province matches the viewer's
///               profiles.province. Hidden if the viewer hasn't
///               set a province yet.
class _ChurchesScreenState extends State<ChurchesScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Church> _churches = [];
  bool _loading = true;
  String? _error;
  String? _locationError;
  LocationFailure? _locationFailure;
  // Active city filter (null = all cities) + verified-only toggle.
  String? _cityFilter;
  bool _verifiedOnly = false;

  // "Near me" by real distance: the device location + a flag to rank churches
  // (that have coordinates) nearest-first.
  double? _devLat;
  double? _devLng;
  bool _nearMode = false;

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
    await _loadChurches();
  }

  /// Visible list â€” composes the active chip filter with the loaded
  /// _churches. Falls back to the full list if a chip's data isn't
  /// available yet (e.g. location not granted while Nearby is
  /// selected, or no churches have province set).
  List<Church> _visibleChurches() {
    var list = _churches;
    if (_cityFilter != null) {
      final cf = _cityFilter!.toLowerCase();
      list = list.where((c) => c.city.toLowerCase() == cf).toList();
    }
    if (_verifiedOnly) {
      list = list.where((c) => c.isVerified).toList();
    }
    // Near me: rank churches that have coordinates (geocoded from the address
    // a church admin entered) nearest-first, then the rest.
    if (_nearMode && _devLat != null && _devLng != null) {
      final ranked = <(double, Church)>[];
      final rest = <Church>[];
      for (final c in list) {
        if (c.latitude != null && c.longitude != null) {
          ranked.add((
            LocationService.distanceMeters(
              fromLat: _devLat!,
              fromLng: _devLng!,
              toLat: c.latitude!,
              toLng: c.longitude!,
            ),
            c,
          ));
        } else {
          rest.add(c);
        }
      }
      ranked.sort((a, b) => a.$1.compareTo(b.$1));
      list = [...ranked.map((e) => e.$2), ...rest];
    }
    return list;
  }

  /// Top cities by church count (for the quick chips). Computed from the
  /// loaded list so it reflects the real data.
  List<String> _topCities({int limit = 8}) {
    final counts = <String, int>{};
    for (final c in _churches) {
      final city = c.city.trim();
      if (city.isEmpty) continue;
      counts[city] = (counts[city] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList();
  }

  /// 📍 Near me — resolve the device GPS to the nearest Zimbabwe city and
  /// filter to that city's churches (church rows have no coordinates, so
  /// city-level is the best "near me" the data supports).
  Future<void> _nearMe() async {
    setState(() {
      _locationError = null;
      _locationFailure = null;
    });
    final result = await LocationService.getCurrentPositionDetailed();
    if (!mounted) return;
    if (result.position == null) {
      setState(() {
        _locationFailure = result.failure;
        _locationError = 'Turn on location to find churches near you.';
      });
      return;
    }
    // Rank ALL churches by real distance from the device. Churches with
    // coordinates (geocoded from their address) float to the top, nearest
    // first. If none have coordinates yet, fall back to the nearest city so
    // the button still does something useful.
    setState(() {
      _devLat = result.position!.latitude;
      _devLng = result.position!.longitude;
      _nearMode = true;
      _cityFilter = null;
    });
    final anyCoords = _churches.any((c) => c.latitude != null);
    if (!anyCoords) {
      final city = nearestZimbabweCity(
        result.position!.latitude,
        result.position!.longitude,
      );
      if (city != null) setState(() => _cityFilter = city);
    }
  }

  /// Searchable picker over every city in the loaded data.
  Future<void> _pickCity() async {
    final cities = <String>{
      for (final c in _churches)
        if (c.city.trim().isNotEmpty) c.city.trim(),
    }.toList()..sort();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CityPickerSheet(cities: cities),
    );
    if (picked != null && mounted) setState(() => _cityFilter = picked);
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
      // Churches gave up its nav slot to Advent Chat (2026-07-27). It is now
      // pushed from Home / Profile, so no tab renders as active — the island
      // stays only so members can jump straight to another section.
      currentIndex: -1,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nearMe,
        backgroundColor: AppColors.primaryBlue,
        icon: const Icon(Icons.my_location, color: AppColors.white),
        label: Text(
          'Near me',
          style: AppTextStyles.buttonText.copyWith(color: AppColors.white),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildFilterChips(),
          if (_cityFilter != null) _buildCityBanner(),
          if (_locationError != null) _buildLocationErrorBanner(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildCityBanner() {
    final count = _visibleChurches().length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on, color: AppColors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$count church${count == 1 ? '' : 'es'} in $_cityFilter',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _cityFilter = null),
              child: const Icon(Icons.close, color: AppColors.white, size: 18),
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
          prefixIcon: const Icon(Icons.search, color: AppColors.primaryBlue),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, color: context.palette.textMuted),
                  onPressed: () {
                    _searchController.clear();
                    _loadChurches();
                  },
                ),
          filled: true,
          fillColor: context.palette.inputFill,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    );
  }

  Widget _buildLocationErrorBanner() {
    // Pick the right action button for the failure type. permission-
    // deniedForever â†’ Settings (the OS won't show the prompt again).
    // servicesDisabled â†’ Location toggle. Everything else â†’ just a
    // dismiss button since "try again" reopens the picker via the FAB.
    final (
      String? actionLabel,
      VoidCallback? action,
    ) = switch (_locationFailure) {
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
                const Icon(Icons.error_outline, color: AppColors.red, size: 18),
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
                  icon: const Icon(Icons.close, size: 18, color: AppColors.red),
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

  /// City-based filter row: All / Verified, the biggest cities as quick
  /// chips, and a "More cities" entry that opens a searchable picker. The
  /// 📍 Near me FAB resolves the device location to the nearest city.
  Widget _buildFilterChips() {
    final top = _topCities();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _FilterChip(
            label: 'All',
            icon: Icons.apps,
            selected: _cityFilter == null && !_verifiedOnly && !_nearMode,
            onTap: () => setState(() {
              _cityFilter = null;
              _verifiedOnly = false;
              _nearMode = false;
              _devLat = null;
              _devLng = null;
            }),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Verified',
            icon: Icons.verified_outlined,
            selected: _verifiedOnly,
            onTap: () => setState(() => _verifiedOnly = !_verifiedOnly),
          ),
          for (final city in top) ...[
            const SizedBox(width: 8),
            _FilterChip(
              label: city,
              icon: Icons.location_city,
              selected: _cityFilter == city,
              onTap: () => setState(
                () => _cityFilter = _cityFilter == city ? null : city,
              ),
            ),
          ],
          const SizedBox(width: 8),
          _FilterChip(
            label: 'More cities',
            icon: Icons.expand_more,
            selected: false,
            onTap: _pickCity,
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return BrandedRefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: _bootstrap,
      // Card-shaped shimmer crossfades into the directory.
      child: ContentReveal(
        loading: _loading && _churches.isEmpty,
        skeleton: ShimmerLoaders.cardList(count: 7),
        child: _buildListContent(),
      ),
    );
  }

  Widget _buildListContent() {
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
                    color: context.palette.textMuted,
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
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 56,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textMuted,
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
                  Icon(
                    Icons.church_outlined,
                    size: 56,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No churches found',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Try a different search or city.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textMuted,
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
        final card = ChurchCard(
          church: c,
          onTap: () => context.pushNamed(
            'church_details',
            pathParameters: {'id': c.id},
            extra: c,
          ),
        );
        // First screenful cascades in; the rest mount plainly.
        if (i >= 8) return card;
        return StaggeredReveal(index: i, rise: 18, child: card);
      },
    );
  }
}

/// Searchable bottom-sheet list of every city, returns the chosen city.
class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet({required this.cities});
  final List<String> cities;
  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.cities
        : widget.cities.where((c) => c.toLowerCase().contains(q)).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, controller) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: ctx.palette.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search city',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: ctx.palette.inputFill,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: filtered.length,
              itemBuilder: (_, i) => ListTile(
                leading: const Icon(
                  Icons.location_city,
                  color: AppColors.primaryBlue,
                ),
                title: Text(filtered[i]),
                onTap: () => Navigator.pop(context, filtered[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.white : AppColors.text;
    return PressEffect(
      child: Material(
        color: selected ? AppColors.primaryBlue : context.palette.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? AppColors.primaryBlue : AppColors.divider,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: fg),
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
      ),
    );
  }
}
