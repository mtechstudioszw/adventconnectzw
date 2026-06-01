import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/prayer_model.dart';
import '../../services/prayer_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../widgets/post_form_widgets.dart';

class PostPrayerScreen extends StatefulWidget {
  const PostPrayerScreen({super.key, this.existing});

  /// When non-null, edits the existing prayer instead of creating a new
  /// one. The form pre-fills with the prayer's content/title.
  final Prayer? existing;

  bool get isEditing => existing != null;

  @override
  State<PostPrayerScreen> createState() => _PostPrayerScreenState();
}

class _PostPrayerScreenState extends State<PostPrayerScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  String _visibility = 'public';
  bool _isUrgent = false;
  PrayerCategory _category = PrayerCategory.other;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
    );
    _contentController.addListener(() => setState(() {}));

    final existing = widget.existing;
    if (existing != null) {
      _contentController.text = existing.content;
      _category = existing.category;
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (widget.isEditing) {
        await PrayerService.updatePrayer(
          prayerId: widget.existing!.id,
          content: _contentController.text,
          visibility: _visibility,
          isUrgent: _isUrgent,
          title: _titleController.text,
          category: _category.code,
        );
      } else {
        await PrayerService.postPrayer(
          _contentController.text,
          visibility: _visibility,
          isUrgent: _isUrgent,
          title: _titleController.text,
          category: _category.code,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditing
                ? 'Prayer updated.'
                : 'Prayer shared with the community.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      context.pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = widget.isEditing
              ? 'Could not update your prayer. Please try again.'
              : 'Could not share your prayer. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final length = _contentController.text.length;
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            PostFormHero(
              kicker: widget.isEditing ? 'EDIT PRAYER' : 'PRAYER REQUEST',
              title: widget.isEditing
                  ? 'Update your prayer'
                  : 'Lift it to the community',
              subtitle: widget.isEditing
                  ? 'Edit your prayer and save your changes.'
                  : 'Share what you need prayer for. Members will pray with you.',
              fallbackRouteName: 'prayer',
            ),
            AnimatedBuilder(
              animation: _entrance,
              builder: (context, child) => Opacity(
                opacity: _fade.value,
                child: Transform.translate(
                  offset: Offset(0, _slide.value),
                  child: child,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PostFormCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PostFormLabeledField(
                              label: 'Title (optional)',
                              child: TextFormField(
                                controller: _titleController,
                                style: AppTextStyles.bodyLarge
                                    .copyWith(fontSize: 15),
                                decoration: postFormFilledDecoration(
                                  icon: Icons.title,
                                  hint: 'A short title for your request',
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            PostFormLabeledField(
                              label: 'Your prayer',
                              helper: '$length/2000',
                              child: TextFormField(
                                controller: _contentController,
                                maxLines: 6,
                                maxLength: 2000,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                style: AppTextStyles.bodyLarge
                                    .copyWith(fontSize: 15),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Type what you need prayer for';
                                  }
                                  if (v.trim().length < 5) {
                                    return 'Tell us a bit more';
                                  }
                                  return null;
                                },
                                decoration: postFormFilledDecoration(
                                  icon: Icons.notes_outlined,
                                  hint: 'Pray with me for...',
                                ).copyWith(counterText: ''),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildCategoryCard(),
                      const SizedBox(height: 16),
                      _buildVisibilityCard(),
                      const SizedBox(height: 16),
                      _buildUrgentToggle(),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        PostFormErrorBanner(message: _error!),
                      ],
                      const SizedBox(height: 24),
                      PostFormSaveButton(
                        label: widget.isEditing
                            ? 'Save changes'
                            : 'Share prayer',
                        busy: _saving,
                        onTap: _saving ? null : _save,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard() {
    return PostFormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CATEGORY',
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in PrayerCategory.values)
                Material(
                  color: c == _category
                      ? AppColors.primaryBlue
                      : context.palette.chipBg,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _category = c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: c == _category
                              ? AppColors.primaryBlue
                              : const Color.fromRGBO(26, 26, 46, 0.08),
                        ),
                      ),
                      child: Text(
                        c.label,
                        style: AppTextStyles.labelMedium.copyWith(
                          color: c == _category
                              ? AppColors.white
                              : context.palette.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVisibilityCard() {
    return PostFormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHO CAN SEE THIS',
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          _VisibilityOption(
            icon: Icons.public,
            title: 'Public',
            subtitle: 'Everyone in the community can see and pray.',
            selected: _visibility == 'public',
            onTap: () => setState(() => _visibility = 'public'),
          ),
          const SizedBox(height: 8),
          _VisibilityOption(
            icon: Icons.church_outlined,
            title: 'Church only',
            subtitle: 'Only members who follow your home church.',
            selected: _visibility == 'church_only',
            onTap: () => setState(() => _visibility = 'church_only'),
          ),
          const SizedBox(height: 8),
          _VisibilityOption(
            icon: Icons.visibility_off_outlined,
            title: 'Anonymous',
            subtitle: 'Public, but your name is hidden.',
            selected: _visibility == 'anonymous',
            onTap: () => setState(() => _visibility = 'anonymous'),
          ),
        ],
      ),
    );
  }

  Widget _buildUrgentToggle() {
    return PostFormCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.priority_high,
              color: AppColors.red,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mark as urgent',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Highlights your request at the top of the feed.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _isUrgent,
            onChanged: (v) => setState(() => _isUrgent = v),
            activeThumbColor: AppColors.white,
            activeTrackColor: AppColors.primaryBlue,
          ),
        ],
      ),
    );
  }
}

class _VisibilityOption extends StatelessWidget {
  const _VisibilityOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryBlue.withValues(alpha: 0.06)
                : context.palette.cardMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppColors.primaryBlue
                  : const Color.fromRGBO(26, 26, 46, 0.06),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: selected ? AppColors.primaryGradient : null,
                  color: selected ? null : context.palette.card,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: selected ? AppColors.white : AppColors.primaryBlue,
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
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? AppColors.primaryBlue
                    : const Color.fromRGBO(26, 26, 46, 0.30),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
