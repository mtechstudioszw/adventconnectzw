import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/member_directory_model.dart';
import '../../models/seller_model.dart';
import '../../services/directory_service.dart';
import '../../services/messaging_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/connection_error_view.dart';
import '../../widgets/verified_tick.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/brand_spinner.dart';

/// Browse other community members who opted into the directory.
class MemberDirectoryScreen extends StatefulWidget {
  const MemberDirectoryScreen({super.key});

  @override
  State<MemberDirectoryScreen> createState() => _MemberDirectoryScreenState();
}

class _MemberDirectoryScreenState extends State<MemberDirectoryScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<MemberDirectoryEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  String? _province;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await DirectoryService.fetchEntries(
        search: _searchController.text,
        province: _province,
      );
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the directory. Pull to retry.';
      });
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.pushNamed('my_directory_profile');
          if (mounted) _load();
        },
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: AppColors.white,
        elevation: 6,
        icon: const Icon(Icons.person_outline),
        label: Text(
          'My listing',
          style: AppTextStyles.buttonText.copyWith(fontSize: 14),
        ),
      ),
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const ScreenHero(
                title: 'Member directory',
                tagline: 'Find your community',
                subtitle:
                    'Doctors, teachers, builders, ministers — opt-in members around the globe.',
                fallbackRoute: 'profile',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SearchField(
                      controller: _searchController,
                      onChanged: _onSearch,
                    ),
                    const SizedBox(height: 12),
                    _ProvinceFilter(
                      selected: _province,
                      onChanged: (p) {
                        setState(() => _province = p);
                        _load();
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildList(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Center(child: BrandSpinner(size: 30)),
      );
    }
    if (_error != null) return ConnectionErrorView(onRetry: _load);
    if (_entries.isEmpty) {
      return EmptyStateCard(
        icon: Icons.people_outline,
        title: 'No matches',
        message:
            'Adjust your search or province filter. Be the first to list yourself — tap "My listing" below.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in _entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _DirectoryRow(entry: e),
          ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search profession, skill or city',
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: context.palette.textMuted,
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 14, right: 10),
            child: Icon(Icons.search, color: AppColors.primaryBlue, size: 20),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 44,
            minHeight: 44,
          ),
          filled: true,
          fillColor: context.palette.inputFill,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _ProvinceFilter extends StatelessWidget {
  const _ProvinceFilter({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          _Chip(
            label: 'All',
            active: selected == null,
            onTap: () => onChanged(null),
          ),
          const SizedBox(width: 8),
          for (final p in sellerProvinces) ...[
            _Chip(label: p, active: selected == p, onTap: () => onChanged(p)),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: active ? AppColors.primaryGradient : null,
            color: active ? null : context.palette.chipBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? AppColors.primaryBlue : context.palette.divider,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color: active ? AppColors.white : context.palette.text,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectoryRow extends StatelessWidget {
  const _DirectoryRow({required this.entry});
  final MemberDirectoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(entry.fullName ?? '');
    final photo = entry.profilePhotoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty;
    final location = [
      entry.city,
      entry.province,
    ].where((s) => s != null && s.isNotEmpty).join(', ');
    return ScreenCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
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
                    initials,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        entry.fullName ?? 'Member',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (entry.isVerified) const VerifiedTick(size: 14),
                  ],
                ),
                if (entry.profession != null &&
                    entry.profession!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.profession!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 12,
                        color: context.palette.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: context.palette.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (entry.skills != null &&
                    entry.skills!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    entry.skills!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.text,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Send a message request',
            icon: const Icon(
              Icons.mail_outline,
              color: AppColors.primaryBlue,
              size: 22,
            ),
            onPressed: () => _openRequestSheet(context),
          ),
        ],
      ),
    );
  }

  Future<void> _openRequestSheet(BuildContext context) async {
    final name = (entry.fullName?.trim().isNotEmpty == true)
        ? entry.fullName!.trim()
        : 'Member';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) =>
          _MessageRequestSheet(otherUserId: entry.userId, otherUserName: name),
    );
  }

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
}

class _MessageRequestSheet extends StatefulWidget {
  const _MessageRequestSheet({
    required this.otherUserId,
    required this.otherUserName,
  });

  final String otherUserId;
  final String otherUserName;

  @override
  State<_MessageRequestSheet> createState() => _MessageRequestSheetState();
}

class _MessageRequestSheetState extends State<_MessageRequestSheet> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final convo = await MessagingService.createConversation(
        otherUserId: widget.otherUserId,
        otherUserName: widget.otherUserName,
        firstMessage: body,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await context.pushNamed(
        'chat',
        pathParameters: {'id': convo.id},
        extra: convo,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not send request. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: context.palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: context.palette.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Send a message request',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'To ${widget.otherUserName}. They\'ll see it in their Requests inbox and can accept or decline.',
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: context.palette.cardMuted,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.palette.divider),
              ),
              child: TextField(
                controller: _controller,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                autofocus: true,
                style: AppTextStyles.bodyMedium.copyWith(fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: 'Hi ${widget.otherUserName.split(' ').first}…',
                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                    color: context.palette.textMuted,
                    fontSize: 14.5,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(14),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _sending || _controller.text.trim().isEmpty
                      ? null
                      : _send,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: AppColors.white,
                          ),
                        )
                      : Text(
                          'Send request',
                          style: AppTextStyles.buttonText.copyWith(
                            color: AppColors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
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
