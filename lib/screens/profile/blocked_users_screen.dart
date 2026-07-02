import 'package:flutter/material.dart';

import '../../services/block_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/brand_spinner.dart';

/// Lists everyone the current user has blocked. Tap "Unblock" to undo.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  bool _loading = true;
  String? _error;
  List<BlockedUser> _items = const [];
  final Set<String> _busy = <String>{};

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
      final items = await BlockService.fetchMyBlocked();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your block list. Pull to retry.';
      });
    }
  }

  Future<void> _unblock(BlockedUser u) async {
    setState(() => _busy.add(u.blockedId));
    try {
      await BlockService.unblock(u.blockedId);
      if (!mounted) return;
      setState(() => _items = _items.where((x) => x.id != u.id).toList());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Unblocked. They can message you again.',
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
            'Could not unblock. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(u.blockedId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const ScreenHero(
                title: 'Blocked users',
                tagline: 'Privacy',
                subtitle:
                    'People you\'ve blocked can\'t see your profile or message you.',
                fallbackRoute: 'settings',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Center(child: BrandSpinner(size: 30)),
      );
    }
    if (_error != null) return ErrorBanner(message: _error!);
    if (_items.isEmpty) {
      return EmptyStateCard(
        icon: Icons.lock_open_outlined,
        title: 'Your block list is empty',
        message:
            'When you block someone, they\'ll appear here. You can unblock at any time.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final u in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _UserRow(
              user: u,
              busy: _busy.contains(u.blockedId),
              onUnblock: () => _unblock(u),
            ),
          ),
      ],
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.busy,
    required this.onUnblock,
  });

  final BlockedUser user;
  final bool busy;
  final VoidCallback onUnblock;

  String _initials(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final name = user.fullName ?? 'Member';
    final photo = user.profilePhotoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty;
    return ScreenCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: hasPhoto ? null : AppColors.primaryGradient,
              color: hasPhoto ? context.palette.cardMuted : null,
              shape: BoxShape.circle,
              image: hasPhoto
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(photo),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: hasPhoto
                ? null
                : Text(
                    _initials(name),
                    style: AppTextStyles.titleSmall.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleSmall.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: busy ? null : onUnblock,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: 0.4),
                  ),
                ),
                child: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryBlue,
                        ),
                      )
                    : Text(
                        'Unblock',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
