import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/presence_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/screen_shell.dart';

/// Who sees you in chat, and who may reach you.
///
/// Persists four columns on `profiles`: `show_last_seen`,
/// `show_online_status`, `show_read_receipts` and `who_can_message`.
///
/// **No Save button.** It used to collect all four and write them on a
/// tap, which meant a member could flip "Online status" off, walk away,
/// and still be broadcasting. Each control now writes on change and rolls
/// itself back if the write fails — the same optimistic pattern as
/// `settings_screen.dart`.
class ChatPrivacyScreen extends StatefulWidget {
  const ChatPrivacyScreen({super.key, this.autoLoad = true});

  /// Test seam — `initState` reads the member's profile from Supabase.
  /// Same convention as `SearchScreen.autoLoad`.
  final bool autoLoad;

  @override
  State<ChatPrivacyScreen> createState() => _ChatPrivacyScreenState();
}

class _ChatPrivacyScreenState extends State<ChatPrivacyScreen> {
  // A getter, not a field. A field initializer runs when the State is
  // constructed — before `autoLoad` is ever consulted — so it reached for
  // Supabase.instance during the widget test and asserted. Resolving it
  // lazily means a screen that never talks to the server never asks for a
  // client.
  SupabaseClient get _client => Supabase.instance.client;
  bool _loading = true;
  bool _showLastSeen = true;
  bool _showOnlineStatus = true;
  bool _showReadReceipts = true;
  String _whoCanMessage = 'everyone';
  // Defaults to 'friends', matching the column default in patch_265.
  // A ringing phone is a far louder interruption than an unread badge,
  // so calling starts tighter than messaging and the member opens it up
  // rather than having to discover they need to close it down.
  String _whoCanCall = 'friends';
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _load();
    } else {
      _loading = false;
    }
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
          .select(
            'show_last_seen, show_online_status, show_read_receipts, '
            'who_can_message, who_can_call',
          )
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _showLastSeen = row?['show_last_seen'] != false;
        _showOnlineStatus = row?['show_online_status'] != false;
        _showReadReceipts = row?['show_read_receipts'] != false;
        _whoCanMessage = (row?['who_can_message'] as String?) ?? 'everyone';
        _whoCanCall = (row?['who_can_call'] as String?) ?? 'friends';
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

  /// Writes one column, having already painted the change.
  ///
  /// [revert] puts the old value back if the write fails, so the switch
  /// never sits in a state the server disagrees with. There is no spinner:
  /// the toggle IS the feedback, and a 200ms wait on a switch reads as lag.
  Future<void> _persist(
    String column,
    Object? value, {
    required VoidCallback revert,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client.from('profiles').update({column: value}).eq('id', user.id);
      // PresenceService caches its broadcast state in _isTracked — flipping
      // the DB column doesn't retroactively untrack the existing presence
      // channel. Tell it to reconcile so OTHER clients see the member
      // vanish (or reappear) within a tick.
      unawaited(PresenceService.refreshVisibility());
    } catch (_) {
      if (!mounted) return;
      setState(revert);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not save that. Check your connection.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  void _setLastSeen(bool v) {
    final was = _showLastSeen;
    setState(() => _showLastSeen = v);
    _persist(
      'show_last_seen',
      v,
      revert: () => _showLastSeen = was,
    );
  }

  void _setOnlineStatus(bool v) {
    final was = _showOnlineStatus;
    setState(() => _showOnlineStatus = v);
    _persist(
      'show_online_status',
      v,
      revert: () => _showOnlineStatus = was,
    );
  }

  void _setReadReceipts(bool v) {
    final was = _showReadReceipts;
    setState(() => _showReadReceipts = v);
    _persist(
      'show_read_receipts',
      v,
      revert: () => _showReadReceipts = was,
    );
  }

  void _setWhoCanMessage(String v) {
    if (v == _whoCanMessage) return;
    final was = _whoCanMessage;
    setState(() => _whoCanMessage = v);
    _persist(
      'who_can_message',
      v,
      revert: () => _whoCanMessage = was,
    );
  }

  void _setWhoCanCall(String v) {
    if (v == _whoCanCall) return;
    final was = _whoCanCall;
    setState(() => _whoCanCall = v);
    _persist(
      'who_can_call',
      v,
      revert: () => _whoCanCall = was,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const ScreenHero(
            title: 'Chat privacy',
            tagline: 'Chat',
            subtitle: 'Who sees you, and who can reach you — in every chat.',
            fallbackRoute: 'settings',
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: BrandSpinner(size: 30));
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.red),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const _ScopeNote(),
        const SizedBox(height: 16),
        _SectionLabel('Who can message me'),
        const SizedBox(height: 8),
        ScreenCard(
          child: Column(
            children: [
              _ChoiceRow(
                title: 'Everyone',
                // The one-message gate is the whole point of the setting,
                // so it is stated on the option rather than buried in a
                // footnote — a member choosing this should know exactly
                // how much a stranger can say.
                subtitle: 'A stranger can send one message. Once you accept '
                    'their friend request, they can chat normally.',
                value: 'everyone',
                group: _whoCanMessage,
                onSelect: _setWhoCanMessage,
              ),
              const _RowDivider(),
              _ChoiceRow(
                title: 'Friends only',
                subtitle:
                    'Only people whose friend request you have accepted can '
                    'message you.',
                value: 'friends',
                group: _whoCanMessage,
                onSelect: _setWhoCanMessage,
              ),
              const _RowDivider(),
              _ChoiceRow(
                title: 'Nobody',
                subtitle: 'No one can start a new chat with you. '
                    'Conversations you are already in keep working.',
                value: 'nobody',
                group: _whoCanMessage,
                onSelect: _setWhoCanMessage,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionLabel('Who can call me'),
        const SizedBox(height: 8),
        ScreenCard(
          child: Column(
            children: [
              _ChoiceRow(
                title: 'Everyone',
                subtitle:
                    'Anyone on Adventist Super App can ring you, including '
                    'people you have never spoken to.',
                value: 'everyone',
                group: _whoCanCall,
                onSelect: _setWhoCanCall,
              ),
              const _RowDivider(),
              _ChoiceRow(
                title: 'Friends only',
                // Named as the default so nobody has to guess which one
                // they are on before they have touched the screen.
                subtitle:
                    'Only people whose friend request you have accepted can '
                    'call you. This is the default.',
                value: 'friends',
                group: _whoCanCall,
                onSelect: _setWhoCanCall,
              ),
              const _RowDivider(),
              _ChoiceRow(
                title: 'Nobody',
                subtitle:
                    'No one can call you. You can still call other people, '
                    'and messaging is unaffected.',
                value: 'nobody',
                group: _whoCanCall,
                onSelect: _setWhoCanCall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionLabel('What people can see'),
        const SizedBox(height: 8),
        ScreenCard(
          child: Column(
            children: [
              _ToggleRow(
                title: 'Last seen',
                subtitle: 'When off, other people won\'t see when you last '
                    'opened the app.',
                value: _showLastSeen,
                onChanged: _setLastSeen,
              ),
              const _RowDivider(),
              _ToggleRow(
                title: 'Online status',
                subtitle: 'When off, no green "Online" dot is shown next to '
                    'your name in chats.',
                value: _showOnlineStatus,
                onChanged: _setOnlineStatus,
              ),
              const _RowDivider(),
              _ToggleRow(
                title: 'Read receipts',
                subtitle: 'When off, blue double-ticks won\'t be sent. You '
                    'won\'t see read receipts from others either.',
                value: _showReadReceipts,
                onChanged: _setReadReceipts,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// States plainly that nothing on this screen is per-conversation.
///
/// Every setting here is a column on `profiles`, so it applies to every
/// chat at once — but the screen is most often reached from *inside* one
/// conversation, where "Chat privacy" reads as "privacy for this chat".
/// A member turning read receipts off from Alice's thread to avoid Alice
/// would otherwise turn them off for everyone and never know. The scope
/// has to be on the screen, not only in the docs.
class _ScopeNote extends StatelessWidget {
  const _ScopeNote();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.chipBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.public, size: 16, color: palette.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              // Kept to one line's worth of meaning. This screen already
              // carries the most wrappable text in the app and is swept at
              // 2.5x text scale; a paragraph here pushes the first real
              // control off a 360dp phone.
              'Applies to every chat, not just the one you opened this from.',
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.textMuted,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ),
        ],
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
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: context.palette.textMuted,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 20, color: context.palette.divider);
}

/// One of the mutually exclusive "who can message me" options.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.group,
    required this.onSelect,
  });

  final String title;
  final String subtitle;
  final String value;
  final String group;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = value == group;
    final palette = context.palette;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () => onSelect(value),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        // The whole row is the target, not just the radio — a 20dp circle
        // is a miss waiting to happen next to three lines of text.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? AppColors.primaryBlue : palette.textMuted,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.titleMedium.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.textMuted,
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
    );
  }
}
