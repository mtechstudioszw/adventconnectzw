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
    this.province,
    this.location,
    this.viewCount = 0,
    this.isFeatured = false,
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
  final String? province;
  final String? location;
  final int viewCount;
  final bool isFeatured;

  String get firstImage => imageUrls.isEmpty ? '' : imageUrls.first;

  bool get isSold => status == 'sold';
  bool get isReserved => status == 'reserved';

  /// "Harare, Mashonaland East" — whichever parts the seller filled in.
  String? get locationLine {
    final parts = [
      location?.trim(),
      province?.trim(),
    ].where((s) => s != null && s.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
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
      province: json['province'] as String?,
      location: json['location'] as String?,
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      isFeatured: json['is_featured'] == true,
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
        'province': province,
        'location': location,
        'view_count': viewCount,
        'is_featured': isFeatured,
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

class ProductCategory {
  const ProductCategory({required this.id, required this.label, required this.icon});
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
