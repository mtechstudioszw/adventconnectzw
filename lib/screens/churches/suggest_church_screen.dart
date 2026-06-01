import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../models/seller_model.dart';
import '../../services/church_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';

/// Lets users propose a new SDA church for the directory. Inserts into
/// `church_suggestions` for admin review.
class SuggestChurchScreen extends StatefulWidget {
  const SuggestChurchScreen({super.key});

  @override
  State<SuggestChurchScreen> createState() => _SuggestChurchScreenState();
}

class _SuggestChurchScreenState extends State<SuggestChurchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _cityController = TextEditingController();
  final _suburbController = TextEditingController();
  final _pastorController = TextEditingController();
  final _phoneController = TextEditingController();

  String? _province;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _suburbController.dispose();
    _pastorController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_province == null) {
      setState(() => _error = 'Pick the province.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ChurchService.suggestChurch(
        name: _nameController.text,
        province: _province!,
        city: _cityController.text,
        suburb: _suburbController.text,
        pastorName: _pastorController.text,
        contactPhone: _phoneController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Thanks! We\'ll review and add it to the directory.',
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
            const ScreenHero(
              title: 'Add a missing church',
              tagline: 'Help us grow the directory',
              subtitle:
                  'Share what you know and we\'ll add it after verification.',
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
                          _Label(text: 'Church name'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Required';
                              }
                              return null;
                            },
                            style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                            decoration: _dec(
                              hint: 'e.g. Avondale SDA Church',
                              icon: Icons.church,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _Label(text: 'Province'),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _province,
                            isExpanded: true,
                            icon: const Icon(
                              Icons.expand_more,
                              color: Color.fromRGBO(26, 26, 46, 0.5),
                            ),
                            style: AppTextStyles.bodyLarge
                                .copyWith(fontSize: 15),
                            hint: Text(
                              'Choose a province',
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: const Color.fromRGBO(26, 26, 46, 0.5),
                                fontSize: 15,
                              ),
                            ),
                            items: [
                              for (final p in sellerProvinces)
                                DropdownMenuItem<String>(
                                  value: p,
                                  child: Text(p),
                                ),
                            ],
                            decoration: _dec(
                              hint: 'Choose a province',
                              icon: Icons.map_outlined,
                            ),
                            onChanged: (v) => setState(() => _province = v),
                          ),
                          const SizedBox(height: 18),
                          _Label(text: 'City / town'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _cityController,
                            textCapitalization: TextCapitalization.words,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Required';
                              }
                              return null;
                            },
                            style: AppTextStyles.bodyLarge
                                .copyWith(fontSize: 15),
                            decoration: _dec(
                              hint: 'Harare',
                              icon: Icons.location_city_outlined,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _Label(text: 'Suburb (optional)'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _suburbController,
                            textCapitalization: TextCapitalization.words,
                            style: AppTextStyles.bodyLarge
                                .copyWith(fontSize: 15),
                            decoration: _dec(
                              hint: 'Avondale',
                              icon: Icons.place_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ScreenCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Label(text: 'Pastor name (optional)'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _pastorController,
                            textCapitalization: TextCapitalization.words,
                            style: AppTextStyles.bodyLarge
                                .copyWith(fontSize: 15),
                            decoration: _dec(
                              hint: 'Pastor Tendai Moyo',
                              icon: Icons.person_outline,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _Label(text: 'Contact phone (optional)'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9+\s\-]'),
                              ),
                            ],
                            style: AppTextStyles.bodyLarge
                                .copyWith(fontSize: 15),
                            decoration: _dec(
                              hint: '+263 77 123 4567',
                              icon: Icons.phone_outlined,
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
                      label: _saving ? 'Submitting...' : 'Suggest church',
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

  InputDecoration _dec({
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

class _Label extends StatelessWidget {
  const _Label({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.labelSmall.copyWith(
        color: const Color.fromRGBO(26, 26, 46, 0.65),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}
