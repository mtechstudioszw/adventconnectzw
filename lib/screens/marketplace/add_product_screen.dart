import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/seller_model.dart';
import '../../services/account_mode_service.dart';
import '../../services/account_service.dart';
import '../../models/product_model.dart';
import '../../services/marketplace_service.dart';
import '../../services/seller_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../widgets/post_form_widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AddProductScreen extends StatefulWidget {
  /// Pass an existing [Product] to pre-fill the form and switch to
  /// edit mode. Leave null for a fresh listing.
  const AddProductScreen({super.key, this.initialProduct});

  final Product? initialProduct;

  bool get isEditing => initialProduct != null;

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _subcategoryController = TextEditingController();
  final _locationController = TextEditingController();

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  String _category = 'other';
  String _currency = 'USD';
  String _condition = 'new';
  String? _province;
  bool _saving = false;
  bool _uploadingPhotos = false;
  String? _error;
  final List<String> _photoUrls = [];

  bool _loadingSeller = true;
  Seller? _seller;
  AccountState? _account;

  static const _categories = <String, String>{
    'books': 'Bibles & Books',
    'clothing': 'Clothing',
    'electronics': 'Electronics',
    'food': 'Food',
    'furniture': 'Furniture',
    'services': 'Services',
    'other': 'Other',
  };

  static const _currencies = ['USD', 'ZWL', 'ZAR'];

  static const _conditions = <String, String>{
    'new': 'New',
    'like_new': 'Like new',
    'good': 'Good',
    'fair': 'Fair',
    'for_parts': 'For parts',
  };

  static const _provinces = [
    'Harare',
    'Bulawayo',
    'Manicaland',
    'Mashonaland Central',
    'Mashonaland East',
    'Mashonaland West',
    'Masvingo',
    'Matabeleland North',
    'Matabeleland South',
    'Midlands',
  ];

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
    _loadSeller();
    // Pre-fill form when editing an existing product
    final p = widget.initialProduct;
    if (p != null) {
      _titleController.text = p.title;
      _descriptionController.text = p.description ?? '';
      _priceController.text = p.price == p.price.roundToDouble()
          ? p.price.toStringAsFixed(0)
          : p.price.toStringAsFixed(2);
      _category = p.category ?? 'other';
      _currency = p.currency;
      if (p.imageUrls.isNotEmpty) _photoUrls.addAll(p.imageUrls);
    }
  }

  Future<void> _loadSeller() async {
    try {
      final results = await Future.wait([
        SellerService.fetchMySellerProfile(),
        AccountService.fetchMyAccount(),
      ]);
      if (!mounted) return;
      setState(() {
        _seller = results[0] as Seller?;
        _account = results[1] as AccountState?;
        _loadingSeller = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSeller = false);
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _subcategoryController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final price = double.parse(_priceController.text);
      if (widget.isEditing) {
        // --- Edit mode: update existing product ---
        await SellerService.updateProduct(
          productId: widget.initialProduct!.id,
          title: _titleController.text,
          price: price,
          currency: _currency,
          category: _category,
          description: _descriptionController.text.isEmpty
              ? null
              : _descriptionController.text,
          imageUrls: List.unmodifiable(_photoUrls),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Product updated.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
            ),
          ),
        );
      } else {
        // --- Add mode: create new product ---
        await MarketplaceService.postProduct(
          title: _titleController.text,
          price: price,
          category: _category,
          priceCurrency: _currency,
          description: _descriptionController.text.isEmpty
              ? null
              : _descriptionController.text,
          subcategory: _subcategoryController.text.isEmpty
              ? null
              : _subcategoryController.text,
          condition: _condition,
          province: _province,
          location: _locationController.text.isEmpty
              ? null
              : _locationController.text,
          imageUrls: List.unmodifiable(_photoUrls),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Product listed.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
            ),
          ),
        );
      }
      context.pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = widget.isEditing
              ? 'Could not update the product. Please try again.'
              : 'Could not list the product. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: SingleChildScrollView(
        child: Column(
          children: [
            const PostFormHero(
              kicker: 'NEW LISTING',
              title: 'List a product',
              subtitle: 'Sell within the trusted SDA community.',
              fallbackRouteName: 'marketplace',
            ),
            if (_loadingSeller)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 40, 20, 40),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.primaryBlue,
                  ),
                ),
              )
            else if (_account != null && _account!.isBusiness &&
                !AccountModeService.inBusinessMode)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: _PersonalModeGate(),
              )
            else if (_account != null && !_account!.isBusiness)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: _BusinessGate(account: _account!),
              )
            else if (_seller == null || !_seller!.isApproved)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: _SellerGate(seller: _seller),
              )
            else
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
                        _buildPhotosCard(),
                        const SizedBox(height: 16),
                        _buildBasicsCard(),
                        const SizedBox(height: 16),
                        _buildPricingCard(),
                        const SizedBox(height: 16),
                        _buildDetailsCard(),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          PostFormErrorBanner(message: _error!),
                        ],
                        const SizedBox(height: 24),
                        PostFormSaveButton(
                          label: 'List product',
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

  Future<void> _pickPhotos() async {
    if (_uploadingPhotos) return;
    final remaining = 4 - _photoUrls.length;
    if (remaining <= 0) return;
    setState(() {
      _uploadingPhotos = true;
      _error = null;
    });
    try {
      final urls = await StorageService.pickAndUploadProductPhotos(
        max: remaining,
      );
      if (!mounted) return;
      if (urls.isNotEmpty) {
        setState(() => _photoUrls.addAll(urls));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not upload photos. Try again.');
      }
    } finally {
      if (mounted) setState(() => _uploadingPhotos = false);
    }
  }

  void _removePhoto(int index) {
    setState(() => _photoUrls.removeAt(index));
  }

  Widget _buildPhotosCard() {
    final canAddMore = _photoUrls.length < 4;
    return PostFormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'PHOTOS',
                style: AppTextStyles.labelSmall.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.65),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                '${_photoUrls.length}/4',
                style: AppTextStyles.labelSmall.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.45),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photoUrls.length + (canAddMore ? 1 : 0),
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                if (i < _photoUrls.length) {
                  return _PhotoThumb(
                    url: _photoUrls[i],
                    onRemove: () => _removePhoto(i),
                  );
                }
                return _AddPhotoTile(
                  busy: _uploadingPhotos,
                  onTap: _pickPhotos,
                );
              },
            ),
          ),
          if (_photoUrls.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Add at least one photo for the best results.',
              style: AppTextStyles.bodySmall.copyWith(
                color: const Color.fromRGBO(26, 26, 46, 0.55),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBasicsCard() {
    return PostFormCard(
      child: Column(
        children: [
          PostFormLabeledField(
            label: 'Title',
            child: TextFormField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Title is required';
                if (v.trim().length < 3) return 'Title is too short';
                return null;
              },
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.shopping_bag_outlined,
                hint: 'e.g. Hand-knit Baby Blanket',
              ),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Description',
            child: TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.notes_outlined,
                hint: 'Material, size, why you\'re selling',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingCard() {
    return PostFormCard(
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 132,
                child: PostFormLabeledField(
                  label: 'Currency',
                  child: _Dropdown<String>(
                    icon: Icons.attach_money,
                    hint: 'USD',
                    value: _currency,
                    items: _currencies
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(
                                c,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                              ),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _currency = v ?? 'USD'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PostFormLabeledField(
                  label: 'Price',
                  child: TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                    decoration: postFormFilledDecoration(
                      icon: Icons.payments_outlined,
                      hint: '50.00',
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Price is required';
                      final n = double.tryParse(v);
                      if (n == null || n <= 0) return 'Enter a positive number';
                      return null;
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    return PostFormCard(
      child: Column(
        children: [
          PostFormLabeledField(
            label: 'Category',
            child: _Dropdown<String>(
              icon: Icons.category_outlined,
              hint: 'Choose a category',
              value: _category,
              items: _categories.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'other'),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Subcategory (optional)',
            child: TextFormField(
              controller: _subcategoryController,
              textCapitalization: TextCapitalization.words,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.label_outline,
                hint: 'e.g. Laptops',
              ),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Condition',
            child: _Dropdown<String>(
              icon: Icons.verified_outlined,
              hint: 'Choose condition',
              value: _condition,
              items: _conditions.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _condition = v ?? 'new'),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Province',
            child: _Dropdown<String?>(
              icon: Icons.map_outlined,
              hint: 'Choose a province',
              value: _province,
              items: [
                const DropdownMenuItem(value: null, child: Text('Not specified')),
                for (final p in _provinces)
                  DropdownMenuItem(value: p, child: Text(p)),
              ],
              onChanged: (v) => setState(() => _province = v),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'City or area',
            child: TextFormField(
              controller: _locationController,
              textCapitalization: TextCapitalization.words,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.location_on_outlined,
                hint: 'e.g. Harare CBD',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.url, required this.onRemove});
  final String url;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: AppColors.lightGrey,
            image: DecorationImage(
              image: CachedNetworkImageProvider(url),
              fit: BoxFit.cover,
            ),
            border: Border.all(color: const Color.fromRGBO(26, 26, 46, 0.06)),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Material(
            color: AppColors.white,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: AppColors.red),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 96,
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.3),
              style: BorderStyle.solid,
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.primaryBlue,
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_a_photo_outlined,
                      color: AppColors.primaryBlue,
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.icon,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final String hint;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      icon: const Icon(
        Icons.expand_more,
        color: Color.fromRGBO(26, 26, 46, 0.5),
      ),
      style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
      decoration: postFormFilledDecoration(icon: icon, hint: hint),
      hint: Text(
        hint,
        style: AppTextStyles.bodyLarge.copyWith(
          color: const Color.fromRGBO(26, 26, 46, 0.5),
          fontSize: 15,
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

class _SellerGate extends StatelessWidget {
  const _SellerGate({required this.seller});
  final Seller? seller;

  @override
  Widget build(BuildContext context) {
    final pending = seller != null && seller!.isPending;
    final rejected = seller != null && seller!.isRejected;

    final (String kicker, String title, String body, String cta, IconData icon) =
        pending
            ? (
                'AWAITING APPROVAL',
                'Your store is in review',
                'Our team is reviewing your seller application. You\'ll be '
                    'able to list products as soon as it\'s approved — '
                    'usually within a day or two.',
                'View seller dashboard',
                Icons.hourglass_top_rounded,
              )
            : rejected
                ? (
                    'NEEDS ATTENTION',
                    'Your application was declined',
                    seller!.rejectionReason?.trim().isNotEmpty == true
                        ? seller!.rejectionReason!.trim()
                        : 'Please review your details and reapply.',
                    'Update & reapply',
                    Icons.error_outline_rounded,
                  )
                : (
                    'SELLER ACCOUNT REQUIRED',
                    'Set up your store first',
                    'Only verified sellers can list products on Advent '
                        'Connect. Set up a free store profile to start '
                        'selling within the trusted SDA community.',
                    'Set up my store',
                    Icons.storefront_rounded,
                  );

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color.fromRGBO(26, 26, 46, 0.06),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(13, 27, 62, 0.06),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.darkNavy, Color(0xFF1A2F5A)],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: AppColors.goldAccent, size: 30),
          ),
          const SizedBox(height: 18),
          Text(
            kicker,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.goldAccent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineMedium.copyWith(
              color: AppColors.textDark,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.70),
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(14),
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
                onTap: () {
                  if (pending) {
                    context.goNamed('seller_dashboard');
                  } else {
                    // Self-serve flow lands on the Code of Conduct
                    // gate before the setup form (patch_022).
                    context.goNamed('marketplace_guidelines');
                  }
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        cta,
                        style: AppTextStyles.buttonText.copyWith(
                          color: AppColors.white,
                          fontSize: 15,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: AppColors.white,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              'Not now',
              style: AppTextStyles.labelMedium.copyWith(
                color: const Color.fromRGBO(26, 26, 46, 0.6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessGate extends StatelessWidget {
  const _BusinessGate({required this.account});

  final AccountState account;

  @override
  Widget build(BuildContext context) {
    final pending = account.hasPendingApplication;
    final rejected = account.hasRejectedApplication;

    final (String kicker, String title, String body, String cta, IconData icon) =
        pending
            ? (
                'AWAITING APPROVAL',
                'Your business application is in review',
                'Your application is pending review. Once approved, you '
                    'can list products and claim a church listing.',
                'OK',
                Icons.hourglass_top_rounded,
              )
            : rejected
                ? (
                    'NEEDS ATTENTION',
                    'Your application was declined',
                    account.latestApplication?.reviewerNote?.trim().isNotEmpty == true
                        ? account.latestApplication!.reviewerNote!.trim()
                        : 'Please review your details and reapply.',
                    'Re-apply',
                    Icons.error_outline_rounded,
                  )
                : (
                    'BUSINESS ACCOUNT REQUIRED',
                    'Selling needs a business account',
                    'Only business accounts can list products on the '
                        'marketplace. Apply for a business account from your '
                        'profile to start selling.',
                    'Apply for Business',
                    Icons.business_center,
                  );

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color.fromRGBO(26, 26, 46, 0.06),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(13, 27, 62, 0.06),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.darkNavy, Color(0xFF1A2F5A)],
              ),
            ),
            child: Icon(icon, color: AppColors.goldAccent, size: 30),
          ),
          const SizedBox(height: 18),
          Text(
            kicker,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.goldAccent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineMedium.copyWith(
              color: AppColors.textDark,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.70),
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (pending) {
                    context.pop();
                  } else {
                    context.pushNamed('apply_business');
                  }
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      cta,
                      style: AppTextStyles.buttonText.copyWith(
                        color: AppColors.white,
                        fontSize: 15,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when a user IS approved as a business but currently in
/// personal view mode. Different from the BusinessGate above (which
/// is for non-business users) — points back to the profile so they
/// can flip the switch.
class _PersonalModeGate extends StatelessWidget {
  const _PersonalModeGate();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color.fromRGBO(26, 26, 46, 0.06),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(13, 27, 62, 0.06),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.primaryGradient,
            ),
            child: const Icon(
              Icons.swap_horiz,
              color: AppColors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'You\'re in Personal mode',
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Selling is only available in Business mode. Open your '
            'profile and flip the Business / Personal switch to take '
            'this action.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.70),
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.goNamed('profile'),
                borderRadius: BorderRadius.circular(14),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'Go to profile',
                      style: TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
