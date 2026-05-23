import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/event_model.dart';
import '../../services/connectivity_service.dart';
import '../../services/event_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/event_card.dart';
import '../../widgets/offline_inline_notice.dart';
import '../widgets/main_scaffold.dart';
import '../widgets/post_form_widgets.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Event> _upcoming = [];
  List<Event> _past = [];
  Set<String> _rsvpedIds = <String>{};
  DateTimeRange? _dateRange;
  bool _loadingUpcoming = true;
  bool _loadingPast = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _entrance.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 1 && _past.isEmpty && !_loadingPast) {
      _loadPast();
    }
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadUpcoming(),
      _refreshRsvps(),
    ]);
  }

  Future<void> _refreshRsvps() async {
    try {
      final ids = await EventService.fetchUserRsvpedEventIds();
      if (mounted) setState(() => _rsvpedIds = ids);
    } catch (_) {}
  }

  Future<void> _loadUpcoming() async {
    setState(() {
      _loadingUpcoming = true;
      _error = null;
    });
    try {
      final list = await EventService.fetchEvents(
        search: _searchController.text,
        upcomingOnly: true,
        from: _dateRange?.start,
        to: _dateRange?.end,
      );
      if (!mounted) return;
      setState(() {
        _upcoming = list;
        _loadingUpcoming = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load events. Pull to retry.';
        _loadingUpcoming = false;
      });
    }
  }

  Future<void> _loadPast() async {
    setState(() => _loadingPast = true);
    try {
      final list = await EventService.fetchEvents(
        search: _searchController.text,
        upcomingOnly: false,
        from: _dateRange?.start,
        to: _dateRange?.end,
      );
      if (!mounted) return;
      setState(() {
        _past = list;
        _loadingPast = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPast = false);
    }
  }

  Future<void> _refreshActive() async {
    if (_tabController.index == 0) {
      await Future.wait([_loadUpcoming(), _refreshRsvps()]);
    } else {
      await Future.wait([_loadPast(), _refreshRsvps()]);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _refreshActive);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _dateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryBlue,
              onPrimary: AppColors.white,
              onSurface: AppColors.textDark,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _refreshActive();
    }
  }

  void _clearDateRange() {
    setState(() => _dateRange = null);
    _refreshActive();
  }

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      title: 'Events',
      currentIndex: 2,
      floatingActionButton: const PostFab(
        routeName: 'post_event',
        tooltip: 'Post an event',
      ),
      body: AnimatedBuilder(
        animation: _entrance,
        builder: (context, child) => Opacity(
          opacity: _fade.value,
          child: Transform.translate(
            offset: Offset(0, _slide.value),
            child: child,
          ),
        ),
        child: Column(
          children: [
            _buildSearchBar(),
            _buildDateFilter(),
            _buildPillTabs(),
            const SizedBox(height: 4),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildList(_upcoming, _loadingUpcoming, isUpcoming: true),
                  _buildList(_past, _loadingPast, isUpcoming: false),
                ],
              ),
            ),
            const AdBanner(),
          ],
        ),
      ),
    );
  }

  Widget _buildPillTabs() {
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
        child: TabBar(
          controller: _tabController,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: AppColors.white,
          unselectedLabelColor: const Color.fromRGBO(26, 26, 46, 0.6),
          indicator: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          labelStyle: AppTextStyles.titleSmall.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 0.3,
          ),
          unselectedLabelStyle: AppTextStyles.titleSmall.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Past'),
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
        onSubmitted: (_) => _refreshActive(),
        style: AppTextStyles.bodyLarge,
        decoration: InputDecoration(
          hintText: 'Search events',
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
                    _refreshActive();
                  },
                ),
          filled: true,
          fillColor: AppColors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    );
  }

  Widget _buildDateFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: _pickDateRange,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _dateRange != null
                        ? AppColors.primaryBlue
                        : const Color.fromRGBO(26, 26, 46, 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.date_range,
                      size: 18,
                      color: _dateRange != null
                          ? AppColors.primaryBlue
                          : const Color.fromRGBO(26, 26, 46, 0.6),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _dateRange == null
                            ? 'Filter by date range'
                            : '${_formatRangeDate(_dateRange!.start)}  →  ${_formatRangeDate(_dateRange!.end)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: _dateRange != null
                              ? AppColors.textDark
                              : const Color.fromRGBO(26, 26, 46, 0.6),
                          fontWeight: _dateRange != null
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_dateRange != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: _clearDateRange,
              icon: const Icon(Icons.close, size: 20),
              color: const Color.fromRGBO(26, 26, 46, 0.6),
              tooltip: 'Clear date filter',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildList(List<Event> events, bool loading,
      {required bool isUpcoming}) {
    return RefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: _refreshActive,
      child: _buildListContent(events, loading, isUpcoming: isUpcoming),
    );
  }

  Widget _buildListContent(List<Event> events, bool loading,
      {required bool isUpcoming}) {
    if (loading && events.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }

    // Soft inline notice instead of a full-screen blocker when the
    // load failed because we're offline. The tab still feels alive —
    // the user sees the search bar, tabs, and either cached items or
    // the empty state right below this strip.
    if (_error != null && events.isEmpty && isUpcoming) {
      final isOffline = !ConnectivityService.isOnline;
      if (isOffline) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            OfflineInlineNotice(onRetry: _refreshActive),
            const SizedBox(height: 80),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'No events cached yet for this tab.',
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

    if (events.isEmpty) {
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
                    isUpcoming
                        ? Icons.event_outlined
                        : Icons.history_toggle_off,
                    size: 56,
                    color: const Color.fromRGBO(26, 26, 46, 0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isUpcoming
                        ? 'No upcoming events'
                        : 'No past events',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.7),
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
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, i) {
        final e = events[i];
        return EventCard(
          event: e,
          isGoing: _rsvpedIds.contains(e.id),
          onTap: () async {
            await context.pushNamed(
              'event_details',
              pathParameters: {'id': e.id},
              extra: e,
            );
            if (mounted) _refreshActive();
          },
        );
      },
    );
  }

  String _formatRangeDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}
