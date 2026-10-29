import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/follow_service.dart';
import '../../services/presence_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/profile/who_can_follow_change.dart';
import '../../widgets/screen_shell.dart';

/// Privacy: who can follow you and message you, and what people
/// can see (28 Oct 2026 — owner: "combine it with who can message me").
///
/// Was "Chat privacy". "Who can follow me" (patch_282) joined it so the
/// reach-me settings sit together — but they stay SEPARATE settings:
/// following someone never lets them message you. The friends-vs-followers
/// card at the top states the difference, because the owner's rule is that
/// on personal accounts the two must never blur.
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
  const ChatPrivacyScreen({
    super.key,
    this.autoLoad = true,
    this.initialWhoCanFollow,
  });

  /// Test seam — `initState` reads the member's profile from Supabase.
  /// Same convention as `SearchScreen.autoLoad`.
  final bool autoLoad;

  /// Test seam with [autoLoad] off: shows the follow section as if
  /// patch_282 had answered with this value.
  final WhoCanFollow? initialWhoCanFollow;

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

  /// Null until patch_282's column answers; the section stays hidden.
  WhoCanFollow? _whoCanFollow;
  bool _whoBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _load();
    } else {
      _loading = false;
      _whoCanFollow = widget.initialWhoCanFollow;
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
            'who_can_message',
          )
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _showLastSeen = row?['show_last_seen'] != false;
        _showOnlineStatus = row?['show_online_status'] != false;
        _showReadReceipts = row?['show_read_receipts'] != false;
        _whoCanMessage = (row?['who_can_message'] as String?) ?? 'everyone';
        _loading = false;
      });
      final who = await FollowService.myWhoCanFollow();
      if (mounted && who != null) setState(() => _whoCanFollow = who);
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

  Future<void> _setWhoCanFollow(WhoCanFollow v) async {
    final current = _whoCanFollow;
    if (current == null || v == current || _whoBusy) return;
    setState(() => _whoBusy = true);
    final now = await changeWhoCanFollow(context, current: current, picked: v);
    if (!mounted) return;
    setState(() {
      _whoCanFollow = now;
      _whoBusy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const ScreenHero(
            title: 'Privacy',
            tagline: 'Privacy',
            subtitle: 'Who can follow you and message you.',
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
        const _FriendsVsFollowers(),
        const SizedBox(height: 20),
        if (_whoCanFollow != null) ...[
          _SectionLabel('Who can follow me'),
          const SizedBox(height: 8),
          ScreenCard(
            key: const ValueKey('who-can-follow-card'),
            child: AbsorbPointer(
              absorbing: _whoBusy,
              child: Column(
                children: [
                  for (final w in WhoCanFollow.values) ...[
                    if (w != WhoCanFollow.values.first) const _RowDivider(),
                    _ChoiceRow(
                      title: w.label,
                      subtitle: w == WhoCanFollow.everyone
                          ? '${w.description} This is the default.'
                          : w.description,
                      value: w.wire,
                      group: _whoCanFollow!.wire,
                      onSelect: (v) =>
                          _setWhoCanFollow(WhoCanFollowX.fromWire(v)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        _SectionLabel('Who can message me'),
        const SizedBox(height: 8),
        ScreenCard(
          key: const ValueKey('who-can-message-card'),
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
              'Applies everywhere — your profile and every chat, not just the '
              'one you opened this from.',
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

/// The difference between a friend and a follower, stated where people
/// choose who may do what. Owner's rule (28 Oct 2026): on personal accounts
/// the two must stay clearly different.
class _FriendsVsFollowers extends StatelessWidget {
  const _FriendsVsFollowers();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget column(IconData icon, String title, List<String> lines) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: palette.brandBlue),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $l',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.textMuted,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
    return ScreenCard(
      key: const ValueKey('friends-vs-followers'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          column(Icons.people_alt_outlined, 'Friends', const [
            'Both of you agree',
            'See your friends-only posts',
            'Can message you, if your setting below allows',
          ]),
          const SizedBox(width: 12),
          column(Icons.person_add_alt_outlined, 'Followers', const [
            // Said plainly (owner, 29 Oct 2026): "don't have to follow
            // back" read as "can't follow back". You can — it's one tap.
            'One-way — you can follow back, but it\'s your choice',
            'See your public posts only',
            'Following never lets them message you',
          ]),
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

/// One of a set of mutually exclusive options — used by the "Who can
/// follow me" and "Who can message me" sections.
///
/// "Who can call me" was removed 29 Oct 2026 (owner: "we have no calls").
/// The app has no calling feature, so the setting controlled nothing. The
/// `who_can_call` column is left in place, unread.
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
