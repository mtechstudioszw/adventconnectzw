import 'package:flutter/material.dart';
import '../../widgets/motion/brand_spinner.dart';
import 'package:go_router/go_router.dart';

import '../../models/member_directory_model.dart';
import '../../models/seller_model.dart';
import '../../services/directory_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';

/// The user's editable row in `member_directory`. Toggling the visibility
/// switch off preserves the fields so they can flip it back on later
/// without re-typing.
class MyDirectoryProfileScreen extends StatefulWidget {
  const MyDirectoryProfileScreen({super.key});

  @override
  State<MyDirectoryProfileScreen> createState() =>
      _MyDirectoryProfileScreenState();
}

class _MyDirectoryProfileScreenState extends State<MyDirectoryProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _professionController = TextEditingController();
  final _skillsController = TextEditingController();
  final _cityController = TextEditingController();
  final _bioController = TextEditingController();

  bool _isVisible = true;
  String? _province;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  MemberDirectoryEntry? _existing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _professionController.dispose();
    _skillsController.dispose();
    _cityController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final entry = await DirectoryService.fetchMyEntry();
      if (!mounted) return;
      if (entry != null) {
        _existing = entry;
        _professionController.text = entry.profession ?? '';
        _skillsController.text = entry.skills ?? '';
        _cityController.text = entry.city ?? '';
        _bioController.text = entry.bio ?? '';
        _isVisible = entry.isVisible;
        _province = entry.province;
      }
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your listing. Pull to retry.';
      });
    }
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await DirectoryService.upsertMyEntry(
        profession: _professionController.text,
        skills: _skillsController.text,
        province: _province,
        city: _cityController.text,
        bio: _bioController.text,
        isVisible: _isVisible,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            _isVisible
                ? 'Your listing is live in the directory.'
                : 'Your listing is hidden.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            ScreenHero(
              title:
                  _existing == null ? 'Join the directory' : 'My directory listing',
              tagline: 'Member directory',
              subtitle:
                  'Share what you do so others in the community can find you.',
              fallbackRoute: 'member_directory',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 64),
                      child: Center(child: BrandSpinner(size: 30)),
                    )
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ScreenCard(
                            child: _VisibilityToggle(
                              value: _isVisible,
                              onChanged: (v) => setState(() => _isVisible = v),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ScreenCard(
                            child: Column(
                              children: [
                                _LabeledField(
                                  label: 'Profession',
                                  child: _Input(
                                    controller: _professionController,
                                    hint: 'Nurse, builder, accountant…',
                                    icon: Icons.work_outline,
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Profession is required';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 18),
                                _LabeledField(
                                  label: 'Skills (optional)',
                                  child: _Input(
                                    controller: _skillsController,
                                    hint: 'Plumbing, IELTS prep, IT support…',
                                    icon: Icons.handyman_outlined,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                _LabeledField(
                                  label: 'Province',
                                  child: _ProvinceDropdown(
                                    selected: _province,
                                    onChanged: (v) =>
                                        setState(() => _province = v),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                _LabeledField(
                                  label: 'City / town',
                                  child: _Input(
                                    controller: _cityController,
                                    hint: 'Harare',
                                    icon: Icons.location_city_outlined,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                _LabeledField(
                                  label: 'Short bio',
                                  helper: '${_bioController.text.length}/240',
                                  child: TextFormField(
                                    controller: _bioController,
                                    maxLength: 240,
                                    maxLines: 3,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    onChanged: (_) => setState(() {}),
                                    style: AppTextStyles.bodyLarge
                                        .copyWith(fontSize: 15),
                                    decoration: _decoration(
                                      icon: Icons.notes_outlined,
                                      hint:
                                          'One or two lines about what you offer.',
                                    ).copyWith(counterText: ''),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            ErrorBanner(message: _error!),
                          ],
                          const SizedBox(height: 24),
                          PrimaryGradientButton(
                            label: _saving ? 'Saving...' : 'Save listing',
                            busy: _saving,
                            onTap: _saving ? null : _save,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration({
    required IconData icon,
    required String hint,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 14, right: 10),
        child: Icon(icon, color: AppColors.primaryBlue, size: 20),
      ),
      prefixIconConstraints:
          const BoxConstraints(minWidth: 44, minHeight: 44),
      filled: true,
      fillColor: context.palette.cardMuted,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: context.palette.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: context.palette.divider),
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

class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(
            value ? Icons.public : Icons.public_off,
            color: AppColors.primaryBlue,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value ? 'Visible in the directory' : 'Hidden from the directory',
                style: AppTextStyles.titleSmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value
                    ? 'Other members can find your listing.'
                    : 'Your details are saved but not shown.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primaryBlue,
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
    this.helper,
  });

  final String label;
  final Widget child;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label.toUpperCase(),
              style: AppTextStyles.labelSmall.copyWith(
                color: context.palette.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            if (helper != null)
              Text(
                helper!,
                style: AppTextStyles.labelSmall.copyWith(
                  color: context.palette.textMuted,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.hint,
    required this.icon,
    this.validator,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      textCapitalization: TextCapitalization.sentences,
      style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Icon(icon, color: AppColors.primaryBlue, size: 20),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 44, minHeight: 44),
        filled: true,
        fillColor: context.palette.cardMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.palette.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.palette.divider),
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
      ),
    );
  }
}

class _ProvinceDropdown extends StatelessWidget {
  const _ProvinceDropdown({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: selected,
      isExpanded: true,
      icon: Icon(
        Icons.expand_more,
        color: context.palette.textMuted,
      ),
      style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
      decoration: InputDecoration(
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 14, right: 10),
          child: Icon(
            Icons.map_outlined,
            color: AppColors.primaryBlue,
            size: 20,
          ),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 44, minHeight: 44),
        filled: true,
        fillColor: context.palette.cardMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.palette.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.palette.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.primaryBlue, width: 1.5),
        ),
      ),
      hint: Text(
        'Choose a province',
        style: AppTextStyles.bodyLarge.copyWith(
          color: context.palette.textMuted,
          fontSize: 15,
        ),
      ),
      items: [
        for (final p in sellerProvinces)
          DropdownMenuItem<String?>(value: p, child: Text(p)),
      ],
      onChanged: onChanged,
    );
  }
}
