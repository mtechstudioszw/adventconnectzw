import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/presence_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/brand_spinner.dart';

/// WhatsApp-style privacy controls dedicated to the chat surface.
/// Persists three flags on profiles:
///   - show_last_seen
///   - show_online_status
///   - show_read_receipts
class ChatPrivacyScreen extends StatefulWidget {
  const ChatPrivacyScreen({super.key});

  @override
  State<ChatPrivacyScreen> createState() => _ChatPrivacyScreenState();
}

class _ChatPrivacyScreenState extends State<ChatPrivacyScreen> {
  final _client = Supabase.instance.client;
  bool _loading = true;
  bool _saving = false;
  bool _showLastSeen = true;
  bool _showOnlineStatus = true;
  bool _showReadReceipts = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final row = await _client
          .from('profiles')
          .select('show_last_seen, show_online_status, show_read_receipts')
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _showLastSeen = row?['show_last_seen'] != false;
        _showOnlineStatus = row?['show_online_status'] != false;
        _showReadReceipts = row?['show_read_receipts'] != false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your privacy settings.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final user = _client.auth.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      await _client
          .from('profiles')
          .update({
            'show_last_seen': _showLastSeen,
            'show_online_status': _showOnlineStatus,
            'show_read_receipts': _showReadReceipts,
          })
          .eq('id', user.id);
      // PresenceService caches its broadcast state in _isTracked —
      // flipping the DB column doesn't retroactively untrack the
      // existing presence channel. Tell PresenceService to reconcile
      // so OTHER clients see the user vanish (or reappear) within a
      // tick of saving here.
      unawaited(PresenceService.refreshVisibility());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Privacy settings saved.',
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
            'Could not save. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      appBar: AppBar(
        title: const Text('Chat privacy'),
        backgroundColor: AppColors.darkNavy,
        foregroundColor: AppColors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.goNamed('settings'),
        ),
      ),
      body: _loading
          ? const Center(child: BrandSpinner(size: 30))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.red,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                _section(
                  title: 'Last seen',
                  subtitle:
                      'When off, other people won\'t see when you last opened the app.',
                  value: _showLastSeen,
                  onChanged: (v) => setState(() => _showLastSeen = v),
                ),
                const SizedBox(height: 12),
                _section(
                  title: 'Online status',
                  subtitle:
                      'When off, no green "Online" dot is shown next to your name in chats.',
                  value: _showOnlineStatus,
                  onChanged: (v) => setState(() => _showOnlineStatus = v),
                ),
                const SizedBox(height: 12),
                _section(
                  title: 'Read receipts',
                  subtitle:
                      'When off, blue double-ticks won\'t be sent. You won\'t see read receipts from others either.',
                  value: _showReadReceipts,
                  onChanged: (v) => setState(() => _showReadReceipts = v),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: AppColors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: AppColors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text('Save changes'),
                ),
              ],
            ),
    );
  }

  Widget _section({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: context.palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            activeThumbColor: AppColors.primaryBlue,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
