import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/org_page_model.dart';
import '../../services/page_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/pages/page_tile.dart';
import '../../widgets/screen_shell.dart';

/// The organization directory (brief §9): ministries, schools, community
/// organizations and businesses, plus a way into the existing church
/// directory. Separate from a person's own church association on their
/// profile — following a Page here never makes anyone a member of it.
class PagesScreen extends StatefulWidget {
  const PagesScreen({super.key});

  @override
  State<PagesScreen> createState() => _PagesScreenState();
}

class _PagesScreenState extends State<PagesScreen> {
  PageCategory? _category;
  final _search = TextEditingController();
  Timer? _debounce;
  List<OrgPage> _pages = const [];
  List<OrgPage> _mine = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    PageService.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    PageService.revision.removeListener(_load);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        PageService.directory(category: _category, query: _search.text),
        PageService.mine(),
      ]);
      if (!mounted) return;
      setState(() {
        _pages = results[0];
        _mine = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            PageService.messageFor(e) ??
            'Could not load Pages. Pull down to try again.';
      });
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  void _pick(PageCategory? c) {
    if (c == _category) return;
    setState(() => _category = c);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ScreenHero(
              title: 'Pages',
              tagline: 'ORGANIZATIONS',
              subtitle: 'Ministries, schools, community groups and businesses',
              fallbackRoute: 'profile',
              trailing: PageService.available
                  ? HeaderIconButton(
                      icon: Icons.add_rounded,
                      tooltip: 'Create a Page',
                      onTap: () => context.pushNamed('page_create'),
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _search,
                onChanged: _onSearch,
                textInputAction: TextInputAction.search,
                style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
                decoration: InputDecoration(
                  hintText: 'Search Pages by name or town',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: palette.card,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    borderSide: BorderSide(color: palette.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    borderSide: BorderSide(color: palette.divider),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _Chip(
                    label: 'All',
                    selected: _category == null,
                    onTap: () => _pick(null),
                  ),
                  for (final c in PageCategory.values)
                    _Chip(
                      label: c.shortLabel,
                      icon: c.icon,
                      selected: _category == c,
                      onTap: () => _pick(c),
                    ),
                  // Churches keep their own directory and verified admins.
                  _Chip(
                    label: 'Churches',
                    icon: Icons.church_outlined,
                    selected: false,
                    trailingArrow: true,
                    onTap: () => context.pushNamed('churches'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_mine.isNotEmpty) ...[
              _SectionLabel('YOUR PAGES'),
              for (final p in _mine)
                PageTile(
                  page: p,
                  onTap: () => context.pushNamed(
                    'page_details',
                    pathParameters: {'id': p.id},
                  ),
                ),
              const SizedBox(height: 8),
            ],
            if (_loading && _pages.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: BrandSpinner(size: 30)),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: EmptyStateCard(
                  icon: Icons.apartment_rounded,
                  title: "Can't show Pages",
                  message: _error!,
                ),
              )
            else if (_pages.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: EmptyStateCard(
                  icon: Icons.apartment_rounded,
                  title: _search.text.trim().isEmpty
                      ? 'No Pages here yet'
                      : 'No Pages match',
                  message:
                      'Run a ministry, school, community group or business? '
                      'Give it a Page so people can follow its updates.',
                  action: FilledButton.icon(
                    onPressed: () => context.pushNamed('page_create'),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create a Page'),
                  ),
                ),
              )
            else ...[
              _SectionLabel(
                _category == null
                    ? 'DISCOVER'
                    : _category!.shortLabel.toUpperCase(),
              ),
              for (final p in _pages)
                PageTile(
                  page: p,
                  onTap: () => context.pushNamed(
                    'page_details',
                    pathParameters: {'id': p.id},
                  ),
                ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Text(
        text,
        style: AppTextStyles.labelSmall.copyWith(
          color: context.palette.textMuted,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.3,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailingArrow = false,
  });
  final String label;
  final IconData? icon;
  final bool selected;
  final bool trailingArrow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = selected ? AppColors.white : palette.text;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? AppColors.primaryBlue : palette.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: selected ? null : Border.all(color: palette.divider),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (trailingArrow) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 16, color: fg),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
