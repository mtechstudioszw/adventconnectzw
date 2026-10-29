import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/countries.dart';
import '../../models/seller_model.dart';
import '../../models/product_model.dart';
import '../../services/ads/interstitial_ad_manager.dart';
import '../../services/auth_service.dart';
import '../../services/marketplace_service.dart';
import '../../services/product_options_service.dart';
import '../../services/seller_service.dart';
import '../../services/storage_service.dart';
import '../../services/post_limit_error.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/country_picker_sheet.dart';
import '../../widgets/marketplace/product_options_editor.dart';
import '../../widgets/marketplace/product_tile.dart';
import '../../widgets/preview_sheet.dart';
import '../../utils/medical_claims.dart';
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

  /// Free-text region for non-ZW listings — a "state / region" is the only
  /// honest equivalent of a Zimbabwean province once you leave Zimbabwe.
  /// Shares the `province` column with [_province]; see [_regionValue].
  final _regionController = TextEditingController();

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  String _category = 'other';
  String _currency = 'USD';
  /// Null only when editing a listing whose stored condition isn't one
  /// of [_conditions] (older data). The dropdown then shows its hint, and
  /// saving leaves the stored value alone unless the seller picks one —
  /// pre-selecting an unknown value would crash the dropdown.
  String? _condition = 'new';

  /// ISO 3166-1 alpha-2. Never null in practice — seeded in [initState]
  /// from the listing being edited, else from the seller's own profile.
  String? _country;
  String? _province;
  bool _saving = false;
  bool _uploadingPhotos = false;
  String? _error;
  final List<String> _photoUrls = [];

  bool _loadingSeller = true;
  Seller? _seller;

  /// Sizes/colours, stock and specs (patch_280). Shown only once the
  /// database has them; before that the form saves as it always did.
  late final ProductOptionsController _options = ProductOptionsController(
    initial: widget.initialProduct,
  );
  bool _optionsOn = ProductOptionsService.available;

  static const _categories = <String, String>{
    'books': 'Bibles & Books',
    'clothing': 'Clothing',
    'electronics': 'Electronics',
    'food': 'Food',
    'furniture': 'Furniture',
    'services': 'Services',
    'other': 'Other',
  };

  /// What the currency dropdown offers, driven by the country picked above
  /// it. Zimbabwe keeps USD/ZWL/ZAR; everyone else gets their own currency
  /// plus USD. The DB stopped enforcing the old three-value list in
  /// patch_217, so this is now the only thing deciding what a seller sees.
  ///
  /// The current selection is always included, even when the country would
  /// not suggest it. `DropdownButtonFormField` asserts when its value is
  /// absent from its items, so an existing listing priced in something the
  /// seller's country no longer offers has to stay renderable — the edit
  /// screen must open, not crash, on a listing made under other rules.
  List<String> get _currencyChoices {
    final choices = Countries.currencyChoices(_country);
    if (choices.contains(_currency)) return choices;
    return <String>[_currency, ...choices];
  }

  static const _conditions = Product.conditionLabels;

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
    _slide = Tween<double>(
      begin: 12,
      end: 0,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOut));
    _loadSeller();
    _loadOptions();
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
      // These three were never pre-filled, and never saved: editing a
      // "Like new" listing showed "New", and whatever the seller changed
      // here was silently dropped.
      _subcategoryController.text = p.subcategory ?? '';
      _locationController.text = p.location ?? '';
      _condition = _conditions.containsKey(p.condition) ? p.condition : null;
    }
    // Country first, then the province/region that hangs off it. Editing
    // keeps whatever the listing already says; a new listing starts on the
    // seller's own country so most people never open the picker.
    _country = p?.country ?? AuthService.currentCountry();
    if (_isZimbabwe) {
      _province = p?.province;
    } else {
      _regionController.text = p?.province ?? '';
    }
  }

  /// Zimbabwe is the one country this app has a real administrative list
  /// for, and `_provinces` is that list. Everywhere else gets free text —
  /// shipping a half-remembered county list for 200 countries would be
  /// worse than a text box.
  bool get _isZimbabwe => _country == 'ZW';

  /// What actually goes in the `province` column: the dropdown in Zimbabwe,
  /// the free-text region anywhere else, null when neither is filled.
  String? get _regionValue {
    if (_isZimbabwe) return _province;
    final typed = _regionController.text.trim();
    return typed.isEmpty ? null : typed;
  }

  /// Swapping country invalidates whichever location control is on screen,
  /// so the old value is dropped rather than carried across. "Harare" must
  /// not survive a switch to Kenya — that is the bad data this form is
  /// here to stop.
  void _onCountryPicked(Country picked) {
    setState(() {
      _country = picked.code;
      _province = null;
      _regionController.clear();
      // Follow the country with the currency. Someone switching to Kenya
      // means KES, not the USD left over from the default — and leaving a
      // stale ZWL selected on a Kenyan listing is the same class of wrong
      // data as leaving "Harare" in the province.
      _currency = Countries.currencyChoices(picked.code).first;
    });
  }

  Future<void> _loadSeller() async {
    try {
      final seller = await SellerService.fetchMySellerProfile();
      if (!mounted) return;
      setState(() {
        _seller = seller;
        _loadingSeller = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSeller = false);
    }
  }

  Future<void> _loadOptions() async {
    final on = await ProductOptionsService.probe();
    if (!mounted) return;
    setState(() => _optionsOn = on);
    final p = widget.initialProduct;
    if (!on || p == null || !p.hasOptions) return;
    final saved = await ProductOptionsService.fetchVariants(p.id);
    if (mounted) _options.loadVariants(saved);
  }

  /// Saves the options section for [productId]. A failure here leaves the
  /// listing itself saved, and says so.
  Future<String?> _saveOptions(String productId) async {
    if (!_optionsOn) return null;
    try {
      await ProductOptionsService.save(
        productId: productId,
        stockQuantity: _options.stockQuantity,
        optionGroups: _options.cleanGroups,
        specs: _options.cleanSpecs,
        variants: _options.variants,
      );
      return null;
    } catch (_) {
      return 'Your listing is saved, but its sizes, stock and specs '
          "didn't save. Open it and tap Edit to try again.";
    }
  }

  @override
  void dispose() {
    _options.dispose();
    _entrance.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _subcategoryController.dispose();
    _locationController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  /// The tile the marketplace grid will actually draw, built from what's
  /// in the form right now. A listing's photo crop and how far its title
  /// truncates are the two things sellers get wrong, and neither is
  /// visible from the form.
  Product _draftProduct() {
    return Product(
      // Never persisted — the real id comes from the insert.
      id: widget.isEditing ? widget.initialProduct!.id : 'preview',
      sellerId: widget.initialProduct?.sellerId ?? 'preview',
      sellerName: widget.initialProduct?.sellerName ?? 'Your store',
      sellerVerified: widget.initialProduct?.sellerVerified ?? false,
      title: _titleController.text.trim(),
      price: double.tryParse(_priceController.text) ?? 0,
      currency: _currency,
      category: _category,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      imageUrls: List.unmodifiable(_photoUrls),
      createdAt: DateTime.now(),
      condition: _condition,
      country: _country,
      province: _regionValue,
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
    );
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_optionsOn) {
      final problem = _options.validate();
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
    }

    // Medical claims are refused before the preview, not after it: the
    // seller fixes the wording here instead of a moderator hiding the
    // listing later. See the "No medical claims" marketplace rule.
    final claims = findMedicalClaims([
      _titleController.text,
      _descriptionController.text,
      _subcategoryController.text,
    ]);
    if (claims.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Please remove medical claims'),
          content: Text(
            'Your listing mentions: ${claims.join(', ')}.\n\n'
            'Health and wellness products are welcome, but listings may not '
            'say a product treats, cures or prevents a disease or condition. '
            'Describe what it is and how to use it instead.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Edit listing'),
            ),
          ],
        ),
      );
      return;
    }

    // Preview before it goes live — same deal the post composer gets.
    final confirmed = await showEntityPreview(
      context,
      title: widget.isEditing
          ? 'How your listing will look'
          : 'How your listing will look',
      confirmLabel: widget.isEditing ? 'Save changes' : 'List it',
      notes: [
        if (_photoUrls.isEmpty)
          const PreviewNote(
            Icons.photo_outlined,
            'No photo yet — buyers will see a placeholder tile.',
            warn: true,
          )
        else
          PreviewNote(
            Icons.photo_library_outlined,
            _photoUrls.length == 1
                ? '1 photo — the first photo is the tile.'
                : '${_photoUrls.length} photos — the first one is the tile.',
          ),
        const PreviewNote(
          Icons.storefront_outlined,
          'Listed on the marketplace under your store.',
        ),
      ],
      child: Padding(
        // The grid tile is half the screen wide; showing it full-bleed
        // would misrepresent exactly the crop it is here to check.
        padding: const EdgeInsets.symmetric(horizontal: 90),
        child: ProductTile(
          product: _draftProduct(),
          onTap: () {},
        ),
      ),
    );
    if (!confirmed || !mounted) return;

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
          country: _country,
          province: _regionValue,
          subcategory: _subcategoryController.text.trim(),
          condition: _condition,
          location: _locationController.text.trim(),
        );
        final optionsProblem = await _saveOptions(widget.initialProduct!.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              optionsProblem ?? 'Product updated.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
            ),
          ),
        );
      } else {
        // --- Add mode: create new product ---
        final newId = await MarketplaceService.postProduct(
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
          country: _country,
          province: _regionValue,
          location: _locationController.text.isEmpty
              ? null
              : _locationController.text,
          imageUrls: List.unmodifiable(_photoUrls),
        );
        final optionsProblem = await _saveOptions(newId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              optionsProblem ?? 'Product listed.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
            ),
          ),
        );
      }
      // Task complete → show a frequency-capped interstitial (best-effort).
      unawaited(InterstitialAdManager.maybeShow());
      context.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          // patch_277 refuses medical claims on the server too (a wording
          // the in-app list missed, or an older app version).
          _error = e.toString().contains('MEDICAL_CLAIM')
              ? 'Listings may not say a product treats, cures or prevents a '
                    'disease or condition. Please reword it.'
              : PostLimitError.messageFor(
            e,
            fallback: widget.isEditing
                ? 'Could not update the product. Please try again.'
                : 'Could not list the product. Please try again.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
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
                        if (_optionsOn) ...[
                          PostFormCard(
                            child: ProductOptionsEditor(
                              controller: _options,
                              category: _category,
                              currencySymbol: _currency == 'USD'
                                  ? r'$'
                                  : '$_currency ',
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
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
                  color: context.palette.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                '${_photoUrls.length}/4',
                style: AppTextStyles.labelSmall.copyWith(
                  color: context.palette.textMuted,
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
                color: context.palette.textMuted,
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
              maxLength: 120,
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
              maxLength: 4000,
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
                    items: _currencyChoices
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              c,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                            ),
                          ),
                        )
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
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'other'),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Subcategory (optional)',
            child: TextFormField(
              controller: _subcategoryController,
              maxLength: 60,
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
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _condition = v),
            ),
          ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'Country',
            helper: 'Where buyers collect',
            child: CountryFormField(
              code: _country,
              decoration: postFormFilledDecoration(
                icon: Icons.public,
                hint: 'Choose a country',
              ),
              onChanged: _onCountryPicked,
            ),
          ),
          const SizedBox(height: 18),
          // Province is a Zimbabwean administrative unit, so it only makes
          // sense on Zimbabwean listings. Everywhere else the same column
          // takes free text.
          if (_isZimbabwe)
            PostFormLabeledField(
              label: 'Province',
              child: _Dropdown<String?>(
                icon: Icons.map_outlined,
                hint: 'Choose a province',
                value: _province,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Not specified'),
                  ),
                  for (final p in _provinces)
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: (v) => setState(() => _province = v),
              ),
            )
          else
            PostFormLabeledField(
              label: 'State or region (optional)',
              child: TextFormField(
                controller: _regionController,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                decoration: postFormFilledDecoration(
                  icon: Icons.map_outlined,
                  hint: 'e.g. Nairobi County',
                ),
              ),
            ),
          const SizedBox(height: 18),
          PostFormLabeledField(
            label: 'City or area',
            child: TextFormField(
              controller: _locationController,
              maxLength: 120,
              textCapitalization: TextCapitalization.words,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: postFormFilledDecoration(
                icon: Icons.location_on_outlined,
                // Not "e.g. Harare CBD" — the hint is read as an example of
                // what belongs here, and a Zimbabwean city named to a Kenyan
                // seller reads as the app expecting Zimbabwean listings.
                hint: 'e.g. city centre or suburb',
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
            color: context.palette.cardMuted,
            image: DecorationImage(
              image: CachedNetworkImageProvider(url),
              fit: BoxFit.cover,
            ),
            border: Border.all(color: context.palette.divider),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Material(
            color: context.palette.card,
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
      icon: Icon(Icons.expand_more, color: context.palette.textMuted),
      style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
      decoration: postFormFilledDecoration(icon: icon, hint: hint),
      hint: Text(
        hint,
        style: AppTextStyles.bodyLarge.copyWith(
          color: context.palette.textMuted,
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

    final (
      String kicker,
      String title,
      String body,
      String cta,
      IconData icon,
    ) = pending
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
            'Only verified sellers can list products on Adventist '
                'Super App. Set up a free store profile to start '
                'selling within the trusted SDA community.',
            'Set up my store',
            Icons.storefront_rounded,
          );

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.divider),
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
              color: context.palette.text,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
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
                color: context.palette.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
