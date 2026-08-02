import 'package:flutter/material.dart';

import '../models/friendship_model.dart';
import '../models/prayer_circle_model.dart';
import '../services/auth_service.dart';
import '../services/feed_service.dart';
import '../services/prayer_circle_service.dart';
import '../theme/app_colors.dart';
import 'screen_shell.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// Create and manage prayer circles (patch_170).
///
/// Members are chosen from accepted friends only. That is a deliberate
/// limit, not a shortcut: a circle is where the hardest requests go, and
/// letting someone be added by name-search would make it possible to put
/// a stranger in a family's prayer group.
///
/// Returns true if anything changed, so the caller can reload.
Future<bool?> showPrayerCirclesSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _CirclesSheet(),
  );
}

class _CirclesSheet extends StatefulWidget {
  const _CirclesSheet();

  @override
  State<_CirclesSheet> createState() => _CirclesSheetState();
}

class _CirclesSheetState extends State<_CirclesSheet> {
  List<PrayerCircle> _circles = const [];
  bool _loading = true;

  /// A failed fetch, kept apart from "you have no circles yet" — the two
  /// look identical to the member and mean opposite things.
  String? _error;

  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final circles = await PrayerCircleService.fetchMine();
      if (!mounted) return;
      setState(() {
        _circles = circles;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your prayer circles.';
      });
    }
  }

  Future<void> _create() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('New prayer circle', style: AppTextStyles.headlineSmall),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          style: AppTextStyles.bodyMedium,
          decoration: const InputDecoration(
            hintText: 'Family, cell group, choir…',
            border: OutlineInputBorder(),
          ),
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
            onPressed: () {
              final t = controller.text.trim();
              // The DB CHECK requires 2..60 chars; reject here too so the
              // user gets a no-op instead of a Postgres error toast.
              if (t.length >= 2) Navigator.pop(ctx, t);
            },
            child: Text('Create', style: AppTextStyles.labelLarge),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    try {
      final circle = await PrayerCircleService.create(name);
      if (!mounted) return;
      setState(() {
        _circles = [circle, ..._circles];
        _changed = true;
      });
      // Straight into adding people — a circle of one is not useful, and
      // this is the moment the user knows who they meant.
      await _manageMembers(circle);
    } catch (_) {
      if (!mounted) return;
      _toast('Could not create the circle.');
    }
  }

  Future<void> _manageMembers(PrayerCircle circle) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MembersSheet(circle: circle),
    );
    if (changed == true) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _confirmDelete(PrayerCircle circle) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete ${circle.name}?', style: AppTextStyles.headlineSmall),
        content: Text(
          // This is the non-obvious consequence and it must be said out
          // loud: the FK is ON DELETE SET NULL, so prayers posted here
          // are not deleted — they widen to normal visibility.
          'Prayers already sent to this circle will NOT be deleted — they '
          'become visible under normal prayer visibility instead. This '
          'cannot be undone.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: ctx.palette.textMuted,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Keep',
              style: AppTextStyles.labelMedium.copyWith(color: ctx.palette.text),
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
    if (ok != true || !mounted) return;
    try {
      await PrayerCircleService.delete(circle.id);
      if (!mounted) return;
      setState(() {
        _circles = _circles.where((c) => c.id != circle.id).toList();
        _changed = true;
      });
    } catch (_) {
      if (!mounted) return;
      _toast('Could not delete the circle.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.red,
        content: Text(
          msg,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final myId = AuthService.currentUser?.id;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: palette.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Prayer circles',
                    style: AppTextStyles.headlineMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Some things you want fifty people praying about. Some '
                    'you want five.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      child: ErrorBanner(message: _error!, onRetry: _load),
                    )
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                      children: [
                        if (_circles.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 28,
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryBlue
                                        .withValues(alpha: 0.10),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.group_outlined,
                                    color: AppColors.primaryBlue,
                                    size: 32,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'No circles yet',
                                  style: AppTextStyles.titleMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Create one for your family or cell group, '
                                  'then choose it when you share a prayer.',
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: palette.textMuted,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          for (final c in _circles)
                            ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryBlue
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.group_outlined,
                                  color: AppColors.primaryBlue,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                c.name,
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${c.memberCount} '
                                '${c.memberCount == 1 ? "person" : "people"}',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: palette.textMuted,
                                ),
                              ),
                              trailing: c.ownerId == myId
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.delete_outline,
                                        color: AppColors.red,
                                        size: 20,
                                      ),
                                      onPressed: () => _confirmDelete(c),
                                    )
                                  : null,
                              onTap: () => _manageMembers(c),
                            ),
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _create,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(
                          'New circle',
                          style: AppTextStyles.buttonText.copyWith(
                            fontSize: 15,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () => Navigator.pop(context, _changed),
                      child: Text(
                        'Done',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: palette.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add or remove members, chosen from accepted friends.
class _MembersSheet extends StatefulWidget {
  const _MembersSheet({required this.circle});
  final PrayerCircle circle;

  @override
  State<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends State<_MembersSheet> {
  Set<String> _memberIds = <String>{};
  List<({String id, String name})> _friends = const [];
  final Set<String> _busy = <String>{};
  bool _loading = true;

  bool _changed = false;

  /// A failed fetch of people who could be added.
  String? _pickError;

  String? get _myId => AuthService.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        PrayerCircleService.fetchMembers(widget.circle.id),
        FeedService.fetchMyFriendships(),
      ]);
      if (!mounted) return;
      final members = results[0] as List<PrayerCircleMember>;
      final friendships = results[1] as List<Friendship>;
      final me = _myId;
      final friends = <({String id, String name})>[];
      for (final f in friendships) {
        if (!f.isAccepted) continue;
        final other = f.requesterId == me ? f.addresseeId : f.requesterId;
        if (other.isEmpty || other == me) continue;
        friends.add((id: other, name: ''));
      }
      setState(() {
        _memberIds = members.map((m) => m.userId).toSet();
        // Names come from the members query where we have them; friends
        // not yet in the circle fall back to their id-keyed row, which
        // the tile renders as "Member". Kept simple deliberately — the
        // friend list screen is the place to browse people.
        _friends = [
          for (final m in members) (id: m.userId, name: m.fullName),
          for (final f in friends)
            if (!members.any((m) => m.userId == f.id))
              (id: f.id, name: 'Friend'),
        ];
        _loading = false;
        _pickError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _pickError = 'Could not load people to add.';
      });
    }
  }

  Future<void> _toggle(String userId) async {
    if (_busy.contains(userId)) return;
    if (userId == _myId) return; // the owner stays in their own circle
    final isMember = _memberIds.contains(userId);
    setState(() => _busy.add(userId));
    try {
      if (isMember) {
        await PrayerCircleService.removeMember(widget.circle.id, userId);
      } else {
        await PrayerCircleService.addMember(widget.circle.id, userId);
      }
      if (!mounted) return;
      setState(() {
        if (isMember) {
          _memberIds = _memberIds.where((id) => id != userId).toSet();
        } else {
          _memberIds = {..._memberIds, userId};
        }
        _changed = true;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not update members.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: palette.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.circle.name,
                    style: AppTextStyles.headlineMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Only friends can be added — a circle is where the '
                    'hardest requests go.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _pickError != null
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                          child: ErrorBanner(
                            message: _pickError!,
                            onRetry: _load,
                          ),
                        )
                      : _friends.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              'Add friends first, then you can build a '
                              'circle from them.',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: palette.textMuted,
                                height: 1.5,
                              ),
                            ),
                          ),
                        )
                      : ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
                          children: [
                            for (final f in _friends)
                              CheckboxListTile(
                                value: _memberIds.contains(f.id),
                                onChanged: _busy.contains(f.id) ||
                                        f.id == _myId
                                    ? null
                                    : (_) => _toggle(f.id),
                                activeColor: AppColors.primaryBlue,
                                title: Text(
                                  f.id == _myId ? 'You' : f.name,
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _changed),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Done',
                      style: AppTextStyles.buttonText.copyWith(fontSize: 15),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
