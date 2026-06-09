import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/presence_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import 'cached_image.dart';
import 'full_image_viewer.dart';

/// WhatsApp-style contact preview sheet. Surfaces only the chat-
/// relevant subset of the other user's profile — big photo, name,
/// online/last-seen, bio — with a "View full profile" CTA that pushes
/// to the full UserProfileScreen for things like their posts grid.
///
/// Opened by tapping the chat header in chat_screen.dart. Tapping
/// outside dismisses; tapping the big photo dismisses too.
Future<void> showChatContactSheet(
  BuildContext context, {
  required String userId,
  required String fallbackName,
  String? fallbackPhotoUrl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => _ChatContactSheet(
      userId: userId,
      fallbackName: fallbackName,
      fallbackPhotoUrl: fallbackPhotoUrl,
    ),
  );
}

class _ChatContactSheet extends StatefulWidget {
  const _ChatContactSheet({
    required this.userId,
    required this.fallbackName,
    this.fallbackPhotoUrl,
  });

  final String userId;
  final String fallbackName;
  final String? fallbackPhotoUrl;

  @override
  State<_ChatContactSheet> createState() => _ChatContactSheetState();
}

class _ChatContactSheetState extends State<_ChatContactSheet> {
  PublicUserProfile? _profile;
  DateTime? _lastSeen;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      UserProfileService.fetch(widget.userId),
      PresenceService.fetchLastSeen(widget.userId),
    ]);
    if (!mounted) return;
    setState(() {
      _profile = results[0] as PublicUserProfile?;
      _lastSeen = results[1] as DateTime?;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = (_profile?.fullName.trim().isNotEmpty == true)
        ? _profile!.fullName.trim()
        : widget.fallbackName;
    final photoUrl = _profile?.profilePhotoUrl ?? widget.fallbackPhotoUrl;
    final bio = _profile?.bio?.trim() ?? '';
    final coverUrl = _profile?.coverPhotoUrl;

    final isOnline = PresenceService.isOnline(widget.userId);
    final presence = isOnline
        ? 'Online'
        : (_lastSeen != null
            ? 'Last seen ${PresenceService.formatLastSeen(_lastSeen!)}'
            : 'Offline');

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, controller) => Container(
        decoration: BoxDecoration(
          color: context.palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grab handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 14),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.palette.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Cover photo strip — falls back to a flat colour so the
              // layout stays consistent for users without a cover.
              SizedBox(
                height: 120,
                child: (coverUrl ?? '').isNotEmpty
                    ? GestureDetector(
                        onTap: () => FullImageViewer.show(context, coverUrl),
                        child: CachedImage(
                          coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            color:
                                AppColors.primaryBlue.withValues(alpha: 0.08),
                          ),
                        ),
                      )
                    : Container(
                        color: AppColors.primaryBlue.withValues(alpha: 0.08),
                      ),
              ),
              const SizedBox(height: 12),
              Center(
                child: GestureDetector(
                  onTap: (photoUrl ?? '').isNotEmpty
                      ? () => FullImageViewer.show(context, photoUrl)
                      : null,
                  child: _bigAvatar(name: name, photoUrl: photoUrl),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleLarge.copyWith(
                        color: context.palette.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isOnline) ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.successGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          presence,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: context.palette.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (bio.isNotEmpty) ...[
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.palette.cardMuted,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      bio,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: context.palette.text,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          context.pushNamed(
                            'user_profile',
                            pathParameters: {'userId': widget.userId},
                          );
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: AppColors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('View full profile'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bigAvatar({required String name, required String? photoUrl}) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
            ? parts.first.substring(0, 1).toUpperCase()
            : (parts.first.substring(0, 1) + parts.last.substring(0, 1))
                .toUpperCase();
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    return Container(
      width: 96,
      height: 96,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: hasPhoto ? null : AppColors.primaryGradient,
        color: hasPhoto ? context.palette.cardMuted : null,
        shape: BoxShape.circle,
        border: Border.all(color: context.palette.sheet, width: 4),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: hasPhoto
          ? CachedImage(
              photoUrl!,
              fit: BoxFit.cover,
              width: 96,
              height: 96,
              errorBuilder: (context, error, stackTrace) => _initialsLabel(initials),
            )
          : _initialsLabel(initials),
    );
  }

  Widget _initialsLabel(String initials) {
    return Text(
      initials,
      style: AppTextStyles.titleLarge.copyWith(
        color: AppColors.white,
        fontWeight: FontWeight.w800,
        fontSize: 32,
      ),
    );
  }
}
