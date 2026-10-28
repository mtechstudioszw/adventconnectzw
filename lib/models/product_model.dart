import 'package:flutter/material.dart';

import '../config/countries.dart';

class Product {
  const Product({
    required this.id,
    required this.sellerId,
    required this.sellerName,
    required this.title,
    required this.price,
    required this.imageUrls,
    required this.createdAt,
    this.description,
    this.category,
    this.currency = 'USD',
    this.sellerPhone,
    this.sellerVerified = false,
    this.isAvailable = true,
    this.status = 'available',
    this.subcategory,
    this.condition,
    this.country,
    this.province,
    this.location,
    this.viewCount = 0,
    this.isFeatured = false,
    this.moderationHiddenAt,
    this.moderationReason,
    this.stockQuantity,
    this.optionGroups = const [],
    this.specs = const [],
  });

  final String id;
  final String sellerId;
  final String sellerName;
  final String? sellerPhone;
  final bool sellerVerified;
  final String title;
  final String? description;
  final double price;
  final String currency;
  final String? category;
  final List<String> imageUrls;
  final bool isAvailable;
  final String status;
  final DateTime createdAt;

  // Columns the sellers already fill in during add_product but that no
  // screen used to read. Surfaced on the details screen.
  final String? subcategory;
  final String? condition;

  /// Stored condition value → what people read. One list for the listing
  /// form and the details screen, which showed the raw value ("new",
  /// "like_new").
  static const conditionLabels = <String, String>{
    'new': 'New',
    'like_new': 'Like new',
    'good': 'Good',
    'fair': 'Fair',
    'for_parts': 'For parts',
  };

  /// Readable condition; an unknown older value is shown tidied, not raw.
  String? get conditionLabel {
    final c = condition?.trim();
    if (c == null || c.isEmpty) return null;
    final known = conditionLabels[c];
    if (known != null) return known;
    final words = c.replaceAll('_', ' ');
    return words[0].toUpperCase() + words.substring(1);
  }
  /// ISO 3166-1 alpha-2 (patch_213). Marketplace handoff is WhatsApp plus
  /// local pickup, so the country is the first thing a buyer needs to know.
  final String? country;
  final String? province;
  final String? location;
  final int viewCount;
  final bool isFeatured;

  /// Set when the moderators hid this listing (patch_272). The seller can
  /// edit it but not show it again; they see why and can appeal.
  final DateTime? moderationHiddenAt;
  final String? moderationReason;
  bool get isModerated => moderationHiddenAt != null;

  /// How many are left (patch_280). Null = the seller doesn't count stock.
  /// For a product with options it is the options' total, kept by the
  /// server when every option counts stock.
  final int? stockQuantity;

  /// Up to two option groups, e.g. Size [S, M, L] and Colour [Black, Navy].
  final List<ProductOptionGroup> optionGroups;

  /// "Material: Leather" rows, in the seller's order.
  final List<ProductSpec> specs;

  bool get hasOptions => optionGroups.isNotEmpty;
  bool get isSoldOut => stockQuantity == 0;

  /// "Only 3 left" is worth saying; "48 in stock" isn't.
  bool get isLowStock =>
      stockQuantity != null && stockQuantity! > 0 && stockQuantity! <= 5;

  String get firstImage => imageUrls.isEmpty ? '' : imageUrls.first;

  bool get isSold => status == 'sold';
  bool get isReserved => status == 'reserved';

