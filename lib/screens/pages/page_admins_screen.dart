import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/org_page_model.dart';
import '../../services/auth_service.dart';
import '../../services/page_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/user_avatar.dart';

/// A Page's admins (brief §9: "authorized managers"). Owners add people by
/// @username and remove them; editors can step down. The database refuses
/// anything else — including removing the last owner.
class PageAdminsScreen extends StatefulWidget {
  const PageAdminsScreen({
    super.key,
    required this.pageId,
    this.isOwner = false,
  });

  final String pageId;
  final bool isOwner;

  @override
  State<PageAdminsScreen> createState() => _PageAdminsScreenState();
}

class _PageAdminsScreenState extends State<PageAdminsScreen> {
  List<PageAdmin> _admins = const [];
  bool _loading = true;
  String? _error;

  String? get _me => AuthService.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final admins = await PageService.admins(widget.pageId);
      if (!mounted) return;
      setState(() {
        _admins = admins;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = PageService.messageFor(e) ?? 'Could not load the admins.';
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? AppColors.red : null,
        content: Text(msg),
      ),
    );
  }

  Future<void> _add() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => const _AddAdminDialog(),
    );
    if (result == null) return;
    try {
      await PageService.addAdmin(widget.pageId, result.$1, role: result.$2);
      _snack('Added @${result.$1.replaceFirst('@', '')}.');
      _load();
    } catch (e) {
      _snack(
        PageService.messageFor(e) ?? 'Could not add that person.',
        error: true,
      );
    }
  }

  Future<void> _remove(PageAdmin a) async {
    final self = a.userId == _me;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(self ? 'Step down as admin?' : 'Remove ${a.fullName}?'),
        content: Text(
          self
              ? 'You will no longer be able to post as or edit this Page.'
              : 'They will no longer be able to post as or edit this Page.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(self ? 'Step down' : 'Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PageService.removeAdmin(widget.pageId, a.userId);
      if (!mounted) return;
      if (self) {
        context.pop();
        return;
      }
      _load();
    } catch (e) {
      _snack(
        PageService.messageFor(e) ?? 'Could not remove that admin.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          ScreenHero(
            title: 'Page admins',
            tagline: 'PAGES',
            fallbackRoute: 'pages',
            trailing: widget.isOwner
                ? HeaderIconButton(
                    icon: Icons.person_add_alt_1_outlined,
                    tooltip: 'Add an admin',
                    onTap: _add,
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Owners can edit the Page, post as it and manage admins. '
              'Editors can edit the Page and post as it.',
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.textMuted,
                height: 1.4,
              ),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(child: BrandSpinner(size: 30)),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: EmptyStateCard(
                icon: Icons.admin_panel_settings_outlined,
                title: "Can't show admins",
                message: _error!,
              ),
            )
          else
            for (final a in _admins)
              ListTile(
                leading: UserAvatar(
                  photoUrl: a.photoUrl,
                  size: 44,
                  name: a.fullName,
                ),
                title: Text(
                  a.userId == _me ? '${a.fullName} (you)' : a.fullName,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  [
                    a.role == 'owner' ? 'Owner' : 'Editor',
                    if ((a.username ?? '').isNotEmpty) '@${a.username}',
                  ].join(' · '),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                trailing: (widget.isOwner || a.userId == _me)
                    ? TextButton(
                        onPressed: () => _remove(a),
                        child: Text(
                          a.userId == _me ? 'Step down' : 'Remove',
                          style: const TextStyle(color: AppColors.red),
                        ),
                      )
                    : null,
              ),
        ],
      ),
    );
  }
}

class _AddAdminDialog extends StatefulWidget {
  const _AddAdminDialog();

  @override
  State<_AddAdminDialog> createState() => _AddAdminDialogState();
}

class _AddAdminDialogState extends State<_AddAdminDialog> {
  final _username = TextEditingController();
  String _role = 'editor';

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add an admin'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _username,
            autofocus: true,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Their username',
              prefixText: '@',
              helperText: 'They need to have set a username on their profile.',
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'editor', label: Text('Editor')),
              ButtonSegment(value: 'owner', label: Text('Owner')),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final u = _username.text.trim().replaceFirst('@', '');
            if (u.isEmpty) return;
            Navigator.pop(context, (u, _role));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
