import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/church_model.dart';
import '../../services/church_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';

/// Lets users propose an edit to a church's profile. The chosen field
/// + new value lands in `church_edit_suggestions` for admin review.
class SuggestEditScreen extends StatefulWidget {
  const SuggestEditScreen({super.key, required this.church});

  final Church church;

  @override
  State<SuggestEditScreen> createState() => _SuggestEditScreenState();
}

class _SuggestEditScreenState extends State<SuggestEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newValueController = TextEditingController();

  late final List<_Field> _fields = _buildFields(widget.church);
  _Field? _selected;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = _fields.first;
    _newValueController.text = '';
  }

  @override
  void dispose() {
    _newValueController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_selected == null) return;
    setState(() => _saving = true);
    try {
      await ChurchService.suggestEdit(
        churchId: widget.church.id,
        fieldName: _selected!.key,
        currentValue: _selected!.currentValue ?? '',
        suggestedValue: _newValueController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Suggestion sent. Thank you!',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      if (context.canPop()) context.pop();
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
              title: 'Suggest an edit',
              tagline: widget.church.name,
              subtitle:
                  'Help keep the directory accurate. Admins review every change.',
              fallbackRoute: 'churches',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ScreenCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WHICH FIELD?',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: const Color.fromRGBO(26, 26, 46, 0.65),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (final f in _fields)
                            _FieldRow(
                              field: f,
                              active: _selected?.key == f.key,
                              onTap: () => setState(() {
                                _selected = f;
                                _newValueController.text = '';
                              }),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_selected != null) ...[
                      ScreenCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CURRENT VALUE',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: const Color.fromRGBO(26, 26, 46, 0.55),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: context.palette.cardMuted,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                _selected!.currentValue?.isNotEmpty == true
                                    ? _selected!.currentValue!
                                    : '— Not set —',
                                style: AppTextStyles.bodyMedium,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'NEW VALUE',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: const Color.fromRGBO(26, 26, 46, 0.65),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _newValueController,
                              maxLines: _selected!.multiline ? 4 : 1,
                              keyboardType: _selected!.keyboardType,
                              textCapitalization: TextCapitalization.sentences,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Type the corrected value';
                                }
                                if (v.trim() == _selected!.currentValue) {
                                  return 'Value is unchanged';
                                }
                                return null;
                              },
                              style: AppTextStyles.bodyLarge
                                  .copyWith(fontSize: 15),
                              decoration: _decoration(
                                hint: 'Type the corrected value',
                                icon: _selected!.icon,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 24),
                    PrimaryGradientButton(
                      label: _saving ? 'Submitting...' : 'Submit suggestion',
                      busy: _saving,
                      onTap: _saving ? null : _submit,
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
    required String hint,
    required IconData icon,
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
      fillColor: context.palette.inputFill,
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

class _Field {
  const _Field({
    required this.key,
    required this.label,
    required this.icon,
    this.currentValue,
    this.multiline = false,
    this.keyboardType,
  });
  final String key;
  final String label;
  final IconData icon;
  final String? currentValue;
  final bool multiline;
  final TextInputType? keyboardType;
}

List<_Field> _buildFields(Church c) {
  return [
    _Field(
      key: 'name',
      label: 'Church name',
      icon: Icons.church,
      currentValue: c.name,
    ),
    _Field(
      key: 'city',
      label: 'City',
      icon: Icons.location_city_outlined,
      currentValue: c.city,
    ),
    _Field(
      key: 'address',
      label: 'Physical address',
      icon: Icons.place_outlined,
      currentValue: c.address,
      multiline: true,
    ),
    _Field(
      key: 'pastor_name',
      label: 'Pastor name',
      icon: Icons.person_outline,
      currentValue: c.pastorName,
    ),
    _Field(
      key: 'contact_phone',
      label: 'Contact phone',
      icon: Icons.phone_outlined,
      currentValue: c.contactPhone,
      keyboardType: TextInputType.phone,
    ),
    _Field(
      key: 'contact_email',
      label: 'Contact email',
      icon: Icons.email_outlined,
      currentValue: c.contactEmail,
      keyboardType: TextInputType.emailAddress,
    ),
    _Field(
      key: 'description',
      label: 'Description',
      icon: Icons.notes_outlined,
      currentValue: c.description,
      multiline: true,
    ),
  ];
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.active,
    required this.onTap,
  });
  final _Field field;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primaryBlue.withValues(alpha: 0.08)
                : context.palette.cardMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? AppColors.primaryBlue : Colors.transparent,
              width: 1.4,
            ),
          ),
          child: Row(
            children: [
              Icon(
                field.icon,
                color: active
                    ? AppColors.primaryBlue
                    : const Color.fromRGBO(26, 26, 46, 0.55),
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.label,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: active
                            ? AppColors.primaryBlue
                            : AppColors.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (field.currentValue != null &&
                        field.currentValue!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          field.currentValue!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: const Color.fromRGBO(26, 26, 46, 0.6),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                active ? Icons.radio_button_checked : Icons.radio_button_off,
                color: active
                    ? AppColors.primaryBlue
                    : const Color.fromRGBO(26, 26, 46, 0.35),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