  /// "🇿🇼 Harare, Zimbabwe" — whichever parts the seller filled in.
  ///
  /// The country is appended rather than replacing province/city, and it
  /// leads with the flag. On a worldwide marketplace "Harare" alone is not
  /// an answer to "can I actually collect this?" — and since the app never
  /// handles the transaction, the buyer is the one who has to judge that.
  String? get locationLine {
    final parts = <String?>[
      location?.trim(),
      province?.trim(),
      Countries.nameOf(country),
    ].where((s) => s != null && s.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    final flag = Countries.flagOf(country);
    final line = parts.join(', ');
    return flag.isEmpty ? line : '$flag  $line';
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    final raw = json['image_urls'];
    final images = raw is List
        ? raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : <String>[];
    // status is the real source of truth in the DB.
    // Valid values: 'available', 'sold', 'reserved', 'removed'.
    // is_available does NOT exist as a column — never read it.
    final status = (json['status'] as String?) ?? 'available';
    // DB column is `price_currency`; `currency` is kept as a fallback
    // for offline-cached payloads written before the rename.
    final currency =
        (json['price_currency'] ?? json['currency'] ?? 'USD') as String;
    return Product(
      id: json['id'].toString(),
      sellerId: (json['seller_id'] ?? '').toString(),
      sellerName: (json['seller_name'] ?? 'Seller') as String,
      sellerPhone: json['seller_phone'] as String?,
      sellerVerified: json['seller_verified'] == true,
      title: (json['title'] ?? '') as String,
      description: json['description'] as String?,
      price: _readDouble(json['price']),
      currency: currency,
      category: json['category'] as String?,
      imageUrls: images,
      status: status,
      isAvailable: status == 'available',
      subcategory: json['subcategory'] as String?,
      condition: json['condition'] as String?,
      country: json['country'] as String?,
      province: json['province'] as String?,
      location: json['location'] as String?,
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      isFeatured: json['is_featured'] == true,
      moderationHiddenAt:
          DateTime.tryParse(json['moderation_hidden_at']?.toString() ?? ''),
      moderationReason: json['moderation_reason'] as String?,
      stockQuantity: (json['stock_quantity'] as num?)?.toInt(),
      optionGroups: [
        if (json['option_groups'] is List)
          for (final g in json['option_groups'] as List)
            if (g is Map) ProductOptionGroup.fromJson(g.cast<String, dynamic>()),
      ].where((g) => g.name.isNotEmpty && g.values.isNotEmpty).toList(),
      specs: [
        if (json['specs'] is List)
          for (final r in json['specs'] as List)
            if (r is Map) ProductSpec.fromJson(r.cast<String, dynamic>()),
      ].where((r) => r.label.isNotEmpty && r.value.isNotEmpty).toList(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  /// Round-trip JSON for offline cache. Column names mirror the API
  /// payload so `fromJson` hydrates without special-casing.
  Map<String, dynamic> toJson() => {
        'id': id,
        'seller_id': sellerId,
        'seller_name': sellerName,
        'seller_phone': sellerPhone,
        'seller_verified': sellerVerified,
        'title': title,
        'description': description,
        'price': price,
        'currency': currency,
        'category': category,
        'image_urls': imageUrls,
        'status': status,
        'subcategory': subcategory,
        'condition': condition,
        'country': country,
        'province': province,
        'location': location,
        'view_count': viewCount,
        'is_featured': isFeatured,
        'moderation_hidden_at': moderationHiddenAt?.toIso8601String(),
        'moderation_reason': moderationReason,
        'stock_quantity': stockQuantity,
        'option_groups': [for (final g in optionGroups) g.toJson()],
        'specs': [for (final r in specs) r.toJson()],
        'created_at': createdAt.toIso8601String(),
      };

  static double _readDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  String formatPrice() {
    final symbol = currency == 'USD' ? r'$' : '$currency ';
    if (price == price.roundToDouble()) {
      return '$symbol${price.toStringAsFixed(0)}';
    }
    return '$symbol${price.toStringAsFixed(2)}';
  }
}

/// One option a buyer picks, e.g. Size with its values.
class ProductOptionGroup {
  const ProductOptionGroup({required this.name, required this.values});
  final String name;
  final List<String> values;

  factory ProductOptionGroup.fromJson(Map<String, dynamic> j) =>
      ProductOptionGroup(
        name: (j['name'] ?? '').toString().trim(),
        values: [
          if (j['values'] is List)
            for (final v in j['values'] as List)
              if (v.toString().trim().isNotEmpty) v.toString().trim(),
        ],
      );

  Map<String, dynamic> toJson() => {'name': name, 'values': values};
}

/// One "Label: Value" specification row.
class ProductSpec {
  const ProductSpec({required this.label, required this.value});
  final String label;
  final String value;

  factory ProductSpec.fromJson(Map<String, dynamic> j) => ProductSpec(
    label: (j['label'] ?? '').toString().trim(),
    value: (j['value'] ?? '').toString().trim(),
  );

  Map<String, dynamic> toJson() => {'label': label, 'value': value};
}

/// One combination of options ("M / Black") with its own optional stock
/// and price (patch_280, table product_variants).
class ProductVariant {
  const ProductVariant({
    required this.label,
    required this.options,
    this.id,
    this.price,
    this.stock,
    this.sort = 0,
    this.isActive = true,
  });

  /// Null for one the seller hasn't saved yet.
  final String? id;
  final String label;

  /// Group name → chosen value, e.g. {Size: M, Colour: Black}.
  final Map<String, String> options;

  /// Null = the product's own price.
  final double? price;

  /// Null = not counted.
  final int? stock;
  final int sort;
  final bool isActive;

  bool get isSoldOut => stock == 0;

  ProductVariant copyWith({
    Object? price = _keep,
    Object? stock = _keep,
    bool? isActive,
  }) => ProductVariant(
    id: id,
    label: label,
    options: options,
    price: price == _keep ? this.price : price as double?,
    stock: stock == _keep ? this.stock : stock as int?,
    sort: sort,
    isActive: isActive ?? this.isActive,
  );
  static const _keep = Object();

  factory ProductVariant.fromJson(Map<String, dynamic> j) => ProductVariant(
    id: j['id']?.toString(),
    label: (j['label'] ?? '').toString(),
    options: {
      if (j['options'] is Map)
        for (final e in (j['options'] as Map).entries)
          e.key.toString(): e.value.toString(),
    },
    price: (j['price'] as num?)?.toDouble(),
    stock: (j['stock'] as num?)?.toInt(),
    sort: (j['sort'] as num?)?.toInt() ?? 0,
    isActive: j['is_active'] != false,
  );

  Map<String, dynamic> toRow(String productId) => {
    'product_id': int.parse(productId),
    'label': label,
    'options': options,
    'price': price,
    'stock': stock,
    'sort': sort,
    'is_active': isActive,
  };

  /// Every combination of [groups], labelled "M / Black", in order.
  static List<ProductVariant> combinations(List<ProductOptionGroup> groups) {
    var combos = <Map<String, String>>[{}];
    for (final g in groups) {
      combos = [
        for (final c in combos)
          for (final v in g.values) {...c, g.name: v},
      ];
    }
    if (groups.isEmpty) return const [];
    return [
      for (var i = 0; i < combos.length; i++)
        ProductVariant(
          label: [for (final g in groups) combos[i][g.name]].join(' / '),
          options: combos[i],
          sort: i,
        ),
    ];
  }
}

class ProductCategory {
  const ProductCategory({required this.id, required this.label, required this.icon});

  /// Material icon for the chip strip. The emoji in [icon] rendered as
  /// colourful clip-art next to the app's line icons everywhere else, and
  /// at a different size on every phone vendor.
  IconData get materialIcon => switch (id) {
        'all' => Icons.apps_rounded,
        'books' => Icons.menu_book_rounded,
        'clothing' => Icons.checkroom_rounded,
        'electronics' => Icons.smartphone_rounded,
        'food' => Icons.bakery_dining_rounded,
        'catering' => Icons.restaurant_rounded,
        'furniture' => Icons.chair_rounded,
        'services' => Icons.handyman_rounded,
        _ => Icons.category_rounded,
      };
  final String id;
  final String label;
  final String icon;

  static const all = [
    ProductCategory(id: 'all', label: 'All', icon: '🛒'),
    ProductCategory(id: 'books', label: 'Bibles & Books', icon: '📖'),
    ProductCategory(id: 'clothing', label: 'Clothing', icon: '👗'),
    ProductCategory(id: 'electronics', label: 'Electronics', icon: '📱'),
    ProductCategory(id: 'food', label: 'Food', icon: '🍞'),
    ProductCategory(id: 'catering', label: 'Catering & Events', icon: '🍽️'),
    ProductCategory(id: 'furniture', label: 'Furniture', icon: '🪑'),
    ProductCategory(id: 'services', label: 'Services', icon: '🛠️'),
    ProductCategory(id: 'other', label: 'Other', icon: '✨'),
  ];
}
