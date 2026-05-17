import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/church_model.dart';
import '../../models/event_model.dart';
import '../../models/job_model.dart';
import '../../models/member_directory_model.dart';
import '../../models/product_model.dart';
import '../../services/church_service.dart';
import '../../services/directory_service.dart';
import '../../services/event_service.dart';
import '../../services/job_service.dart';
import '../../services/marketplace_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/start_conversation_sheet.dart';

/// Cross-content search. Hits churches, events, products and jobs in
/// parallel — small per-list limit each so the UI stays snappy.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  bool _searching = false;
  String _lastQuery = '';
  List<Church> _churches = const [];
  List<Event> _events = const [];
  List<Product> _products = const [];
  List<Job> _jobs = const [];
  List<MemberDirectoryEntry> _people = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(value.trim());
    });
  }

  Future<void> _runSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searching = false;
        _lastQuery = '';
        _churches = const [];
        _events = const [];
        _products = const [];
        _jobs = const [];
        _people = const [];
      });
      return;
    }
    setState(() {
      _searching = true;
      _lastQuery = query;
    });
    try {
      final results = await Future.wait([
        _searchPeople(query),
        ChurchService.fetchChurches(search: query),
        EventService.fetchEvents(search: query),
        MarketplaceService.fetchProducts(search: query),
        JobService.fetchJobs(search: query),
      ]);
      if (!mounted) return;
      setState(() {
        _people = (results[0] as List<MemberDirectoryEntry>).take(8).toList();
        _churches = (results[1] as List<Church>).take(8).toList();
        _events = (results[2] as List<Event>).take(8).toList();
        _products = (results[3] as List<Product>).take(8).toList();
        _jobs = (results[4] as List<Job>).take(8).toList();
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  /// People search: combines the server-side directory query (profession,
  /// skills, city, bio) with a client-side name filter against the recent
  /// directory entries. That way "Tendai" still matches even though name
  /// lives on the joined profiles row.
  Future<List<MemberDirectoryEntry>> _searchPeople(String query) async {
    final lower = query.toLowerCase();
    final results = await Future.wait([
      DirectoryService.fetchEntries(search: query),
      DirectoryService.fetchSuggestedMembers(limit: 60),
    ]);
    final byProfession = results[0];
    final recent = results[1];

    final seen = <String>{};
    final merged = <MemberDirectoryEntry>[];
    for (final e in byProfession) {
      if (seen.add(e.id)) merged.add(e);
    }
    for (final e in recent) {
      if (seen.contains(e.id)) continue;
      final name = (e.fullName ?? '').toLowerCase();
      if (name.contains(lower)) {
        seen.add(e.id);
        merged.add(e);
      }
    }
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _people.isNotEmpty ||
        _churches.isNotEmpty ||
        _events.isNotEmpty ||
        _products.isNotEmpty ||
        _jobs.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: Column(
        children: [
          _buildHero(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: _SearchField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onChanged,
              onClear: () {
                _controller.clear();
                _onChanged('');
              },
            ),
          ),
          Expanded(
            child: _searching
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryBlue,
                    ),
                  )
                : _lastQuery.isEmpty
                    ? _buildHint()
                    : hasResults
                        ? _buildResults()
                        : _buildEmpty(),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return ClipPath(
      clipper: _HeroClipper(),
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const ScreenHeroBackButton(fallbackRoute: 'home'),
                  ],
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SEARCH',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Find anything',
                        style: AppTextStyles.displayMedium.copyWith(
                          color: AppColors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'People, churches, events, products and jobs — '
                        'all in one place.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHint() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          'TRY SEARCHING FOR',
          style: AppTextStyles.labelSmall.copyWith(
            color: const Color.fromRGBO(26, 26, 46, 0.55),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            _SuggestionChip('Tendai'),
            _SuggestionChip('Harare central'),
            _SuggestionChip('Camp meeting'),
            _SuggestionChip('Plumber'),
            _SuggestionChip('Bibles'),
            _SuggestionChip('Solusi'),
            _SuggestionChip('Teaching'),
          ],
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      child: EmptyStateCard(
        icon: Icons.search_off,
        title: 'No matches for "$_lastQuery"',
        message:
            'Try a shorter keyword or a different spelling — searches look across churches, events, products and jobs.',
      ),
    );
  }

  Widget _buildResults() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        if (_people.isNotEmpty)
          _Section(
            label: 'PEOPLE',
            count: _people.length,
            children: [
              for (final p in _people)
                _PersonRow(
                  person: p,
                  onTap: () => showStartConversationSheet(
                    context,
                    otherUserId: p.userId,
                    otherUserName: p.fullName ?? 'a member',
                    source: 'search',
                  ),
                ),
            ],
          ),
        if (_churches.isNotEmpty)
          _Section(
            label: 'CHURCHES',
            count: _churches.length,
            children: [
              for (final c in _churches)
                _ChurchRow(
                  church: c,
                  onTap: () => context.pushNamed(
                    'church_details',
                    pathParameters: {'id': c.id},
                    extra: c,
                  ),
                ),
            ],
          ),
        if (_events.isNotEmpty)
          _Section(
            label: 'EVENTS',
            count: _events.length,
            children: [
              for (final e in _events)
                _EventRow(
                  event: e,
                  onTap: () => context.pushNamed(
                    'event_details',
                    pathParameters: {'id': e.id},
                    extra: e,
                  ),
                ),
            ],
          ),
        if (_products.isNotEmpty)
          _Section(
            label: 'PRODUCTS',
            count: _products.length,
            children: [
              for (final p in _products)
                _ProductRow(
                  product: p,
                  onTap: () => context.pushNamed(
                    'product_details',
                    pathParameters: {'id': p.id},
                    extra: p,
                  ),
                ),
            ],
          ),
        if (_jobs.isNotEmpty)
          _Section(
            label: 'JOBS',
            count: _jobs.length,
            children: [
              for (final j in _jobs)
                _JobRow(
                  job: j,
                  onTap: () => context.pushNamed(
                    'job_details',
                    pathParameters: {'id': j.id},
                    extra: j,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.count,
    required this.children,
  });
  final String label;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Text(
                label,
                style: AppTextStyles.labelSmall.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final c in children) ...[c, const SizedBox(height: 10)],
        const SizedBox(height: 6),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.onTap});
  final MemberDirectoryEntry person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = (person.fullName ?? '').trim().isEmpty
        ? 'Member'
        : person.fullName!.trim();
    final parts = <String>[
      if ((person.profession ?? '').trim().isNotEmpty) person.profession!.trim(),
      if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
      if ((person.churchName ?? '').trim().isNotEmpty) person.churchName!.trim(),
    ];
    final subtitle = parts.isEmpty ? 'On Advent Connect' : parts.join('  ·  ');
    return ScreenCard(
      padding: const EdgeInsets.all(14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            children: [
              _PersonAvatar(
                photoUrl: person.profilePhotoUrl,
                fullName: name,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chat_bubble_outline_rounded,
                color: AppColors.primaryBlue,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({required this.photoUrl, required this.fullName});
  final String? photoUrl;
  final String fullName;

  String get _initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryBlue.withValues(alpha: 0.10),
        image: hasPhoto
            ? DecorationImage(
                image: NetworkImage(photoUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: hasPhoto
          ? null
          : Text(
              _initials,
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
    );
  }
}

class _ChurchRow extends StatelessWidget {
  const _ChurchRow({required this.church, required this.onTap});
  final Church church;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Row(
      icon: Icons.church,
      title: church.name,
      subtitle: church.city,
      onTap: onTap,
      trailing: church.isVerified
          ? const Icon(Icons.verified, color: AppColors.goldAccent, size: 16)
          : null,
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.onTap});
  final Event event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Row(
      icon: Icons.event,
      title: event.title,
      subtitle:
          '${event.eventDate.day}/${event.eventDate.month}  ·  ${event.eventTime}${event.location != null ? "  ·  ${event.location}" : ""}',
      onTap: onTap,
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Row(
      icon: Icons.shopping_bag_outlined,
      title: product.title,
      subtitle: '${product.formatPrice()}  ·  ${product.sellerName}',
      onTap: onTap,
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job, required this.onTap});
  final Job job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loc = (job.location ?? '').trim();
    final companyLine = loc.isEmpty ? job.company : '${job.company}  ·  $loc';
    return _Row(
      icon: Icons.work_outline,
      title: job.title,
      subtitle: companyLine,
      onTap: onTap,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ScreenCard(
      padding: const EdgeInsets.all(14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primaryBlue, size: 20),
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
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleSmall.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 6),
                          trailing!,
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color.fromRGBO(26, 26, 46, 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search the community',
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: const Color.fromRGBO(26, 26, 46, 0.45),
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 14, right: 10),
            child: Icon(
              Icons.search,
              color: AppColors.primaryBlue,
              size: 20,
            ),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 44),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Color.fromRGBO(26, 26, 46, 0.5),
                    size: 18,
                  ),
                  onPressed: onClear,
                ),
          filled: true,
          fillColor: AppColors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: AppColors.primaryBlue,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color.fromRGBO(26, 26, 46, 0.08)),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelMedium.copyWith(
          color: AppColors.textDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HeroClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 28);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 28,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
