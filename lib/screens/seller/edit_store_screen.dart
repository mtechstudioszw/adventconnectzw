import 'package:flutter/material.dart';
import '../../widgets/screen_shell.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../models/seller_model.dart';
import '../../services/seller_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/motion/brand_spinner.dart';

/// Post-approval edit screen. Pre-filled from the existing sellers row.
/// Category is shown but not editable — switching category requires
/// admin re-review and is intentionally outside this flow.
class EditStoreScreen extends StatefulWidget {
  const EditStoreScreen({super.key, this.initialSeller});

  /// Optional pre-fetched seller, passed via `extra` from the dashboard
  /// to skip a round-trip. The screen still refetches if it's null.
  final Seller? initialSeller;

  @override
  State<EditStoreScreen> createState() => _EditStoreScreenState();
}

class _EditStoreScreenState extends State<EditStoreScreen>
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
  final _sabbathNoticeController = TextEditingController();

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  Seller? _seller;
  String? _selectedProvince;
  String? _photoUrl;
  String? _coverUrl;
  bool _offersDelivery = false;
  bool _observesSabbath = false;
  bool _isActive = true;
  bool _loading = true;
  bool _uploading = false;
  bool _uploadingCover = false;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(
      begin: 12,
      end: 0,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOut));
    _bootstrap();
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

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final seller =
          widget.initialSeller ?? await SellerService.fetchMySellerProfile();
      if (seller == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'You haven\'t set up a store yet.';
        });
        return;
      }
      _seller = seller;
      _businessNameController.text = seller.businessName;
      _descriptionController.text = seller.description ?? '';
      _contactNameController.text = seller.contactName ?? '';
      _phoneController.text = seller.phone;
      _whatsappController.text = seller.whatsapp ?? '';
      _cityController.text = seller.city ?? '';
      _suburbController.text = seller.suburb ?? '';
      _addressController.text = seller.address ?? '';
      _paymentMethodsController.text = seller.paymentMethods ?? '';
      _deliveryAreaController.text = seller.deliveryArea ?? '';
      _deliveryFeeController.text = seller.deliveryFee ?? '';
      _sabbathNoticeController.text =
          seller.sabbathNoticeText ??
          '🕊️ This seller observes the Sabbath. Response times may be slower Friday sundown to Saturday sundown.';
      _selectedProvince = seller.province;
      _photoUrl = seller.profilePhotoUrl;
      _coverUrl = seller.coverPhotoUrl;
      _offersDelivery = seller.offersDelivery;
      _observesSabbath = seller.observesSabbath;
      _isActive = seller.isActive;
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your store. Pull to retry.';
      });
    }
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

  Future<void> _pickCover() async {
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
        setState(() => _error = 'Could not upload cover photo. Try again.');
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _confirmDeleteStore() async {
    if (_deleting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete this store?', style: AppTextStyles.headlineSmall),
        content: Text(
          'Your store and every product you listed will be removed from the marketplace. This cannot be undone.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: ctx.palette.text,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.labelMedium.copyWith(
                color: ctx.palette.text,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete store', style: AppTextStyles.labelLarge),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await SellerService.deleteMySellerProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Store deleted.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      // Bounce back to the marketplace — the seller dashboard would
      // re-fetch and crash with "store not found" otherwise.
      context.goNamed('marketplace');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = 'Could not delete store. Try again.';
      });
    }
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_seller == null) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProvince == null) {
      setState(() => _error = 'Pick a province.');
      return;
    }

    setState(() => _saving = true);
    try {
      final wasRejected = _seller!.isRejected;
      await SellerService.updateMySellerProfile(
        sellerId: _seller!.id,
        businessName: _businessNameController.text,
        description: _descriptionController.text,
        province: _selectedProvince,
        city: _cityController.text,
        suburb: _suburbController.text,
        address: _addressController.text,
        phone: _phoneController.text,
        whatsapp: _whatsappController.text,
        contactName: _contactNameController.text,
        profilePhotoUrl: _photoUrl,
        coverPhotoUrl: _coverUrl,
        paymentMethods: _paymentMethodsController.text,
        offersDelivery: _offersDelivery,
        deliveryArea: _offersDelivery ? _deliveryAreaController.text : '',
        deliveryFee: _offersDelivery ? _deliveryFeeController.text : '',
        observesSabbath: _observesSabbath,
        sabbathNoticeText: _observesSabbath
            ? _sabbathNoticeController.text
            : '',
        isActive: _isActive,
      );

      // patch_037: when a rejected seller saves new details, also fire
      // seller_reapply so the row flips back into the admin queue
      // (pending or final_review_pending) and the attempt counter
      // bumps. Without this the updated row stayed at status='rejected'
      // and the admin never saw the resubmission.
      Seller? reapplied;
      if (wasRejected) {
        try {
          reapplied = await SellerService.reapplyAsSeller(_seller!.id);
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _saving = false;
            _error = e.toString().replaceFirst('Exception: ', '');
          });
          return;
        }
      }

      if (!mounted) return;
      final isFinalReview = reapplied?.isFinalReviewPending ?? false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            wasRejected
                ? (isFinalReview
                      ? 'Resubmitted — this is your final review.'
                      : 'Resubmitted. An admin will review your details again.')
                : 'Store updated.',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                child: _buildContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: BrandSpinner(size: 30)),
      );
    }
    if (_seller == null) {
      return _ErrorCard(message: _error ?? 'Store not found.');
    }
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CategoryReadonly(category: _seller!.category),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Business profile',
            subtitle: 'How buyers recognise you on the marketplace.',
            child: Column(
              children: [
                _PhotoTile(
                  photoUrl: _photoUrl,
                  uploading: _uploading,
                  onTap: _pickPhoto,
                ),
                const SizedBox(height: 14),
                _CoverPhotoTile(
                  coverUrl: _coverUrl,
                  uploading: _uploadingCover,
                  onTap: _pickCover,
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
                  label: 'Description',
                  helper: '${_descriptionController.text.length}/600',
                  child: TextFormField(
                    controller: _descriptionController,
                    validator: _validateDescription,
                    maxLength: 600,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                    decoration: _filledDecoration(
                      icon: Icons.notes_outlined,
                      hint: 'What you sell and why people buy from you.',
                    ).copyWith(counterText: ''),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Location',
            subtitle: 'Buyers see your province + city on listings.',
            child: Column(
              children: [
                _LabeledField(
                  label: 'Province',
                  child: _ProvincePicker(
                    selected: _selectedProvince,
                    onChanged: (v) => setState(() => _selectedProvince = v),
                  ),
                ),
                const SizedBox(height: 18),
                _LabeledField(
                  label: 'City / town',
                  child: _Input(
                    controller: _cityController,
                    hint: 'Harare',
                    icon: Icons.location_city_outlined,
                    validator: (v) => _validateRequired(v, 'City'),
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
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Contact',
            subtitle: 'How buyers reach you.',
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
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]')),
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
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]')),
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
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Delivery',
            subtitle: 'Tell buyers if you deliver.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ToggleRow(
                  value: _offersDelivery,
                  onChanged: (v) => setState(() => _offersDelivery = v),
                  title: 'I offer delivery',
                  subtitle: 'Adds a delivery badge to your listings.',
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
            subtitle: 'Adds a gentle badge that explains your hours.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ToggleRow(
                  value: _observesSabbath,
                  onChanged: (v) => setState(() => _observesSabbath = v),
                  title: 'I observe the Sabbath',
                  subtitle: 'Friday sundown to Saturday sundown.',
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
                      textCapitalization: TextCapitalization.sentences,
                      style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                      decoration: _filledDecoration(
                        icon: Icons.info_outline,
                        hint: 'Shown alongside your listings.',
                      ).copyWith(counterText: ''),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Store visibility',
            subtitle: 'Pause your store without deleting it.',
            child: _ToggleRow(
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              title: _isActive ? 'Store is active' : 'Store is paused',
              subtitle: _isActive
                  ? 'Your listings are visible on the marketplace.'
                  : 'Buyers see your products as unavailable.',
              icon: _isActive
                  ? Icons.toggle_on_outlined
                  : Icons.toggle_off_outlined,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 24),
          _GradientButton(
            label: _saving ? 'Saving...' : 'Save changes',
            busy: _saving,
            onTap: _saving ? null : _save,
          ),
          const SizedBox(height: 22),
          _DeleteStoreButton(
            busy: _deleting,
            onTap: (_deleting || _saving) ? null : _confirmDeleteStore,
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return const ScreenHero(
      title: 'Edit your storefront',
      tagline: 'Store settings',
      subtitle: 'Update business profile, contact, delivery and Sabbath hours.',
      fallbackRoute: 'seller_dashboard',
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
      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      filled: true,
      fillColor: context.palette.inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
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

class _CategoryReadonly extends StatelessWidget {
  const _CategoryReadonly({required this.category});
  final String category;

  @override
  Widget build(BuildContext context) {
    final label = SellerCategory.labelFor(category);
    final icon = SellerCategory.all
        .firstWhere(
          (c) => c.id == category,
          orElse: () =>
              const SellerCategory(id: 'other', label: 'Other', icon: '✨'),
        )
        .icon;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(icon, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STORE CATEGORY',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: context.palette.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Contact support to change category.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.lock_outline, color: context.palette.textMuted, size: 18),
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
              color: context.palette.textMuted,
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
  const _LabeledField({required this.label, required this.child, this.helper});

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
        prefixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
        filled: true,
        fillColor: context.palette.inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
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
          borderSide: const BorderSide(
            color: AppColors.primaryBlue,
            width: 1.5,
          ),
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

class _ProvincePicker extends StatelessWidget {
  const _ProvincePicker({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: selected,
      isExpanded: true,
      icon: Icon(Icons.expand_more, color: context.palette.textMuted),
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
        prefixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
        filled: true,
        fillColor: context.palette.inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
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
          borderSide: const BorderSide(
            color: AppColors.primaryBlue,
            width: 1.5,
          ),
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
              : const Icon(Icons.storefront, color: AppColors.white, size: 32),
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
                  color: context.palette.textMuted,
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

class _CoverPhotoTile extends StatelessWidget {
  const _CoverPhotoTile({
    required this.coverUrl,
    required this.uploading,
    required this.onTap,
  });

  final String? coverUrl;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasCover = coverUrl != null && coverUrl!.isNotEmpty;
    return Material(
      color: context.palette.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: uploading ? null : onTap,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasCover)
                CachedNetworkImage(
                  imageUrl: coverUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Container(color: context.palette.cardMuted),
                  errorWidget: (context, url, error) => const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.appBarGradient,
                    ),
                  ),
                )
              else
                const DecoratedBox(
                  decoration: BoxDecoration(gradient: AppColors.appBarGradient),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.45),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (uploading)
                const Center(
                  child: CircularProgressIndicator(color: AppColors.white),
                )
              else
                Positioned(
                  left: 12,
                  bottom: 10,
                  right: 12,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.image_outlined,
                          color: AppColors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          hasCover
                              ? 'Tap to change cover photo'
                              : 'Add a cover photo (16:9)',
                          style: AppTextStyles.titleSmall.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
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

class _DeleteStoreButton extends StatelessWidget {
  const _DeleteStoreButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null && !busy ? 0.6 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: AppColors.red,
                      ),
                    )
                  : Text(
                      'Delete store',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.red,
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

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: context.palette.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ],
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
