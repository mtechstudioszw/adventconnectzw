import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../config/countries.dart';
import '../../models/seller_model.dart';
import '../../services/auth_service.dart';
import '../../services/church_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/country_picker_sheet.dart';
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

  /// Free-text region for non-ZW churches. Shares the `province` column
  /// with [_province]; see [_regionValue].
  final _regionController = TextEditingController();

  /// ISO 3166-1 alpha-2, seeded from the suggester's own profile — the
  /// church they know about is almost always in their own country.
  String? _country = AuthService.currentCountry();
  String? _province;
  bool _saving = false;
  String? _error;

  /// Zimbabwe is the one country with a real province list in this app.
  /// Everywhere else the same column takes free text.
  bool get _isZimbabwe => _country == 'ZW';

  /// What goes in the `province` column: the dropdown in Zimbabwe, the
  /// free-text region anywhere else, null when neither is filled.
  String? get _regionValue {
    if (_isZimbabwe) return _province;
    final typed = _regionController.text.trim();
    return typed.isEmpty ? null : typed;
  }

  /// Changing country invalidates whichever location control is showing,
  /// so the old value is dropped rather than carried across.
  void _onCountryPicked(Country picked) {
    setState(() {
      _country = picked.code;
      _province = null;
      _regionController.clear();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _suburbController.dispose();
    _pastorController.dispose();
    _phoneController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    // Province stays mandatory in Zimbabwe, where the dropdown makes it one
    // tap. Elsewhere it is optional — a Kenyan church has no Zimbabwean
    // province, and demanding one is what kept this form ZW-only.
    if (_isZimbabwe && _province == null) {
      setState(() => _error = 'Pick the province.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ChurchService.suggestChurch(
        name: _nameController.text,
        country: _country,
        province: _regionValue,
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
      backgroundColor: Colors.transparent,
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
                          _Label(text: 'Country'),
                          const SizedBox(height: 8),
                          CountryFormField(
                            code: _country,
                            decoration: _dec(
                              hint: 'Choose a country',
                              icon: Icons.public,
                            ),
                            onChanged: _onCountryPicked,
                          ),
                          const SizedBox(height: 18),
                          // Province is a Zimbabwean administrative unit —
                          // offer the list only where it means something,
                          // free text everywhere else.
                          if (_isZimbabwe) ...[
                            _Label(text: 'Province'),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _province,
                              isExpanded: true,
                              icon:  Icon(
                                Icons.expand_more,
                                color: AppColors.textMuted,
                              ),
                              style: AppTextStyles.bodyLarge
                                  .copyWith(fontSize: 15),
                              hint: Text(
                                'Choose a province',
                                style: AppTextStyles.bodyLarge.copyWith(
                                  color: AppColors.textMuted,
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
                          ] else ...[
                            _Label(text: 'State or region (optional)'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _regionController,
                              textCapitalization: TextCapitalization.words,
                              style: AppTextStyles.bodyLarge
                                  .copyWith(fontSize: 15),
                              decoration: _dec(
                                hint: 'e.g. Nairobi County',
                                icon: Icons.map_outlined,
                              ),
                            ),
                          ],
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
                              hint: Countries.phoneHint(_country),
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
        borderSide:  BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:  BorderSide(color: AppColors.divider),
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
        color: AppColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}
