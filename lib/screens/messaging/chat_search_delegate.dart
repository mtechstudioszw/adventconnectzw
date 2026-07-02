import 'package:flutter/material.dart';

import '../../models/member_directory_model.dart';
import '../../models/message_model.dart';
import '../../models/story_model.dart';
import '../../services/directory_service.dart';
import '../../services/messaging_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/brand_spinner.dart';

/// WhatsApp-style scoped search for Advent Chat. One search field, a row of
/// scope chips (Friends · Messages · Groups · Archived · Status), and an
/// Explore scope that searches everyone on Advent (people who aren't your
/// friends yet). Reuses the inbox's already-loaded data so the in-your-world
/// scopes are instant; only Explore hits the network.
enum ChatSearchScope { friends, messages, groups, archived, status, explore }

class ChatSearchDelegate extends SearchDelegate<void> {
  ChatSearchDelegate({
    required this.chats,
    required this.groups,
    required this.archived,
    required this.stories,
    required this.onOpenConversation,
    required this.onOpenStatus,
    required this.onStartChatWithUser,
    required this.onOpenMessage,
  }) : super(searchFieldLabel: 'Search Advent Chat');

  final List<Conversation> chats; // 1:1 conversations
  final List<Conversation> groups;
  final List<Conversation> archived;
  final List<Story> stories;
  final void Function(Conversation) onOpenConversation;
  final void Function(List<Story> reel) onOpenStatus;
  final void Function(String userId, String name) onStartChatWithUser;
  // Open a conversation AND scroll to a specific message (message-content
  // search result). Resolves the conversation by id from the known lists.
  final void Function(String conversationId, String messageId) onOpenMessage;

