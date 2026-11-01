import 'package:flutter/material.dart';

import '../../services/e2ee/chat_backup_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';

/// Settings → Chat backup (1 Nov 2026).
///
/// End-to-end encrypted chats can't be read on a new phone without this:
/// the keys that opened them stayed on the old one. The member picks a
/// password; the phone seals its readable history with it and keeps a copy
/// on our servers that only that password opens.
class ChatBackupScreen extends StatefulWidget {
  const ChatBackupScreen({super.key});

  @override
  State<ChatBackupScreen> createState() => _ChatBackupScreenState();
}

class _ChatBackupScreenState extends State<ChatBackupScreen> {
  bool _loading = true;
  bool _enabled = false;
  bool _hasRemote = false;
  bool _working = false;
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      ChatBackupService.isEnabled(),
      ChatBackupService.hasRemoteBackup(),
    ]);
    if (!mounted) return;
    setState(() {
      _enabled = results[0];
      _hasRemote = results[1];
      _loading = false;
    });
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _turnOn() async {
    final a = _pw.text, b = _pw2.text;
    if (a.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (a != b) {
      setState(() => _error = "The two passwords don't match.");
      return;
    }
    setState(() {
      _error = null;
      _working = true;
    });
    try {
      await ChatBackupService.enable(a);
      _pw.clear();
      _pw2.clear();
      if (!mounted) return;
      setState(() {
        _enabled = true;
        _hasRemote = true;
      });
      _toast('Backup is on. Your chats are backed up.');
    } catch (_) {
      if (mounted) _toast("Couldn't back up. Check your connection.");
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restore() async {
    if (_pw.text.isEmpty) {
      setState(() => _error = 'Enter your backup password.');
      return;
    }
    setState(() {
      _error = null;
      _working = true;
    });
    try {
      final n = await ChatBackupService.restore(_pw.text);
      _pw.clear();
      if (!mounted) return;
      setState(() => _enabled = true);
      _toast(
        n == 0
            ? 'Restored. Nothing new was missing on this phone.'
            : 'Restored $n messages and chat lines.',
      );
    } on BackupPasswordException {
      if (mounted) {
        setState(() => _error = "That password doesn't open this backup.");
      }
    } catch (_) {
      if (mounted) _toast("Couldn't restore. Check your connection.");
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _backupNow() async {
    setState(() => _working = true);
    try {
      await ChatBackupService.backupNow();
      if (mounted) _toast('Backed up.');
    } catch (_) {
      if (mounted) _toast("Couldn't back up. Check your connection.");
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _turnOff() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off chat backup?'),
        content: const Text(
          'Your backup is deleted from our servers. If you change phone, '
          'messages from before will show "Waiting for this message".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ChatBackupService.disable();
    if (mounted) {
      setState(() {
        _enabled = false;
        _hasRemote = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const ScreenHero(
              title: 'Chat backup',
              tagline: 'End-to-end encrypted',
              fallbackRoute: 'settings',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _card(
                          context,
                          icon: Icons.lock_outline_rounded,
                          title: 'Only your password opens it',
                          body:
                              'Your chats are end-to-end encrypted, so a new '
                              'phone can\'t read old messages on its own. A '
                              'backup keeps a copy sealed with a password you '
                              'choose. We never see it — if you forget it, '
                              'nobody can open the backup, not even us.',
                        ),
                        const SizedBox(height: 14),
                        if (_enabled)
                          ..._enabledView(palette)
                        else if (_hasRemote)
                          ..._restoreView(palette)
                        else
                          ..._setupView(palette),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _setupView(AppPalette palette) => [
    _field(_pw, 'Backup password (8+ characters)'),
    const SizedBox(height: 10),
    _field(_pw2, 'Type it again'),
    if (_error != null) _errorText(),
    const SizedBox(height: 16),
    PrimaryGradientButton(
      label: 'Turn on backup',
      icon: Icons.cloud_upload_outlined,
      busy: _working,
      onTap: _working ? null : _turnOn,
    ),
    const SizedBox(height: 10),
    Text(
      'Write the password down somewhere safe. Backups then run '
      'automatically once a day.',
      textAlign: TextAlign.center,
      style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
    ),
  ];

  List<Widget> _restoreView(AppPalette palette) => [
    _card(
      context,
      icon: Icons.history_rounded,
      title: 'A backup is waiting',
      body:
          'Enter the password you chose on your old phone to bring your '
          'messages back.',
    ),
    const SizedBox(height: 14),
    _field(_pw, 'Backup password'),
    if (_error != null) _errorText(),
    const SizedBox(height: 16),
    PrimaryGradientButton(
      label: 'Restore my chats',
      icon: Icons.restore_rounded,
      busy: _working,
      onTap: _working ? null : _restore,
    ),
    const SizedBox(height: 8),
    TextButton(
      onPressed: _working ? null : () => setState(() => _hasRemote = false),
      child: const Text('Forgot it? Start a new backup instead'),
    ),
  ];

  List<Widget> _enabledView(AppPalette palette) {
    final last = ChatBackupService.lastBackup?.toLocal();
    final when = last == null
        ? 'Not yet'
        : '${last.day}/${last.month}/${last.year} at '
              '${last.hour.toString().padLeft(2, '0')}:'
              '${last.minute.toString().padLeft(2, '0')}';
    return [
      _card(
        context,
        icon: Icons.cloud_done_outlined,
        title: 'Backup is on',
        body: 'Last backup: $when. It runs by itself once a day.',
      ),
      const SizedBox(height: 16),
      PrimaryGradientButton(
        label: 'Back up now',
        icon: Icons.cloud_upload_outlined,
        busy: _working,
        onTap: _working ? null : _backupNow,
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _working ? null : _turnOff,
        child: Text(
          'Turn off and delete backup',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.red),
        ),
      ),
    ];
  }

  Widget _errorText() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      _error!,
      style: AppTextStyles.bodySmall.copyWith(color: AppColors.red),
    ),
  );

  Widget _field(TextEditingController c, String hint) => TextField(
    controller: c,
    obscureText: true,
    enableSuggestions: false,
    autocorrect: false,
    decoration: InputDecoration(hintText: hint),
  );

  Widget _card(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primaryBlue, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.textMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
