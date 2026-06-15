import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/church_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';

/// Church admin dashboard. The post-an-announcement composer lives
/// inline so admins can fire off updates without a route hop.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, required this.role});

  final ChurchAdminRole role;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  String? _error;
  List<ChurchAnnouncement> _items = const [];

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
      final items = await ChurchService.fetchAnnouncements(
        churchId: widget.role.churchId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load announcements.';
      });
    }
  }

  Future<void> _openComposer() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ComposerSheet(churchId: widget.role.churchId),
    );
    if (result == true) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openComposer,
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: AppColors.white,
        elevation: 6,
        icon: const Icon(Icons.campaign_outlined),
        label: Text(
          'New announcement',
          style: AppTextStyles.buttonText.copyWith(fontSize: 14),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              ScreenHero(
                title: widget.role.churchName,
                tagline: 'Church admin · ${widget.role.role}',
                subtitle:
                    'Post announcements, review pending content, manage church info.',
                fallbackRoute: 'admin_login',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _QuickActionsCard(
                      onPost: _openComposer,
                      onApprovals: () => context.pushNamed(
                        'pending_approvals',
                        extra: widget.role,
                      ),
                      onPostEvent: () => context.pushNamed('post_event'),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'RECENT ANNOUNCEMENTS',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: const Color.fromRGBO(26, 26, 46, 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      )
                    else if (_error != null)
                      ErrorBanner(message: _error!)
                    else if (_items.isEmpty)
                      EmptyStateCard(
                        icon: Icons.campaign_outlined,
                        title: 'No announcements yet',
                        message:
                            'Tap the button below to post the first one.',
                      )
                    else
                      for (final item in _items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _AnnouncementSummary(item: item),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.onPost,
    required this.onApprovals,
    required this.onPostEvent,
  });

  final VoidCallback onPost;
  final VoidCallback onApprovals;
  final VoidCallback onPostEvent;

  @override
  Widget build(BuildContext context) {
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUICK ACTIONS',
            style: AppTextStyles.labelSmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.55),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          _Row(
            icon: Icons.campaign_outlined,
            title: 'Post announcement',
            subtitle: 'Reach every follower of this church.',
            onTap: onPost,
          ),
          const _Divider(),
          _Row(
            icon: Icons.event_outlined,
            title: 'Post an event',
            subtitle: 'Add to the events feed.',
            onTap: onPostEvent,
          ),
          const _Divider(),
          _Row(
            icon: Icons.task_alt_outlined,
            title: 'Pending approvals',
            subtitle: 'Review content waiting on you.',
            onTap: onApprovals,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primaryBlue, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color.fromRGBO(26, 26, 46, 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      color: Color.fromRGBO(26, 26, 46, 0.06),
    );
  }
}

class _AnnouncementSummary extends StatelessWidget {
  const _AnnouncementSummary({required this.item});

  final ChurchAnnouncement item;

  @override
  Widget build(BuildContext context) {
    return ScreenCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.category.toUpperCase(),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (item.isPinned) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.push_pin,
                  color: AppColors.goldAccent,
                  size: 14,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            style: AppTextStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.7),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerSheet extends StatefulWidget {
  const _ComposerSheet({required this.churchId});

  final String churchId;

  @override
  State<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<_ComposerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String _category = 'general';
  bool _pinned = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ChurchService.postAnnouncement(
        churchId: widget.churchId,
        title: _titleController.text,
        body: _bodyController.text,
        category: _category,
        isPinned: _pinned,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(26, 26, 46, 0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'New announcement',
                    style: AppTextStyles.headlineSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in const [
                        'general',
                        'urgent',
                        'event',
                        'program',
                        'obituary',
                      ])
                        _CategoryChip(
                          label: c,
                          active: _category == c,
                          onTap: () => setState(() => _category = c),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _titleController,
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      return null;
                    },
                    style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                    decoration: _dec(hint: 'Title', icon: Icons.title),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bodyController,
                    maxLines: 5,
                    maxLength: 600,
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (v.trim().length < 10) return 'A little longer please';
                      return null;
                    },
                    style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                    decoration: _dec(
                      hint: 'Body',
                      icon: Icons.notes_outlined,
                    ).copyWith(counterText: ''),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.push_pin_outlined,
                        color: AppColors.primaryBlue,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Pin this announcement',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: _pinned,
                        onChanged: (v) => setState(() => _pinned = v),
                        activeThumbColor: AppColors.primaryBlue,
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 16),
                  PrimaryGradientButton(
                    label: _saving ? 'Posting...' : 'Post announcement',
                    busy: _saving,
                    onTap: _saving ? null : _post,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 14, right: 10),
        child: Icon(icon, color: AppColors.primaryBlue, size: 20),
      ),
      prefixIconConstraints:
          const BoxConstraints(minWidth: 44, minHeight: 44),
      filled: true,
      fillColor: AppColors.lightGrey,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color.fromRGBO(26, 26, 46, 0.06)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color.fromRGBO(26, 26, 46, 0.06)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: AppColors.primaryBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: active ? AppColors.primaryGradient : null,
          color: active ? null : AppColors.lightGrey,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? AppColors.primaryBlue
                : const Color.fromRGBO(26, 26, 46, 0.08),
          ),
        ),
        child: Text(
          label[0].toUpperCase() + label.substring(1),
          style: AppTextStyles.labelMedium.copyWith(
            color: active ? AppColors.white : AppColors.text,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}