  ChatSearchScope _scope = ChatSearchScope.messages;
  Future<List<MemberDirectoryEntry>>? _friendsFuture;

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkNavy,
        foregroundColor: AppColors.white,
        elevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white70),
        border: InputBorder.none,
      ),
      textTheme: base.textTheme.copyWith(
        titleLarge: AppTextStyles.titleMedium.copyWith(color: AppColors.white),
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
          showSuggestions(context);
        },
      ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _content(context);

  @override
  Widget buildSuggestions(BuildContext context) => _content(context);

  Widget _content(BuildContext context) {
    // StatefulBuilder so tapping a scope chip ALWAYS rebuilds the results —
    // the previous showSuggestions()-only approach didn't reliably refresh,
    // so every chip except the default (Messages) looked broken.
    return StatefulBuilder(
      builder: (context, setLocal) {
        return Container(
          color: context.palette.scaffoldBg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _scopeChips(context, setLocal),
              Expanded(child: _scopedResults(context)),
            ],
          ),
        );
      },
    );
  }

  Widget _scopeChips(
    BuildContext context,
    void Function(VoidCallback) setLocal,
  ) {
    Widget chip(String label, ChatSearchScope s) {
      final sel = _scope == s;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setLocal(() => _scope = s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? AppColors.primaryBlue : context.palette.chipBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: sel ? AppColors.primaryBlue : context.palette.divider,
              ),
            ),
            child: Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: sel ? AppColors.white : context.palette.text,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        children: [
          chip('Friends', ChatSearchScope.friends),
          chip('Messages', ChatSearchScope.messages),
          chip('Groups', ChatSearchScope.groups),
          chip('Archived', ChatSearchScope.archived),
          chip('Status', ChatSearchScope.status),
          chip('Explore', ChatSearchScope.explore),
        ],
      ),
    );
  }

  Widget _scopedResults(BuildContext context) {
    final q = query.trim().toLowerCase();
    switch (_scope) {
      case ChatSearchScope.friends:
        return _peopleList(context, friendsOnly: true);
      case ChatSearchScope.explore:
        return _peopleList(context, friendsOnly: false);
      case ChatSearchScope.status:
        return _statusList(context, q);
      case ChatSearchScope.messages:
        return _messageSearchList(context, query.trim());
      case ChatSearchScope.groups:
        return _conversationList(context, _filterConvos(groups, q));
      case ChatSearchScope.archived:
        return _conversationList(context, _filterConvos(archived, q));
    }
  }

  List<Conversation> _filterConvos(List<Conversation> list, String q) {
    if (q.isEmpty) return list;
    return list
        .where(
          (c) =>
              c.otherUserName.toLowerCase().contains(q) ||
              c.lastMessage.toLowerCase().contains(q),
        )
        .toList();
  }

  /// Full-text search across the user's actual message history. Tapping a
  /// hit opens the conversation AND scrolls to that exact message.
  Widget _messageSearchList(BuildContext context, String q) {
    if (q.length < 2) {
      return _empty(context, 'Type at least 2 letters to search messages.');
    }
    return FutureBuilder<List<MessageSearchHit>>(
      // Keyed by query so each new query re-runs the search.
      key: ValueKey('msgsearch:$q'),
      future: MessagingService.searchMessages(q),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: BrandSpinner(size: 30));
        }
        final hits = snap.data ?? const <MessageSearchHit>[];
        if (hits.isEmpty) return _empty(context, 'No messages match.');
        return ListView.builder(
          itemCount: hits.length,
          itemBuilder: (_, i) {
            final h = hits[i];
            final convo = _convoById(h.conversationId);
            final title = convo?.otherUserName ?? 'Conversation';
            return ListTile(
              leading: _Avatar(name: title, photoUrl: convo?.otherUserPhotoUrl),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                h.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
              onTap: () {
                close(context, null);
                onOpenMessage(h.conversationId, h.messageId);
              },
            );
          },
        );
      },
    );
  }

  Conversation? _convoById(String id) {
    for (final c in [...chats, ...groups, ...archived]) {
      if (c.id == id) return c;
    }
    return null;
  }

  Widget _conversationList(BuildContext context, List<Conversation> list) {
    if (list.isEmpty) return _empty(context, 'No chats match.');
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final c = list[i];
        return ListTile(
          leading: _Avatar(
            name: c.otherUserName,
            photoUrl: c.otherUserPhotoUrl,
          ),
          title: Text(
            c.otherUserName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: c.lastMessage.isEmpty
              ? null
              : Text(
                  c.lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
          onTap: () {
            close(context, null);
            onOpenConversation(c);
          },
        );
      },
    );
  }

  Widget _statusList(BuildContext context, String q) {
    // Group active stories by author, newest reel per author.
    final byAuthor = <String, List<Story>>{};
    for (final s in stories) {
      if (s.isExpired) continue;
      byAuthor.putIfAbsent(s.authorId, () => []).add(s);
    }
    var authors = byAuthor.entries.toList();
    if (q.isNotEmpty) {
      authors = authors
          .where((e) => e.value.first.authorName.toLowerCase().contains(q))
          .toList();
    }
    if (authors.isEmpty) return _empty(context, 'No status updates match.');
    return ListView.builder(
      itemCount: authors.length,
      itemBuilder: (_, i) {
        final reel = authors[i].value;
        final a = reel.first;
        return ListTile(
          leading: _Avatar(name: a.authorName, photoUrl: a.authorPhotoUrl),
          title: Text(
            a.authorName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            reel.length == 1
                ? '1 status update'
                : '${reel.length} status updates',
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
            ),
          ),
          onTap: () {
            close(context, null);
            onOpenStatus(reel);
          },
        );
      },
    );
  }

  Widget _peopleList(BuildContext context, {required bool friendsOnly}) {
    final q = query.trim();
    if (!friendsOnly && q.isEmpty) {
      return _empty(context, 'Type a name to find people on Advent.');
    }
    final future = friendsOnly
        ? (_friendsFuture ??= DirectoryService.fetchFriends())
        : DirectoryService.searchProfilesByName(q);
    return FutureBuilder<List<MemberDirectoryEntry>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: BrandSpinner(size: 30));
        }
        var people = snap.data ?? const <MemberDirectoryEntry>[];
        if (friendsOnly && q.isNotEmpty) {
          final ql = q.toLowerCase();
          people = people
              .where((m) => (m.fullName ?? '').toLowerCase().contains(ql))
              .toList();
        }
        if (people.isEmpty) {
          return _empty(
            context,
            friendsOnly ? 'No friends match.' : 'No people found.',
          );
        }
        return ListView.builder(
          itemCount: people.length,
          itemBuilder: (_, i) {
            final m = people[i];
            final name = (m.fullName ?? '').trim().isEmpty
                ? 'Member'
                : m.fullName!.trim();
            return ListTile(
              leading: _Avatar(name: name, photoUrl: m.profilePhotoUrl),
              title: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: (m.churchName ?? '').trim().isEmpty
                  ? null
                  : Text(
                      m.churchName!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.palette.textMuted,
                      ),
                    ),
              onTap: () {
                close(context, null);
                onStartChatWithUser(m.userId, name);
              },
            );
          },
        );
      },
    );
  }

  Widget _empty(BuildContext context, String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Text(
        msg,
        textAlign: TextAlign.center,
        style: AppTextStyles.bodyMedium.copyWith(
          color: context.palette.textMuted,
        ),
      ),
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.photoUrl});
  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasPhoto ? null : AppColors.primaryGradient,
      ),
      child: hasPhoto
          ? CachedImage(photoUrl!, fit: BoxFit.cover)
          : Text(
              initial,
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
