import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../utils/name_validator.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/support_sheet.dart';
import '../../theme/app_theme.dart';

/// External landing URLs for the legal pages (live Netlify site).
const _termsUrl =
    'https://mtechstudioszw.github.io/adventconnect-legal/terms.html';
const _privacyUrl =
    'https://mtechstudioszw.github.io/adventconnect-legal/privacy.html';

Future<void> _openLegalUrl(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// Unified login + signup surface. The user enters an email; we ask
/// Supabase whether an account exists for it; based on that we reveal
/// either the login password field or the full signup form.
///
/// `birthDate` is forwarded from the age-verification step. It's
/// required to *create* a new account but ignored for logins.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.birthDate});

  final DateTime? birthDate;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _Stage { email, login, signup }

class _AuthScreenState extends State<AuthScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();

  late final FocusNode _emailFocus;
  late final FocusNode _passwordFocus;
  late final FocusNode _nameFocus;
  late final FocusNode _surnameFocus;

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  _Stage _stage = _Stage.email;
  bool _checking = false;
  bool _submitting = false;
  bool _googleBusy = false;
  bool _appleBusy = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptedTerms = false;
  String? _error;

  DateTime? _birthDate;

  @override
  void initState() {
    super.initState();
    _emailFocus = FocusNode();
    _passwordFocus = FocusNode();
    _nameFocus = FocusNode();
    _surnameFocus = FocusNode();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 16, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic),
    );
    _birthDate = widget.birthDate;
    _loadStoredBirthDate();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _emailFocus.requestFocus(),
    );
  }

  Future<void> _loadStoredBirthDate() async {
    if (_birthDate != null) return;
    final stored = await AuthService.getStoredBirthDate();
    if (!mounted || stored == null) return;
    setState(() => _birthDate = stored);
  }

  @override
  void dispose() {
    _entrance.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _nameController.dispose();
    _surnameController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _nameFocus.dispose();
    _surnameFocus.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!regex.hasMatch(v.trim())) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (_stage == _Stage.signup && v.length < 8) {
      return 'At least 8 characters';
    }
    return null;
  }

  String? _validateConfirm(String? v) {
    if (_stage != _Stage.signup) return null;
    if (v == null || v.isEmpty) return 'Confirm your password';
    if (v != _passwordController.text) return 'Passwords don\'t match';
    return null;
  }

  String? _validateName(String? v) {
    if (_stage != _Stage.signup) return null;
    return NameValidator.namePart(v, 'First name');
  }

  String? _validateSurname(String? v) {
    if (_stage != _Stage.signup) return null;
    return NameValidator.namePart(v, 'Surname');
  }

  Future<void> _onContinue() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _emailController.text.trim();
    setState(() => _checking = true);

    // Pull both presence + provider mix in parallel. providers is the
    // authoritative existence signal — the RPC joins auth.identities
    // → auth.users, so a non-empty result inherently means the
    // account exists. We fall back to email_exists only when
    // providers is null (RPC failed / rate-limited). Previously we
    // gated isOAuthOnly on `exists == true`, which meant ONE failing
    // RPC made us silently drop a Google user into the sign-up form
    // (the bug "asked me for name + create password despite having
    // a Google account").
    final results = await Future.wait([
      AuthService.emailExists(email),
      AuthService.emailAuthProviders(email),
    ]);
    if (!mounted) return;
    final exists = results[0] as bool?;
    final providers = results[1] as List<String>?;

    final hasProviders = providers != null && providers.isNotEmpty;
    final accountExists = hasProviders || exists == true;

    // OAuth-only case: account exists but no email/password identity.
    // Offer two routes — keep tapping the Google button (existing
    // behaviour) OR verify with an emailed 6-digit code that links
    // an email/password identity to the same auth.users row. Claude
    // does the same thing.
    final isOAuthOnly = hasProviders && !providers.contains('email');
    if (isOAuthOnly) {
      setState(() => _checking = false);
      HapticFeedback.heavyImpact();
      await _showLinkOptionsSheet(email);
      return;
    }

    // Both RPCs failed (rate limit / network). Don't silently default
    // to signup — that's how a returning user ends up creating a
    // duplicate account. Stay on the email stage and tell them.
    if (exists == null && providers == null) {
      setState(() {
        _checking = false;
        _error = 'Couldn\'t verify this email right now. '
            'Try Continue with Google above, or try again in a minute.';
      });
      HapticFeedback.heavyImpact();
      return;
    }

    final next = accountExists ? _Stage.login : _Stage.signup;
    setState(() {
      _checking = false;
      _stage = next;
    });
    HapticFeedback.selectionClick();
    Future.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      if (_stage == _Stage.signup) {
        _nameFocus.requestFocus();
      } else {
        _passwordFocus.requestFocus();
      }
    });
  }

  Future<void> _onLogin() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final result = await AuthService.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isSuccess) {
      HapticFeedback.mediumImpact();
      context.goNamed('home');
      return;
    }
    final message = (result.errorMessage ?? '').toLowerCase();
    if (message.contains('email') && message.contains('confirm')) {
      context.goNamed(
        'email_verification',
        extra: _emailController.text.trim(),
      );
      return;
    }
    if (message.contains('incorrect') || message.contains('invalid')) {
      // Concrete "is this email actually Google-only?" check rather
      // than a hand-wavy "if you signed up with Google" hint. The
      // generic copy used to confuse users with mistyped passwords
      // because it always suggested Google. Now we only push them
      // toward Google when we can confirm the email's only identity
      // is Google.
      final providers = await AuthService.emailAuthProviders(
        _emailController.text.trim(),
      );
      if (!mounted) return;
      final isGoogleOnly = providers != null &&
          providers.contains('google') &&
          !providers.contains('email');
      if (isGoogleOnly) {
        HapticFeedback.heavyImpact();
        await _showLinkOptionsSheet(_emailController.text.trim());
        return;
      }
      setState(() => _error = 'That password didn\'t match. Try again.');
      return;
    }
    setState(() => _error = result.errorMessage);
  }

  /// Shown when the user types an email tied only to Google. Lets
  /// them either tap through to Google sign-in OR receive a 6-digit
  /// code by email — the OTP path proves inbox control and lets the
  /// user (optionally) attach a password for next time.
  Future<void> _showLinkOptionsSheet(String email) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GoogleLinkSheet(
        email: email,
        onUseGoogle: () {
          Navigator.of(ctx).pop();
          _onGoogle();
        },
        onUseOtp: () async {
          Navigator.of(ctx).pop();
          await _startOtpLinkFlow(email);
        },
      ),
    );
  }

  /// Send a 6-digit code and route to the OTP entry sheet. The
  /// service-side method handles rate-limit + SMTP failures with
  /// friendly copy.
  Future<void> _startOtpLinkFlow(String email) async {
    setState(() {
      _checking = true;
      _error = null;
    });
    final sent = await AuthService.sendEmailLoginOtp(email);
    if (!mounted) return;
    setState(() => _checking = false);
    if (!sent.isSuccess) {
      setState(() => _error = sent.errorMessage);
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.mediumImpact();
    final verified = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (ctx) => _OtpLinkSheet(email: email),
    );
    if (!mounted) return;
    if (verified == true) {
      final hasProfile = await AuthService.hasCompletedProfileSetup();
      if (!mounted) return;
      context.goNamed(hasProfile ? 'home' : 'profile_setup');
    }
  }

  Future<void> _onSignup() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_acceptedTerms) {
      setState(() => _error =
          'Please accept the Terms & Conditions to create your account.');
      return;
    }
    final birthDate = _birthDate ?? await AuthService.getStoredBirthDate();
    if (!mounted) return;
    if (birthDate == null) {
      setState(() => _error = 'Please pick your date of birth.');
      return;
    }
    if (!AuthService.meetsMinimumAge(birthDate)) {
      setState(() => _error =
          'You must be at least 16 years old to create an account.');
      return;
    }
    setState(() {
      _submitting = true;
      _birthDate = birthDate;
    });
    await AuthService.markAgeVerified(birthDate);
    final result = await AuthService.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      fullName: NameValidator.combine(
        _nameController.text,
        _surnameController.text,
      ),
      birthDate: birthDate,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isSuccess) {
      HapticFeedback.mediumImpact();
      context.goNamed(
        'email_verification',
        extra: _emailController.text.trim(),
      );
      return;
    }
    final message = (result.errorMessage ?? '').toLowerCase();
    if (message.contains('already exists') ||
        message.contains('already registered') ||
        message.contains('try logging in')) {
      // Check if this email is Google-only before pushing to login
      final providers = await AuthService.emailAuthProviders(
        _emailController.text.trim(),
      );
      if (!mounted) return;
      final isGoogleOnly = providers != null &&
          providers.contains('google') &&
          !providers.contains('email');
      if (isGoogleOnly) {
        setState(() {
          _stage = _Stage.email;
          _passwordController.clear();
          _confirmController.clear();
          _error = null;
        });
        HapticFeedback.heavyImpact();
        await _showLinkOptionsSheet(_emailController.text.trim());
        return;
      }
      setState(() {
        _stage = _Stage.login;
        _passwordController.clear();
        _confirmController.clear();
        _error =
            'Looks like you already have an account — enter your password '
            'to log in.';
      });
      Future.delayed(const Duration(milliseconds: 280), () {
        if (mounted) _passwordFocus.requestFocus();
      });
      return;
    }
    setState(() => _error = result.errorMessage);
  }

  /// BUG 2 FIX — _onGoogle now receives meaningful errors from
  /// AuthService.signInWithGoogle() when the email already exists as
  /// an email/password account. Those errors are surfaced directly so
  /// the user knows to sign in with their password instead.
  Future<void> _onGoogle() async {
    setState(() {
      _error = null;
      _googleBusy = true;
    });
    final result = await AuthService.signInWithGoogle();
    if (!mounted) return;
    if (!result.isSuccess) {
      setState(() => _googleBusy = false);
      // Silent cancel — user dismissed the Google picker, not an error.
      if (result.errorMessage == 'Sign in cancelled.') return;
      setState(() => _error = result.errorMessage);
      return;
    }

    // Returning user (already has a profiles row) → straight to home.
    // New Google user → age verification → profile-setup onboarding.
    final hasProfile = await AuthService.hasCompletedProfileSetup();
    if (!mounted) return;
    if (hasProfile) {
      HapticFeedback.mediumImpact();
      setState(() => _googleBusy = false);
      context.goNamed('home');
      return;
    }

    // New user — collect birth date for age verification before the
    // profile setup flow. Cancel or underage → sign back out.
    final dob = await _pickBirthDateForGoogleSignup();
    if (!mounted) return;
    if (dob == null) {
      await AuthService.signOut();
      if (!mounted) return;
      setState(() {
        _googleBusy = false;
        _error = 'Date of birth is required to create an account.';
      });
      return;
    }
    final age = _ageInYears(dob);
    if (age < 13) {
      await AuthService.signOut();
      if (!mounted) return;
      setState(() {
        _googleBusy = false;
        _error = 'You must be at least 13 to use Adventist Super App.';
      });
      return;
    }
    await AuthService.markAgeVerified(dob);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _googleBusy = false);
    context.goNamed('profile_setup');
  }

  /// Sign in with Apple — iOS only (see _AppleButton gating). Mirrors
  /// _onGoogle: returning users go home, new users pass age check then
  /// profile setup. Will only succeed once the Apple provider is
  /// configured in Supabase (docs/APPLE_SIGN_IN_SETUP.md); until then
  /// the user just sees a friendly error.
  Future<void> _onApple() async {
    setState(() {
      _error = null;
      _appleBusy = true;
    });
    final result = await AuthService.signInWithApple();
    if (!mounted) return;
    if (!result.isSuccess) {
      setState(() => _appleBusy = false);
      if (result.errorMessage == 'Sign in cancelled.') return;
      setState(() => _error = result.errorMessage);
      return;
    }

    final hasProfile = await AuthService.hasCompletedProfileSetup();
    if (!mounted) return;
    if (hasProfile) {
      HapticFeedback.mediumImpact();
      setState(() => _appleBusy = false);
      context.goNamed('home');
      return;
    }

    final dob = await _pickBirthDateForGoogleSignup();
    if (!mounted) return;
    if (dob == null) {
      await AuthService.signOut();
      if (!mounted) return;
      setState(() {
        _appleBusy = false;
        _error = 'Date of birth is required to create an account.';
      });
      return;
    }
    if (_ageInYears(dob) < 13) {
      await AuthService.signOut();
      if (!mounted) return;
      setState(() {
        _appleBusy = false;
        _error = 'You must be at least 13 to use Adventist Super App.';
      });
      return;
    }
    await AuthService.markAgeVerified(dob);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _appleBusy = false);
    context.goNamed('profile_setup');
  }

  Future<DateTime?> _pickBirthDateForGoogleSignup() async {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(now.year - 110),
      lastDate: now,
      helpText: 'Your date of birth',
      cancelText: 'Cancel',
      confirmText: 'Continue',
      builder: brandPickerBuilder,
    );
  }

  int _ageInYears(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age -= 1;
    }
    return age;
  }

  void _changeEmail() {
    HapticFeedback.selectionClick();
    setState(() {
      _stage = _Stage.email;
      _passwordController.clear();
      _confirmController.clear();
      _nameController.clear();
      _surnameController.clear();
      _acceptedTerms = false;
      _error = null;
    });
    Future.delayed(const Duration(milliseconds: 280), () {
      if (mounted) _emailFocus.requestFocus();
    });
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: 'Date of birth',
      builder: brandPickerBuilder,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _birthDate = picked;
      if (_error != null && _error!.toLowerCase().contains('birth')) {
        _error = null;
      }
    });
    await AuthService.markAgeVerified(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: AnimatedBuilder(
            animation: _entrance,
            builder: (context, child) => Opacity(
              opacity: _fade.value,
              child: Transform.translate(
                offset: Offset(0, _slide.value),
                child: child,
              ),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  const _LogoMark(),
                  const SizedBox(height: 28),
                  Text(
                    _headlineForStage(),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.displayMedium.copyWith(
                      color: context.palette.text,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _subheadlineForStage(),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: context.palette.textMuted,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_stage == _Stage.email) ...[
                    // App Store Guideline 4.8: when a social login is
                    // offered on iOS, Sign in with Apple must be offered
                    // too — and presented at least as prominently, so it
                    // goes ABOVE Google. iOS only; Android stays Google-
                    // only (Apple sign-in isn't expected there).
                    if (Platform.isIOS) ...[
                      _AppleButton(
                        busy: _appleBusy,
                        onTap: (_appleBusy || _submitting) ? null : _onApple,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _GoogleButton(
                      busy: _googleBusy,
                      onTap: (_googleBusy || _submitting) ? null : _onGoogle,
                    ),
                    const SizedBox(height: 20),
                    const _OrDivider(),
                    const SizedBox(height: 20),
                  ],
                  AnimatedSize(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: _buildStageForm(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 18),
                    _ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 24),
                  _PrimaryButton(
                    label: _primaryLabelForStage(),
                    busy: _submitting || _checking,
                    onTap: _submitting || _checking ? null : _onPrimary,
                  ),
                  const SizedBox(height: 18),
                  if (_stage != _Stage.email)
                    Center(
                      child: TextButton(
                        onPressed: _changeEmail,
                        child: Text(
                          'Use a different email',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: context.palette.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  _LegalLine(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _headlineForStage() {
    switch (_stage) {
      case _Stage.email:
        return 'Build community.\nFind your home.';
      case _Stage.login:
        return 'Welcome back';
      case _Stage.signup:
        return 'Create your account';
    }
  }

  String _subheadlineForStage() {
    switch (_stage) {
      case _Stage.email:
        return 'Sign in or create an account — we\'ll figure out which '
            'from your email.';
      case _Stage.login:
        return 'Enter your password to keep going.';
      case _Stage.signup:
        return 'Just a few details and you\'re in.';
    }
  }

  String _primaryLabelForStage() {
    if (_checking) return 'Checking…';
    switch (_stage) {
      case _Stage.email:
        return 'Continue';
      case _Stage.login:
        return _submitting ? 'Signing in…' : 'Log in';
      case _Stage.signup:
        return _submitting ? 'Creating…' : 'Create account';
    }
  }

  void _onPrimary() {
    switch (_stage) {
      case _Stage.email:
        _onContinue();
        break;
      case _Stage.login:
        _onLogin();
        break;
      case _Stage.signup:
        _onSignup();
        break;
    }
  }

  Widget _buildStageForm() {
    switch (_stage) {
      case _Stage.email:
        return _buildEmailStage();
      case _Stage.login:
        return _buildLoginStage();
      case _Stage.signup:
        return _buildSignupStage();
    }
  }

  Widget _buildEmailStage() {
    return Column(
      key: const ValueKey('stage-email'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlowField(
          controller: _emailController,
          focusNode: _emailFocus,
          hint: 'Email address',
          icon: Icons.alternate_email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.go,
          autofillHints: const [AutofillHints.email],
          validator: _validateEmail,
          onSubmitted: (_) => _onContinue(),
        ),
      ],
    );
  }

  Widget _buildLoginStage() {
    return Column(
      key: const ValueKey('stage-login'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EmailRow(
          email: _emailController.text.trim(),
          onEdit: _changeEmail,
        ),
        const SizedBox(height: 14),
        _GlowField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          hint: 'Password',
          icon: Icons.lock_outline,
          obscure: _obscurePassword,
          textInputAction: TextInputAction.go,
          autofillHints: const [AutofillHints.password],
          validator: _validatePassword,
          onSubmitted: (_) => _onLogin(),
          suffix: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: context.palette.textMuted,
              size: 20,
            ),
            onPressed: () => setState(
              () => _obscurePassword = !_obscurePassword,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.pushNamed('forgot_password'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Forgot password?',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        Center(
          child: TextButton.icon(
            onPressed: () =>
                showSupportSheet(context, topic: 'Sign-in problem'),
            icon: Icon(Icons.help_outline,
                size: 16, color: AppColors.textMuted),
            label: Text(
              'Having trouble? Contact support',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignupStage() {
    return Column(
      key: const ValueKey('stage-signup'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EmailRow(
          email: _emailController.text.trim(),
          onEdit: _changeEmail,
        ),
        const SizedBox(height: 14),
        _GlowField(
          controller: _nameController,
          focusNode: _nameFocus,
          hint: 'First name',
          icon: Icons.person_outline,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.givenName],
          validator: _validateName,
        ),
        const SizedBox(height: 14),
        _GlowField(
          controller: _surnameController,
          focusNode: _surnameFocus,
          hint: 'Surname',
          icon: Icons.badge_outlined,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.familyName],
          validator: _validateSurname,
        ),
        const SizedBox(height: 14),
        _GlowField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          hint: 'Password (8+ characters)',
          icon: Icons.lock_outline,
          obscure: _obscurePassword,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          validator: _validatePassword,
          suffix: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: context.palette.textMuted,
              size: 20,
            ),
            onPressed: () => setState(
              () => _obscurePassword = !_obscurePassword,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _GlowField(
          controller: _confirmController,
          hint: 'Confirm password',
          icon: Icons.lock_outline,
          obscure: _obscureConfirm,
          textInputAction: TextInputAction.go,
          validator: _validateConfirm,
          onSubmitted: (_) => _onSignup(),
          suffix: IconButton(
            icon: Icon(
              _obscureConfirm
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: context.palette.textMuted,
              size: 20,
            ),
            onPressed: () => setState(
              () => _obscureConfirm = !_obscureConfirm,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _BirthDateField(
          birthDate: _birthDate,
          onTap: _pickBirthDate,
        ),
        const SizedBox(height: 14),
        _TermsCheckbox(
          value: _acceptedTerms,
          onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
        ),
      ],
    );
  }
}

// =============================================================================
// Sub-widgets
// =============================================================================

class _BirthDateField extends StatelessWidget {
  const _BirthDateField({required this.birthDate, required this.onTap});

  final DateTime? birthDate;
  final VoidCallback onTap;

  static const _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final hasDate = birthDate != null;
    final label = hasDate
        ? '${birthDate!.day} ${_months[birthDate!.month - 1]} ${birthDate!.year}'
        : 'Date of birth';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          decoration: BoxDecoration(
            color: context.palette.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: context.palette.divider,
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 12),
                child: Icon(
                  Icons.cake_outlined,
                  color: context.palette.textMuted,
                  size: 20,
                ),
              ),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 15,
                    color: hasDate
                        ? context.palette.text
                        : context.palette.textMuted,
                    fontWeight:
                        hasDate ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              const Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: AppColors.primaryBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Image.asset(
            'assets/icon/logo.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Container(
        height: 1,
        color: context.palette.divider,
      ),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'OR',
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ),
        line,
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null && !busy ? 0.6 : 1,
      child: Material(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(22),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: context.palette.divider,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: busy
                ? const Center(child: BrandSpinner(size: 22))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _GoogleGlyph(),
                      const SizedBox(width: 12),
                      Text(
                        'Continue with Google',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: context.palette.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Sign in with Apple button. Apple's HIG requires the black-fill +
/// white Apple logo + "Continue with Apple" wording at equal-or-
/// greater prominence than other social buttons. Shown on iOS only.
class _AppleButton extends StatelessWidget {
  const _AppleButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null && !busy ? 0.6 : 1,
      child: Material(
        color: Colors.black,
        borderRadius: BorderRadius.circular(22),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: busy
                ? const Center(
                    child: BrandSpinner(size: 22, color: Colors.white),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.apple, color: Colors.white, size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Continue with Apple',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 22,
      height: 22,
      child: Image(
        image: AssetImage('assets/icon/google.png'),
        fit: BoxFit.contain,
      ),
    );
  }
}

class _GlowField extends StatefulWidget {
  const _GlowField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.focusNode,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_GlowField> createState() => _GlowFieldState();
}

class _GlowFieldState extends State<_GlowField> {
  late FocusNode _focus;
  bool _ownsFocus = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    _ownsFocus = widget.focusNode == null;
    _focus.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_handleFocus);
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : [],
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focus,
        obscureText: widget.obscure,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        autofillHints: widget.autofillHints,
        validator: widget.validator,
        onFieldSubmitted: widget.onSubmitted,
        style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: context.palette.textMuted,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 18, right: 12),
            child: Icon(
              widget.icon,
              color: _focused
                  ? AppColors.primaryBlue
                  : context.palette.textMuted,
              size: 20,
            ),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 48, minHeight: 48),
          suffixIcon: widget.suffix,
          filled: true,
          fillColor: context.palette.inputFill,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(
              color: context.palette.divider,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(
              color: context.palette.divider,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(
              color: AppColors.primaryBlue,
              width: 1.6,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: AppColors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: AppColors.red, width: 1.6),
          ),
        ),
      ),
    );
  }
}

class _EmailRow extends StatelessWidget {
  const _EmailRow({required this.email, required this.onEdit});
  final String email;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.palette.cardMuted,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: context.palette.divider,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.alternate_email,
                color: context.palette.textMuted,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: context.palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'Change',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TermsCheckbox extends StatefulWidget {
  const _TermsCheckbox({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  State<_TermsCheckbox> createState() => _TermsCheckboxState();
}

class _TermsCheckboxState extends State<_TermsCheckbox> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = () => _openLegalUrl(_termsUrl);
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => _openLegalUrl(_privacyUrl);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final linkStyle = AppTextStyles.bodySmall.copyWith(
      color: AppColors.primaryBlue,
      fontWeight: FontWeight.w700,
      fontSize: 13,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.primaryBlue.withValues(alpha: 0.4),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => widget.onChanged(!widget.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: widget.value
                    ? AppColors.primaryBlue
                    : context.palette.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.value
                      ? AppColors.primaryBlue
                      : context.palette.divider,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              // Check glyph sits on primaryBlue when value=true — keep white.
              // TODO(dark-mode): const Icon — stays white on primaryBlue fill.
              child: widget.value
                  ? const Icon(
                      Icons.check,
                      size: 14,
                      color: AppColors.white,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text.rich(
                TextSpan(
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                    fontSize: 13,
                    height: 1.45,
                  ),
                  children: [
                    TextSpan(
                      text: 'I agree to the ',
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => widget.onChanged(!widget.value),
                    ),
                    TextSpan(
                      text: 'Terms & Conditions',
                      style: linkStyle,
                      recognizer: _termsTap,
                    ),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: linkStyle,
                      recognizer: _privacyTap,
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null && !busy ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.32),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              child: busy
                  ? const BrandSpinner(size: 22, color: AppColors.white)
                  : Text(
                      label,
                      style: AppTextStyles.buttonText.copyWith(
                        fontSize: 15.5,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, color: AppColors.red, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.red,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalLine extends StatefulWidget {
  @override
  State<_LegalLine> createState() => _LegalLineState();
}

class _LegalLineState extends State<_LegalLine> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = () => _openLegalUrl(_termsUrl);
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => _openLegalUrl(_privacyUrl);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppTextStyles.labelSmall.copyWith(
      color: context.palette.textMuted,
      fontSize: 11,
      height: 1.45,
    );
    final link = base.copyWith(
      color: AppColors.primaryBlue,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.primaryBlue.withValues(alpha: 0.4),
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text.rich(
          TextSpan(
            style: base,
            children: [
              const TextSpan(text: 'By continuing you agree to the '),
              TextSpan(
                text: 'Terms & Conditions',
                style: link,
                recognizer: _termsTap,
              ),
              const TextSpan(text: ' and '),
              TextSpan(
                text: 'Privacy Policy',
                style: link,
                recognizer: _privacyTap,
              ),
              const TextSpan(text: '.'),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}


/// Bottom sheet shown when the user types an email tied only to a
/// Google account. Gives them two ways forward: tap Google (the
/// historical happy path) or verify with an emailed 6-digit code
/// (Claude-style — proves inbox control without needing Google).
class _GoogleLinkSheet extends StatelessWidget {
  const _GoogleLinkSheet({
    required this.email,
    required this.onUseGoogle,
    required this.onUseOtp,
  });

  final String email;
  final VoidCallback onUseGoogle;
  final VoidCallback onUseOtp;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: context.palette.sheet,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.palette.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.info_outline,
                      color: AppColors.primaryBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This email is signed in with Google',
                      style: AppTextStyles.titleLarge.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '$email already has an account through Google. Pick how '
                'you\'d like to sign in — either continue with Google or '
                'we can email you a 6-digit code to verify it\'s you.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: context.palette.textMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              _PrimaryButton(
                label: 'Continue with Google',
                busy: false,
                onTap: onUseGoogle,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onUseOtp,
                icon: const Icon(
                  Icons.mark_email_read_outlined,
                  color: AppColors.primaryBlue,
                ),
                label: Text(
                  'Email me a code instead',
                  style: AppTextStyles.buttonText.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  side: BorderSide(
                    color: AppColors.primaryBlue.withValues(alpha: 0.40),
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

/// Stateful bottom sheet that collects the 6-digit code emailed by
/// `AuthService.sendEmailLoginOtp`, then verifies it. On success the
/// user is signed in to the same auth.users row the Google identity
/// is attached to; the sheet then offers to set a password so the
/// next login can skip the email round-trip.
class _OtpLinkSheet extends StatefulWidget {
  const _OtpLinkSheet({required this.email});

  final String email;

  @override
  State<_OtpLinkSheet> createState() => _OtpLinkSheetState();
}

class _OtpLinkSheetState extends State<_OtpLinkSheet> {
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _verifying = false;
  bool _settingPassword = false;
  bool _verified = false;
  bool _resending = false;
  bool _obscurePassword = true;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    final result = await AuthService.verifyEmailLoginOtp(
      email: widget.email,
      token: code,
    );
    if (!mounted) return;
    if (!result.isSuccess) {
      setState(() {
        _verifying = false;
        _error = result.errorMessage;
      });
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _verifying = false;
      _verified = true;
    });
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0 || _resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    final result = await AuthService.sendEmailLoginOtp(widget.email);
    if (!mounted) return;
    setState(() => _resending = false);
    if (!result.isSuccess) {
      setState(() => _error = result.errorMessage);
      return;
    }
    // 60s cool-down to keep users from spamming the SMTP quota.
    setState(() => _resendCooldown = 60);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendCooldown -= 1);
      if (_resendCooldown <= 0) t.cancel();
    });
  }

  Future<void> _setPassword() async {
    final pw = _passwordController.text;
    if (pw.length < 8) {
      setState(() => _error = 'At least 8 characters.');
      return;
    }
    setState(() {
      _settingPassword = true;
      _error = null;
    });
    final result = await AuthService.setPasswordForOtpUser(pw);
    if (!mounted) return;
    setState(() => _settingPassword = false);
    if (!result.isSuccess) {
      // Don't block the user — they're already signed in. Show the
      // error inline but let them continue with Skip.
      setState(() => _error = result.errorMessage);
      return;
    }
    Navigator.of(context).pop(true);
  }

  void _skip() {
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: context.palette.sheet,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.palette.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (!_verified) ..._buildCodeStep(context),
              if (_verified) ..._buildPasswordStep(context),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.red,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCodeStep(BuildContext context) {
    return [
      Text(
        'Enter the 6-digit code',
        style: AppTextStyles.titleLarge.copyWith(
          fontWeight: FontWeight.w800,
          fontSize: 17,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'We sent it to ${widget.email}. The code expires in a few '
        'minutes.',
        style: AppTextStyles.bodyMedium.copyWith(
          color: context.palette.textMuted,
          height: 1.45,
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _codeController,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 6,
        autofocus: true,
        style: AppTextStyles.displayMedium.copyWith(
          fontSize: 22,
          letterSpacing: 8,
          fontWeight: FontWeight.w700,
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          hintText: '000000',
          counterText: '',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      const SizedBox(height: 14),
      _PrimaryButton(
        label: 'Verify and sign in',
        busy: _verifying,
        onTap: _verifying ? null : _verify,
      ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: _resendCooldown > 0 || _resending ? null : _resend,
        child: Text(
          _resending
              ? 'Sending…'
              : _resendCooldown > 0
                  ? 'Resend in ${_resendCooldown}s'
                  : 'Didn\'t get it? Resend code',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.primaryBlue,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildPasswordStep(BuildContext context) {
    return [
      Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.successGreen.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppColors.successGreen,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'You\'re signed in',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        'Set a password so you can sign in directly next time without '
        'waiting for an email — totally optional.',
        style: AppTextStyles.bodyMedium.copyWith(
          color: context.palette.textMuted,
          height: 1.45,
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        // Force the alphanumeric password keyboard — without this it could
        // inherit the numeric keyboard from the preceding 6-digit code step.
        keyboardType: TextInputType.text,
        enableSuggestions: false,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: 'New password (at least 8 characters)',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility : Icons.visibility_off,
            ),
            onPressed: () => setState(
              () => _obscurePassword = !_obscurePassword,
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      _PrimaryButton(
        label: 'Save password',
        busy: _settingPassword,
        onTap: _settingPassword ? null : _setPassword,
      ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: _skip,
        child: Text(
          'Skip for now',
          style: AppTextStyles.bodyMedium.copyWith(
            color: context.palette.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ];
  }
}
