import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/prayer_model.dart';
import '../../services/prayer_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/prayer_card.dart';
import '../widgets/main_scaffold.dart';
import '../widgets/post_form_widgets.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';

class PrayerScreen extends StatefulWidget {
  const PrayerScreen({super.key});

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  List<Prayer> _prayers = [];
  Set<String> _prayedIds = <String>{};
  Set<String> _busyIds = <String>{};
  bool _loading = true;
  /// null = "All" chip. Otherwise a PrayerCategory whose .code is
  /// passed to fetchPrayers() to narrow the server-side query.
  PrayerCategory? _activeCategory;

  @override
  void initState() {
    super.initState();
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
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        PrayerService.fetchPrayers(category: _activeCategory?.code),
        PrayerService.fetchUserPrayedIds(),
      ]);
      if (!mounted) return;
      setState(() {
        _prayers = results[0] as List<Prayer>;
        _prayedIds = results[1] as Set<String>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _selectCategory(PrayerCategory? next) async {
    if (next == _activeCategory) return;
    setState(() => _activeCategory = next);
    await _bootstrap();
  }

  Future<void> _togglePray(Prayer prayer) async {
    if (_busyIds.contains(prayer.id)) return;
    setState(() => _busyIds = {..._busyIds, prayer.id});
    final wasPraying = _prayedIds.contains(prayer.id);
    try {
      // The service returns the authoritative post-write prayer_count
      // (computed by the bump_prayer_count DB trigger). Trust that
      // instead of our local +1 / -1 so quick re-taps, duplicate
      // inserts, and trigger-lag never leave the badge out of sync.
      final newCount = wasPraying
          ? await PrayerService.unpray(prayer.id)
          : await PrayerService.pray(prayer.id);
      if (!mounted) return;
      setState(() {
        if (wasPraying) {
          _prayedIds = _prayedIds.where((id) => id != prayer.id).toSet();
        } else {
          _prayedIds = {..._prayedIds, prayer.id};
        }
        _prayers = _prayers
            .map((p) =>
                p.id == prayer.id ? p.copyWith(prayerCount: newCount) : p)
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not update prayer status.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(
            () => _busyIds = _busyIds.where((id) => id != prayer.id).toSet());
      }
    }
  }

  Future<void> _openPostScreen() async {
    await context.pushNamed('post_prayer');
    if (mounted) await _bootstrap();
  }

  Future<void> _confirmDelete(Prayer prayer) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text('Delete this prayer?', style: AppTextStyles.headlineSmall),
        content: Text(
          'Your request and every "I\'m praying" reaction will be removed. '
          'This can\'t be undone.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: context.palette.textMuted,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style:
                  AppTextStyles.labelMedium.copyWith(color: context.palette.text),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text('Delete', style: AppTextStyles.labelLarge),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PrayerService.deletePrayer(prayer.id);
      if (!mounted) return;
      // Drop the row locally so the list updates without a full
      // reload roundtrip; _bootstrap on next refresh corrects drift.
      setState(() => _prayers = _prayers.where((p) => p.id != prayer.id).toList());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Prayer deleted.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not delete. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _editPrayer(Prayer prayer) async {
    final controller = TextEditingController(text: prayer.content);
    final newContent = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Edit prayer', style: AppTextStyles.headlineSmall),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          style: AppTextStyles.bodyMedium,
          decoration: const InputDecoration(
            hintText: 'Update your prayer request…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: AppTextStyles.labelMedium
                    .copyWith(color: context.palette.text)),
          ),
          FilledButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: Text('Save', style: AppTextStyles.labelLarge),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newContent == null || newContent.trim() == prayer.content.trim()) {
      return;
    }
    try {
      await PrayerService.updatePrayer(
        prayerId: prayer.id,
        content: newContent,
        visibility: prayer.isAnonymous ? 'anonymous' : 'public',
        category: prayer.category.code,
      );
      if (!mounted) return;
      _bootstrap(); // reload so the edited content shows
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text('Prayer updated.',
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.white)),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text('Could not update. Try again.',
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.white)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      // Prayer stays ad-free (faith-sensitive) — per the app's ad rules.
      showAd: false,
      title: 'Prayer',
      // Prayer is reached from inside Profile (My prayers), so we highlight
      // the Profile tab. Per master reference Part 7, Prayer is not a
      // top-level tab.
      currentIndex: 4,
      floatingActionButton: const PostFab(
        routeName: 'post_prayer',
        tooltip: 'Share a prayer',
        icon: Icons.volunteer_activism,
      ),
      body: Column(
        children: [
          _buildCategoryChips(),
          Expanded(
            child: BrandedRefreshIndicator(
              color: AppColors.primaryBlue,
              onRefresh: _bootstrap,
              child: AnimatedBuilder(
                animation: _entrance,
                builder: (context, child) => Opacity(
                  opacity: _fade.value,
                  child: Transform.translate(
                    offset: Offset(0, _slide.value),
                    child: child,
                  ),
                ),
                child: _buildList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    return Container(
      color: context.palette.scaffoldBg,
      child: SizedBox(
        height: 50,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          children: [
            _CategoryChip(
              label: 'All',
              selected: _activeCategory == null,
              onTap: () => _selectCategory(null),
            ),
            for (final c in PrayerCategory.values) ...[
              const SizedBox(width: 8),
              _CategoryChip(
                label: c.label,
                selected: _activeCategory == c,
                onTap: () => _selectCategory(c),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading && _prayers.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }
    if (_prayers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.volunteer_activism_outlined,
                    color: AppColors.primaryBlue,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Be the first to share',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Share a prayer request and pray together with the SDA community in Zimbabwe.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: context.palette.textMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                _GradientButton(
                  label: 'Share a prayer',
                  onTap: _openPostScreen,
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _prayers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final p = _prayers[i];
        // Anonymous prayers come back with an empty authorId — there's
        // nothing to navigate to and the row should stay inert.
        final canViewAuthor = p.authorId.isNotEmpty;
        // Ownership is computed server-side BEFORE the anonymous mask, so the
        // poster can still manage a prayer they posted anonymously.
        final isMine = p.isMine;
        return PrayerCard(
          prayer: p,
          isPraying: _prayedIds.contains(p.id),
          busy: _busyIds.contains(p.id),
          onTogglePray: () => _togglePray(p),
          onTap: () async {
            await context.pushNamed(
              'prayer_details',
              pathParameters: {'id': p.id},
              extra: p,
            );
            if (mounted) _bootstrap();
          },
          onAuthorTap: canViewAuthor
              ? () => context.pushNamed(
                    'user_profile',
                    pathParameters: {'userId': p.authorId},
                  )
              : null,
          onEdit: isMine ? () => _editPrayer(p) : null,
          onDelete: isMine ? () => _confirmDelete(p) : null,
        );
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
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
      color: selected ? AppColors.primaryBlue : context.palette.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.primaryBlue
                  : AppColors.divider,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color: selected ? AppColors.white : context.palette.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.onTap,
  });
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  label,
                  style: AppTextStyles.buttonText.copyWith(
                    fontSize: 15,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
