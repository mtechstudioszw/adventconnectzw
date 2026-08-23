import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;
import '../../models/prayer_model.dart';
import '../../services/prayer_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/prayer_card.dart';
import '../widgets/main_scaffold.dart';
import '../widgets/post_form_widgets.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/content_reveal.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/shimmer_loaders.dart';

class PrayerScreen extends StatefulWidget {
  const PrayerScreen({super.key});

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen> {
  List<Prayer> _prayers = [];
  Set<String> _prayedIds = <String>{};
  Set<String> _busyIds = <String>{};
  bool _loading = true;

  /// Non-null when the last load failed. Kept separate from "the list is
  /// empty" so the two can render differently.
  String? _loadError;

  /// null = "All" chip. Otherwise a PrayerCategory whose .code is
  /// passed to fetchPrayers() to narrow the server-side query.
  PrayerCategory? _activeCategory;

  /// The "Answered" chip. Orthogonal to [_activeCategory] rather than one
  /// of its values — a prayer has exactly one category and may also be
  /// answered, so selecting Answered clears the category and vice versa
  /// only because the chip row is single-select, not because the DB
  /// couldn't express both.
  bool _answeredOnly = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        PrayerService.fetchPrayers(
          category: _activeCategory?.code,
          answeredOnly: _answeredOnly,
        ),
        PrayerService.fetchUserPrayedIds(),
      ]);
      if (!mounted) return;
      final prayers = results[0] as List<Prayer>;
      setState(() {
        _prayers = prayers;
        _prayedIds = results[1] as Set<String>;
        _loading = false;
      });
      // Names for the "Rutendo, Blessing and 41 others prayed" line.
      // Deliberately after the first paint: the list is useful without
      // it, and one extra round-trip shouldn't delay the whole screen.
      _loadPrayedBy(prayers);
    } catch (e) {
      if (!mounted) return;
      // Previously this swallowed the error and fell through to the
      // "Be the first to share" empty state — so a dropped connection,
      // an expired session or an RLS rejection all looked identical to
      // "nobody has posted a prayer". Surface it instead: an empty list
      // and a failed load are different things and need different
      // reactions from the user.
      setState(() {
        _loading = false;
        _loadError = _describeLoadError(e);
      });
    }
  }

  /// Turn an exception into something a member can act on. Auth and
  /// connectivity are the two that actually happen and each has a
  /// different remedy, so they get their own wording.
  String _describeLoadError(Object e) {
    if (e is AuthException) return 'Sign in again to see prayers.';
    if (e is PostgrestException) {
      return 'Prayers could not be loaded (${e.code ?? 'server error'}).';
    }
    return 'Could not load prayers. Check your connection and try again.';
  }

  Future<void> _loadPrayedBy(List<Prayer> prayers) async {
    final ids = prayers
        .where((p) => p.prayerCount > 0)
        .map((p) => p.id)
        .toList(growable: false);
    if (ids.isEmpty) return;
    final grouped = await PrayerService.fetchPrayedByPreview(ids);
    if (!mounted || grouped.isEmpty) return;
    setState(() {
      _prayers = _prayers.map((p) {
        final names = grouped[p.id];
        return names == null ? p : p.copyWith(prayedBy: names);
      }).toList();
    });
  }

  Future<void> _selectCategory(PrayerCategory? next) async {
    if (next == _activeCategory && !_answeredOnly) return;
    setState(() {
      _activeCategory = next;
      _answeredOnly = false;
    });
    await _bootstrap();
  }

  Future<void> _selectAnswered() async {
    if (_answeredOnly) return;
    setState(() {
      _answeredOnly = true;
      _activeCategory = null;
    });
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
            .map(
              (p) => p.id == prayer.id ? p.copyWith(prayerCount: newCount) : p,
            )
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
          () => _busyIds = _busyIds.where((id) => id != prayer.id).toSet(),
        );
      }
    }
  }

  /// Mark answered (with an optional testimony) or un-answer. Author-only
  /// — the card passes null for anyone else, so the menu item is absent.
  Future<void> _toggleAnswered(Prayer prayer) async {
    if (prayer.isAnswered) {
      await _writeAnswered(prayer, answered: false, testimony: null);
      return;
    }
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Mark as answered', style: AppTextStyles.headlineSmall),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Everyone who prayed will see this. Sharing what happened is '
              'optional — you can mark it answered on its own.',
              style: AppTextStyles.bodySmall.copyWith(
                color: ctx.palette.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              style: AppTextStyles.bodyMedium,
              decoration: const InputDecoration(
                hintText: 'What happened? (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: AppTextStyles.labelMedium.copyWith(color: ctx.palette.text),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.successGreen,
            ),
            child: Text('Mark answered', style: AppTextStyles.labelLarge),
          ),
        ],
      ),
    );
    controller.dispose();
    // Distinguish "dismissed" (null) from "confirmed with no testimony"
    // (empty string) — only the second should write.
    if (result == null) return;
    await _writeAnswered(
      prayer,
      answered: true,
      testimony: result.isEmpty ? null : result,
    );
  }

  Future<void> _writeAnswered(
    Prayer prayer, {
    required bool answered,
    required String? testimony,
  }) async {
    try {
      await PrayerService.setAnswered(
        prayer.id,
        answered: answered,
        testimony: testimony,
      );
      if (!mounted) return;
      setState(() {
        if (_answeredOnly && !answered) {
          // It no longer belongs in this filtered list.
          _prayers = _prayers.where((p) => p.id != prayer.id).toList();
          return;
        }
        _prayers = _prayers
            .map((p) => p.id == prayer.id
                ? p.copyWith(
                    isAnswered: answered,
                    // Mirror the trigger's stamp locally so the card can
                    // render "Answered just now" without a refetch.
                    answeredAt: answered ? DateTime.now() : null,
                    testimony: testimony,
                  )
                : p)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            answered ? 'Marked as answered. 🙏' : 'Moved back to open prayers.',
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
            'Could not update. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
              style: AppTextStyles.labelMedium.copyWith(
                color: context.palette.text,
              ),
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
      setState(
        () => _prayers = _prayers.where((p) => p.id != prayer.id).toList(),
      );
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
            child: Text(
              'Cancel',
              style: AppTextStyles.labelMedium.copyWith(
                color: context.palette.text,
              ),
            ),
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
          content: Text(
            'Prayer updated.',
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
            'Could not update. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
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
      // Prayer is PUSHED (from Home's Prayer action and from Profile's My
      // prayers), not a tab — so it hides the island and shows the AppBar
      // back button, the same way Events does.
      //
      // It used to pass `currentIndex: 4`, which lit the Profile pill while
      // the member was on Prayer: the bar said "you are in Profile" and
      // tapping that pill did nothing. Highlighting a tab you are not on is
      // worse than highlighting none, and an island with nothing active is
      // itself a tab bar that doesn't work — which is the false affordance
      // the founder reported (2 Aug 2026).
      currentIndex: 0,
      showNav: false,
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
              // Entrance now happens per-card (StaggeredReveal below).
              child: _buildList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    return Container(
      // Transparent: this rail sits immediately under ScreenHero, which is
      // now transparent too. Leaving it opaque just moved the hard edge of
      // the ambient field down by one row instead of removing it.
      color: Colors.transparent,
      child: SizedBox(
        height: 50,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          children: [
            _CategoryChip(
              label: 'All',
              selected: _activeCategory == null && !_answeredOnly,
              onTap: () => _selectCategory(null),
            ),
            const SizedBox(width: 8),
            // Answered sits second, right after All — it is the reason to
            // come back to this screen, so it should not be the last chip
            // off the right edge.
            _CategoryChip(
              label: 'Answered',
              selected: _answeredOnly,
              tint: AppColors.successGreen,
              icon: Icons.auto_awesome,
              onTap: _selectAnswered,
            ),
            for (final c in PrayerCategory.values) ...[
              const SizedBox(width: 8),
              _CategoryChip(
                label: c.label,
                selected: _activeCategory == c && !_answeredOnly,
                onTap: () => _selectCategory(c),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return ContentReveal(
      loading: _loading && _prayers.isEmpty,
      skeleton: ShimmerLoaders.cardList(count: 6),
      child: _buildListContent(),
    );
  }

  Widget _buildListContent() {
    // A failed load is NOT an empty list. Showing "Be the first to share"
    // when the request actually errored tells the user the community has
    // posted nothing, which is both wrong and unfixable from their side.
    final error = _loadError;
    if (error != null && _prayers.isEmpty) {
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
                    color: AppColors.red.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cloud_off_outlined,
                    color: AppColors.red,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Prayers didn\'t load',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: context.palette.textMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                _GradientButton(label: 'Try again', onTap: _bootstrap),
              ],
            ),
          ),
        ],
      );
    }
    if (_prayers.isEmpty) {
      // "No prayers exist" and "no prayers match the chip you just
      // tapped" are different situations and need different words. They
      // used to share one screen that said "Be the first to share", so
      // tapping Healing on a board whose prayers are all filed under
      // Other looked exactly like an empty, broken Prayer tab — with a
      // button inviting you to post something you'd already posted.
      final filtered = _activeCategory != null || _answeredOnly;
      final filterName =
          _answeredOnly ? 'answered' : (_activeCategory?.label.toLowerCase() ?? '');
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
                  child: Icon(
                    filtered
                        ? Icons.filter_alt_off_outlined
                        : Icons.volunteer_activism_outlined,
                    color: AppColors.primaryBlue,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  filtered
                      ? 'Nothing under $filterName yet'
                      : 'Be the first to share',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  filtered
                      ? 'There are prayers on the board — just none in this '
                          'filter. Clear it to see them all.'
                      : 'Share a prayer request and pray together with the SDA community worldwide.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: context.palette.textMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                if (filtered)
                  _GradientButton(
                    label: 'Show all prayers',
                    onTap: () {
                      setState(() {
                        _activeCategory = null;
                        _answeredOnly = false;
                      });
                      _bootstrap();
                    },
                  )
                else
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
        final card = PrayerCard(
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
          onToggleAnswered: isMine ? () => _toggleAnswered(p) : null,
        );
        if (i >= 8) return card;
        return StaggeredReveal(index: i, rise: 18, child: card);
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.tint,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Overrides the selected fill. Only "Answered" uses it — green, so the
  /// chip matches the rail on the cards it filters to.
  final Color? tint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final accent = tint ?? AppColors.primaryBlue;
    return PressEffect(
      child: Material(
        color: selected ? accent : context.palette.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? accent : AppColors.divider,
              ),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 13,
                    color: selected ? AppColors.white : accent,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: selected ? AppColors.white : context.palette.text,
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

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressEffect(
      child: Opacity(
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
      ),
    );
  }
}
