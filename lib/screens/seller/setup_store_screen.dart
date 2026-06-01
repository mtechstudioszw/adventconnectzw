import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../models/seller_model.dart';
import '../../services/seller_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// The "Open a store" form. Self-serve as of patch_022 — anyone
/// authenticated can publish a storefront after accepting the
/// Marketplace Code of Conduct. The accepted code [termsVersion]
/// MUST be forwarded from MarketplaceGuidelinesScreen via the
/// route's `extra` arg; the DB constraint rejects approved-status
/// inserts without a terms_accepted_at timestamp.
class SetupStoreScreen extends StatefulWidget {
  const SetupStoreScreen({super.key, required this.termsVersion});

  final String termsVersion;

  @override
  State<SetupStoreScreen> createState() => _SetupStoreScreenState();
}

class _SetupStoreScreenState extends State<SetupStoreScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final _businessNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _cityController = TextEditingController();
  final _suburbController = TextEditingController();
  final _addressController = TextEditingController();
  final _paymentMethodsController = TextEditingController();
  final _deliveryAreaController = TextEditingController();
  final _deliveryFeeController = TextEditingController();
  final _sabbathNoticeController = TextEditingController(
    text:
        '🕊️ This seller observes the Sabbath. Response times may be slower Friday sundown to Saturday sundown.',
  );

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  String? _selectedCategory;
  String? _selectedProvince;
  String? _photoUrl;
  String? _coverUrl;
  bool _offersDelivery = false;
  bool _observesSabbath = false;
  bool _uploading = false;
  bool _uploadingCover = false;
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
  }

  @override
  void dispose() {
    _entrance.dispose();
    _businessNameController.dispose();
    _descriptionController.dispose();
    _contactNameController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    _cityController.dispose();
    _suburbController.dispose();
    _addressController.dispose();
    _paymentMethodsController.dispose();
    _deliveryAreaController.dispose();
    _deliveryFeeController.dispose();
    _sabbathNoticeController.dispose();
    super.dispose();
  }

  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Business name is required';
    if (v.trim().length < 2) return 'Enter a real business name';
    return null;
  }

  String? _validateDescription(String? v) {
    if (v == null || v.trim().isEmpty) return 'Tell buyers what you sell';
    if (v.trim().length < 20) return 'At least 20 characters';
    if (v.length > 600) return 'Keep it under 600 characters';
    return null;
  }

  String? _validatePhone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Phone number is required';
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9) return 'Enter a valid phone number';
    return null;
  }

  String? _validateRequired(String? v, String field) {
    if (v == null || v.trim().isEmpty) return '$field is required';
    return null;
  }

  Future<void> _pickPhoto() async {
    if (_uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final url = await StorageService.pickAndUploadProfilePhoto();
      if (!mounted) return;
      if (url != null) setState(() => _photoUrl = url);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not upload photo. Try again.');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickCoverPhoto() async {
    if (_uploadingCover) return;
    setState(() {
      _uploadingCover = true;
      _error = null;
    });
    try {
      final url = await StorageService.pickAndUploadCoverPhoto();
      if (!mounted) return;
      if (url != null) setState(() => _coverUrl = url);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not upload background. Try again.');
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      setState(() => _error = 'Pick a category for your store.');
      return;
    }
    if (_selectedProvince == null) {
      setState(() => _error = 'Pick a province.');
      return;
    }

    setState(() => _saving = true);
    try {
      await SellerService.applyAsSeller(
        businessName: _businessNameController.text,
        category: _selectedCategory!,
        phone: _phoneController.text,
        termsVersion: widget.termsVersion,
        description: _descriptionController.text,
        province: _selectedProvince,
        city: _cityController.text,
        suburb: _suburbController.text,
        address: _addressController.text,
        whatsapp: _whatsappController.text,
        contactName: _contactNameController.text,
        profilePhotoUrl: _photoUrl,
        coverPhotoUrl: _coverUrl,
        paymentMethods: _paymentMethodsController.text,
        offersDelivery: _offersDelivery,
        deliveryArea: _offersDelivery ? _deliveryAreaController.text : null,
        deliveryFee: _offersDelivery ? _deliveryFeeController.text : null,
        observesSabbath: _observesSabbath,
        sabbathNoticeText:
            _observesSabbath ? _sabbathNoticeController.text : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Store created — your dashboard is ready!',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      // Use go() instead of goNamed() so the dashboard is always
      // rebuilt fresh. setup_store is a child of /seller, so
      // goNamed('seller_dashboard') would reuse the existing parent
      // widget without re-running initState — the store status would
      // stay as "no seller row" until the user navigated away.
      context.go('/seller');
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
            _buildHero(),
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
                      _IntroCard(),
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Business profile',
                        subtitle:
                            'How buyers will recognise you on the marketplace.',
                        child: Column(
                          children: [
                            _PhotoTile(
                              photoUrl: _photoUrl,
                              uploading: _uploading,
                              onTap: _pickPhoto,
                            ),
                            const SizedBox(height: 14),
                            _CoverTile(
                              photoUrl: _coverUrl,
                              uploading: _uploadingCover,
                              onTap: _pickCoverPhoto,
                            ),
                            const SizedBox(height: 18),
                            _LabeledField(
                              label: 'Business name',
                              child: _Input(
                                controller: _businessNameController,
                                hint: 'Tendai Crafts',
                                icon: Icons.storefront_outlined,
                                validator: _validateName,
                                textCapitalization: TextCapitalization.words,
                              ),
                            ),
                            const SizedBox(height: 18),
                            _LabeledField(
                              label: 'Category',
                              child: _CategoryPicker(
                                selected: _selectedCategory,
                                onChanged: (id) =>
                                    setState(() => _selectedCategory = id),
                              ),
                            ),
                            const SizedBox(height: 18),
                            _LabeledField(
                              label: 'Description',
                              helper:
                                  '${_descriptionController.text.length}/600',
                              child: TextFormField(
                                controller: _descriptionController,
                                validator: _validateDescription,
                                maxLength: 600,
                                maxLines: 4,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                onChanged: (_) => setState(() {}),
                                style: AppTextStyles.bodyLarge
                                    .copyWith(fontSize: 15),
                                decoration: _filledDecoration(
                                  icon: Icons.notes_outlined,
                                  hint:
                                      'A short pitch — what you sell and why people buy from you.',
                                ).copyWith(counterText: ''),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Location',
                        subtitle:
                            'Buyers see your province + city on listings.',
                        child: Column(
                          children: [
                            _LabeledField(
                              label: 'Province',
                              child: _ProvincePicker(
                                selected: _selectedProvince,
                                onChanged: (v) =>
                                    setState(() => _selectedProvince = v),
                              ),
                            ),
                            const SizedBox(height: 18),
                            _LabeledField(
                              label: 'City / town',
                              child: _Input(
                                controller: _cityController,
                                hint: 'Harare',
                                icon: Icons.location_city_outlined,
                                validator: (v) =>
                                    _validateRequired(v, 'City'),
                                textCapitalization: TextCapitalization.words,
                              ),
                            ),
                            const SizedBox(height: 18),
                            _LabeledField(
                              label: 'Suburb (optional)',
                              child: _Input(
                                controller: _suburbController,
                                hint: 'Avondale',
                                icon: Icons.place_outlined,
                                textCapitalization: TextCapitalization.words,
                              ),
                            ),
                            const SizedBox(height: 18),
                            _LabeledField(
                              label: 'Physical address (optional)',
                              child: _Input(
                                controller: _addressController,
                                hint: 'Shop number, street',
                                icon: Icons.home_outlined,
                                textCapitalization:
                                    TextCapitalization.sentences,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Contact',
                        subtitle: 'How buyers reach you to place orders.',
                        child: Column(
                          children: [
                            _LabeledField(
                              label: 'Contact name (optional)',
                              child: _Input(
                                controller: _contactNameController,
                                hint: 'Tendai Moyo',
                                icon: Icons.person_outline,
                                textCapitalization: TextCapitalization.words,
                              ),
                            ),
                            const SizedBox(height: 18),
                            _LabeledField(
                              label: 'Phone number',
                              child: _Input(
                                controller: _phoneController,
                                hint: '+263 77 123 4567',
                                icon: Icons.phone_outlined,
                                keyboardType: TextInputType.phone,
                                validator: _validatePhone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9+\s\-]'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            _LabeledField(
                              label: 'WhatsApp number (optional)',
                              child: _Input(
                                controller: _whatsappController,
                                hint: '+263 77 123 4567',
                                icon: Icons.chat_bubble_outline,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9+\s\-]'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            _LabeledField(
                              label: 'Payment methods (optional)',
                              child: _Input(
                                controller: _paymentMethodsController,
                                hint: 'EcoCash, bank transfer, cash',
                                icon: Icons.payments_outlined,
                                textCapitalization:
                                    TextCapitalization.sentences,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Delivery',
                        subtitle: 'Tell buyers if you deliver to them.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ToggleRow(
                              value: _offersDelivery,
                              onChanged: (v) =>
                                  setState(() => _offersDelivery = v),
                              title: 'I offer delivery',
                              subtitle:
                                  'Adds a delivery badge to your listings.',
                              icon: Icons.local_shipping_outlined,
                            ),
                            if (_offersDelivery) ...[
                              const SizedBox(height: 18),
                              _LabeledField(
                                label: 'Delivery area',
                                child: _Input(
                                  controller: _deliveryAreaController,
                                  hint: 'Greater Harare',
                                  icon: Icons.map_outlined,
                                  textCapitalization: TextCapitalization.words,
                                ),
                              ),
                              const SizedBox(height: 18),
                              _LabeledField(
                                label: 'Delivery fee',
                                child: _Input(
                                  controller: _deliveryFeeController,
                                  hint: r'$5 within CBD, $10 suburbs',
                                  icon: Icons.attach_money_outlined,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Sabbath observance',
                        subtitle:
                            'Adds a gentle badge that lets buyers know your hours.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ToggleRow(
                              value: _observesSabbath,
                              onChanged: (v) =>
                                  setState(() => _observesSabbath = v),
                              title: 'I observe the Sabbath',
                              subtitle:
                                  'Friday sundown to Saturday sundown.',
                              icon: Icons.brightness_3_outlined,
                            ),
                            if (_observesSabbath) ...[
                              const SizedBox(height: 18),
                              _LabeledField(
                                label: 'Sabbath notice',
                                child: TextFormField(
                                  controller: _sabbathNoticeController,
                                  maxLines: 3,
                                  maxLength: 200,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  style: AppTextStyles.bodyLarge
                                      .copyWith(fontSize: 15),
                                  decoration: _filledDecoration(
                                    icon: Icons.info_outline,
                                    hint: 'Shown next to your listings.',
                                  ).copyWith(counterText: ''),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        _ErrorBanner(message: _error!),
                      ],
                      const SizedBox(height: 24),
                      _GradientButton(
                        label: _saving
                            ? 'Submitting...'
                            : 'Submit application',
                        busy: _saving,
                        onTap: _saving ? null : _submit,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'We review applications within 1–3 business days.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: const Color.fromRGBO(26, 26, 46, 0.55),
                        ),
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

  Widget _buildHero() {
    return ClipPath(
      clipper: _HeroClipper(),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _CircleBackButton(
                      onTap: () => context.canPop()
                          ? context.pop()
                          : context.goNamed('profile'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BECOME A SELLER',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Open your storefront',
                        style: AppTextStyles.displayMedium.copyWith(
                          color: AppColors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tell us about your business — we\'ll review and approve.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _filledDecoration({
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

class _HeroClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 28);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 28,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _CircleBackButton extends StatelessWidget {
  const _CircleBackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.10)),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new,
            size: 14,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.storefront,
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
                  'What happens next?',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Fill the form. We review within 1–3 days. Once approved your dashboard unlocks and you can list products.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.65),
                    height: 1.5,
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTextStyles.bodySmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.6),
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
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
                color: const Color.fromRGBO(26, 26, 46, 0.65),
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
                  color: const Color.fromRGBO(26, 26, 46, 0.45),
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
    this.keyboardType,
    this.validator,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
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
        fillColor: context.palette.inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: Color.fromRGBO(26, 26, 46, 0.06)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: Color.fromRGBO(26, 26, 46, 0.06)),
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

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: SellerCategory.all.map((c) {
        final active = c.id == selected;
        return InkWell(
          onTap: () => onChanged(c.id),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: active ? AppColors.primaryGradient : null,
              color: active ? null : context.palette.chipBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active
                    ? AppColors.primaryBlue
                    : const Color.fromRGBO(26, 26, 46, 0.08),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c.icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  c.label,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: active ? AppColors.white : AppColors.textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ProvincePicker extends StatelessWidget {
  const _ProvincePicker({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: selected,
      isExpanded: true,
      icon: const Icon(
        Icons.expand_more,
        color: Color.fromRGBO(26, 26, 46, 0.5),
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
        fillColor: context.palette.inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: Color.fromRGBO(26, 26, 46, 0.06)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: Color.fromRGBO(26, 26, 46, 0.06)),
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
          color: const Color.fromRGBO(26, 26, 46, 0.5),
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

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photoUrl,
    required this.uploading,
    required this.onTap,
  });

  final String? photoUrl;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return Row(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: hasPhoto ? null : AppColors.primaryGradient,
            color: hasPhoto ? AppColors.lightGrey : null,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
            image: hasPhoto
                ? DecorationImage(
                    image: CachedNetworkImageProvider(photoUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: hasPhoto
              ? null
              : const Icon(
                  Icons.storefront,
                  color: AppColors.white,
                  size: 32,
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Store logo / photo',
                style: AppTextStyles.titleSmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hasPhoto
                    ? 'Looks great. Tap change to swap it.'
                    : 'Optional — a logo or shopfront photo.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.6),
                ),
              ),
            ],
          ),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: uploading ? null : onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primaryBlue.withValues(alpha: 0.4),
                ),
              ),
              child: uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryBlue,
                      ),
                    )
                  : Text(
                      hasPhoto ? 'Change' : 'Upload',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CoverTile extends StatelessWidget {
  const _CoverTile({
    required this.photoUrl,
    required this.uploading,
    required this.onTap,
  });

  final String? photoUrl;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: uploading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            color: context.palette.cardMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color.fromRGBO(26, 26, 46, 0.08),
            ),
            image: hasPhoto
                ? DecorationImage(
                    image: CachedNetworkImageProvider(photoUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          alignment: Alignment.center,
          child: uploading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.primaryBlue,
                  ),
                )
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.image_outlined,
                        color: AppColors.primaryBlue,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hasPhoto
                            ? 'Change background photo'
                            : 'Add background photo',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w700,
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

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
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
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.primaryBlue,
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
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
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.white,
                        ),
                      )
                    : Text(
                        label,
                        style: AppTextStyles.buttonText.copyWith(
                          fontSize: 15,
                          letterSpacing: 0.4,
                        ),
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
