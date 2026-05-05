import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, this.birthDate});

  final DateTime? birthDate;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  DateTime? _birthDate;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    _birthDate = widget.birthDate;
    _initBirthDate();
  }

  Future<void> _initBirthDate() async {
    if (_birthDate != null) return;
    final stored = await AuthService.getStoredBirthDate();
    if (mounted && stored != null) {
      setState(() => _birthDate = stored);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!regex.hasMatch(value.trim())) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Must be at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(value)) return 'Add an uppercase letter';
    if (!RegExp(r'[0-9]').hasMatch(value)) return 'Add a number';
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Name is required';
    if (value.trim().length < 2) return 'Enter your full name';
    return null;
  }

  Future<void> _submit() async {
    setState(() => _serverError = null);
    if (!_formKey.currentState!.validate()) return;

    if (_birthDate == null) {
      setState(() => _serverError = 'Please verify your age first.');
      return;
    }

    if (!AuthService.meetsMinimumAge(_birthDate!)) {
      setState(() => _serverError = 'You must be at least 13 to sign up.');
      return;
    }

    setState(() => _loading = true);
    final result = await AuthService.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      fullName: _nameController.text.trim(),
      birthDate: _birthDate!,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (result.isSuccess) {
      context.goNamed('home');
    } else {
      setState(() => _serverError = result.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.goNamed('age_verification'),
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      color: AppColors.textDark,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Create account', style: AppTextStyles.displayMedium),
                const SizedBox(height: 8),
                Text(
                  'Join the Advent Connect ZW community.',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.7),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _buildTextField(
                          controller: _nameController,
                          label: 'Full name',
                          hint: 'Tendai Moyo',
                          icon: Icons.person_outline,
                          textInputAction: TextInputAction.next,
                          validator: _validateName,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _emailController,
                          label: 'Email',
                          hint: 'you@example.com',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _passwordController,
                          label: 'Password',
                          hint: '8+ chars, 1 uppercase, 1 number',
                          icon: Icons.lock_outline,
                          obscure: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          validator: _validatePassword,
                          suffix: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: const Color.fromRGBO(26, 26, 46, 0.5),
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _confirmController,
                          label: 'Confirm password',
                          hint: 'Repeat your password',
                          icon: Icons.lock_outline,
                          obscure: _obscureConfirm,
                          textInputAction: TextInputAction.done,
                          validator: _validateConfirm,
                          suffix: IconButton(
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: const Color.fromRGBO(26, 26, 46, 0.5),
                            ),
                            onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _AgeBadge(birthDate: _birthDate),
                      ],
                    ),
                  ),
                ),
                if (_serverError != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppColors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _serverError!,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _GradientButton(
                  label: _loading ? 'Creating account...' : 'Create account',
                  loading: _loading,
                  onPressed: _loading ? null : _submit,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account?',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.7),
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.goNamed('login'),
                      child: Text(
                        'Log in',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    bool obscure = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      validator: validator,
      style: AppTextStyles.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primaryBlue, size: 20),
        suffixIcon: suffix,
      ),
    );
  }
}

class _AgeBadge extends StatelessWidget {
  const _AgeBadge({this.birthDate});

  final DateTime? birthDate;

  @override
  Widget build(BuildContext context) {
    final verified = birthDate != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: verified
            ? AppColors.successGreen.withValues(alpha: 0.08)
            : AppColors.lightGrey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: verified
              ? AppColors.successGreen.withValues(alpha: 0.3)
              : const Color.fromRGBO(26, 26, 46, 0.1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            verified ? Icons.check_circle : Icons.info_outline,
            size: 18,
            color: verified ? AppColors.successGreen : AppColors.primaryBlue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              verified
                  ? 'Age verified — you are 13+'
                  : 'Age verification required',
              style: AppTextStyles.bodySmall.copyWith(
                color: verified
                    ? AppColors.successGreen
                    : AppColors.textDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.6 : 1,
      child: Container(
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
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: AppColors.white,
                        strokeWidth: 2.4,
                      ),
                    )
                  : Text(label, style: AppTextStyles.buttonText),
            ),
          ),
        ),
      ),
    );
  }
}
