import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/account_service.dart';
import '../../services/account_mode_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// "Apply for a Business account" form. The user fills in their
/// business name, picks a category, optionally writes a short pitch,
/// and submits. The row sits as pending until the admin panel
/// approves or rejects it.
class ApplyBusinessScreen extends StatefulWidget {
  const ApplyBusinessScreen({super.key});

  @override
  State<ApplyBusinessScreen> createState() => _ApplyBusinessScreenState();
}

class _ApplyBusinessScreenState extends State<ApplyBusinessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _category = _categories.first;
  bool _submitting = false;
  bool _approved = false;
  String? _errorMessage;

  static const _categories = [
    'Retail / Marketplace',
    'Church / Ministry',
    'Food & Drink',
    'Education',
    'Health',
    'Services',
    'Other',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _whatsappController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await AccountService.applyForBusiness(
        businessName: _nameController.text,
        category: _category,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text,
        whatsapp: _whatsappController.text.trim().isEmpty
            ? null
            : _whatsappController.text,
      );
      if (!mounted) return;
      // Auto-switch to business mode so user lands on seller dashboard
      await AccountModeService.setMode(AppViewMode.business);
      if (!mounted) return;
      setState(() => _approved = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage =
            'Could not submit your application. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_approved) return _ApprovedScreen();
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      appBar: AppBar(
        backgroundColor: AppColors.darkNavy,
        foregroundColor: AppColors.white,
        title: Text(
          'Apply for Business',
          style: AppTextStyles.titleLarge.copyWith(
            color: AppColors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _IntroCard(),
                const SizedBox(height: 20),
                _Label('Business name'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: _decoration(hint: 'e.g. Tanatswa Crafts'),
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.length < 2) return 'Enter your business name.';
                    if (v.length > 80) return 'Keep it under 80 characters.';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _Label('WhatsApp number (for review contact)'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _whatsappController,
                  keyboardType: TextInputType.phone,
                  decoration: _decoration(hint: '+263 77 123 4567'),
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return null;
                    // Allow +, digits, spaces, dashes. 7+ digits min.
                    final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digits.length < 7) {
                      return 'Enter a valid phone number.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _Label('Category'),
                const SizedBox(height: 8),
                _CategoryPicker(
                  value: _category,
                  onChanged: (v) => setState(() => _category = v),
                ),
                const SizedBox(height: 20),
                _Label('Tell us about your business (optional)'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 4,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _decoration(
                    hint: 'What do you sell? Where are you based? '
                        'How long have you been doing this?',
                  ),
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.length > 600) {
                      return 'Keep it under 600 characters.';
                    }
                    return null;
                  },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _errorMessage!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.red,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _SubmitButton(
                  loading: _submitting,
                  onTap: _submit,
                ),
                const SizedBox(height: 14),
                Text(
                  'Your account is upgraded instantly. You can list products as soon as you submit.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.bodyMedium.copyWith(
        color: const Color.fromRGBO(26, 26, 46, 0.45),
      ),
      filled: true,
      fillColor: AppColors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color.fromRGBO(26, 26, 46, 0.10),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color.fromRGBO(26, 26, 46, 0.10),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: AppColors.primaryBlue,
          width: 1.5,
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.business_center,
              color: AppColors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upgrade to Business',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'A business account lets you list products in the '
                  'marketplace and claim ownership of a church listing. '
                  'Activated instantly.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.white.withValues(alpha: 0.9),
                    height: 1.35,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.titleMedium.copyWith(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: AppColors.textDark,
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color.fromRGBO(26, 26, 46, 0.10)),
      ),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        items: [
          for (final c in _ApplyBusinessScreenState._categories)
            DropdownMenuItem(
              value: c,
              child: Text(c, style: AppTextStyles.bodyMedium),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: AppColors.white,
                        strokeWidth: 2.4,
                      ),
                    )
                  : Text(
                      'Submit application',
                      style: AppTextStyles.buttonText.copyWith(
                        fontSize: 15,
                        letterSpacing: 0.4,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Full-screen success state shown after business account is approved.
/// Replaces the form so the user cannot re-submit. Offers a single CTA
/// to go set up their store.
class _ApprovedScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.30),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  color: AppColors.white,
                  size: 52,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                "You're a business!",
                style: AppTextStyles.headlineMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Your business account is active. Set up your store to start listing products on the marketplace.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.65),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              _ApprovedButton(
                label: 'Set up my store',
                icon: Icons.storefront_outlined,
                onTap: () => context.goNamed('marketplace_guidelines'),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => context.goNamed('seller_dashboard'),
                child: Text(
                  'Go to seller dashboard',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovedButton extends StatelessWidget {
  const _ApprovedButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: AppColors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: AppTextStyles.buttonText.copyWith(fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
