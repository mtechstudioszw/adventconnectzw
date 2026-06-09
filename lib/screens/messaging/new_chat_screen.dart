import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/member_directory_model.dart';
import '../../services/directory_service.dart';
import '../../services/messaging_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';

/// "New chat" people picker — search any member and tap to open a 1:1
/// chat. Replaces the opt-in member directory as the New-chat target so
/// the list is never empty (it searches all discoverable profiles).
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<MemberDirectoryEntry> _results = const [];
  bool _loading = true;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _loadSuggested();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggested() async {
    try {
      final list = await DirectoryService.fetchSuggestedMembers(limit: 40);
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final query = q.trim();
      if (query.isEmpty) {
        _loadSuggested();
        return;
      }
      setState(() => _loading = true);
      try {
        final list = await DirectoryService.searchProfilesByName(query);
        if (!mounted) return;
        setState(() {
          _results = list;
          _loading = false;
        });
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  Future<void> _openChatWith(MemberDirectoryEntry m) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final convo = await MessagingService.createConversation(
        otherUserId: m.userId,
        otherUserName: (m.fullName ?? '').trim().isEmpty
            ? 'Member'
            : m.fullName!.trim(),
      );
      if (!mounted) return;
      context.pushReplacementNamed('chat', pathParameters: {'id': convo.id});
    } catch (_) {
      if (mounted) {
        setState(() => _opening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not start the chat. Try again.',
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkNavy,
        foregroundColor: AppColors.white,
        title: const Text('New chat'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: 'Search people',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: context.palette.inputFill,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryBlue,
                      ),
                    )
                  : _results.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              'No people found. Try a different name.',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: context.palette.textMuted,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, i) {
                            final m = _results[i];
                            final name = (m.fullName ?? '').trim().isEmpty
                                ? 'Member'
                                : m.fullName!.trim();
                            return ListTile(
                              leading: _Avatar(
                                  name: name, photoUrl: m.profilePhotoUrl),
                              title: Text(
                                name,
                                style: AppTextStyles.bodyMedium
                                    .copyWith(fontWeight: FontWeight.w600),
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
                              onTap: () => _openChatWith(m),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
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
