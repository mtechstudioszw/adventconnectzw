/// Mirrors the `sellers` table (V4 schema, Table 10).
///
/// A row exists only after the user applies via setup_store. Status is
/// the gate to the dashboard — `pending` shows a waiting banner,
/// `rejected` shows the reason + Reapply, `approved` unlocks the full
/// seller experience.
class Seller {
  const Seller({
    required this.id,
    required this.authUserId,
    required this.businessName,
    required this.category,
    required this.phone,
    required this.status,
    this.description,
    this.province,
    this.city,
    this.suburb,
    this.address,
    this.whatsapp,
    this.contactName,
    this.profilePhotoUrl,
    this.coverPhotoUrl,
    this.paymentMethods,
    this.offersDelivery = false,
    this.deliveryArea,
    this.deliveryFee,
    this.rejectionReason,
    this.verified = false,
    this.sdaVerified = false,
    this.featured = false,
    this.rating = 0,
    this.ratingCount = 0,
    this.isActive = true,
    this.approvedAt,
    this.observesSabbath = false,
    this.sabbathNoticeText,
    this.createdAt,
  });

  final String id;
  final String authUserId;
  final String businessName;
  final String category;
  final String? description;
  final String? province;
  final String? city;
  final String? suburb;
  final String? address;
  final String phone;
  final String? whatsapp;
  final String? contactName;
  final String? profilePhotoUrl;
  final String? coverPhotoUrl;
  final String? paymentMethods;
  final bool offersDelivery;
  final String? deliveryArea;
  final String? deliveryFee;
  final String status;
  final String? rejectionReason;
  final bool verified;
  final bool sdaVerified;
  final bool featured;
  final double rating;
  final int ratingCount;
  final bool isActive;
  final DateTime? approvedAt;
  final bool observesSabbath;
  final String? sabbathNoticeText;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory Seller.fromJson(Map<String, dynamic> json) {
    return Seller(
      id: json['id'].toString(),
      authUserId: (json['auth_user_id'] ?? '').toString(),
      businessName: (json['business_name'] ?? '') as String,
      category: (json['category'] ?? '') as String,
      description: json['description'] as String?,
      province: json['province'] as String?,
      city: json['city'] as String?,
      suburb: json['suburb'] as String?,
      address: json['address'] as String?,
      phone: (json['phone'] ?? '') as String,
      whatsapp: json['whatsapp'] as String?,
      contactName: json['contact_name'] as String?,
      profilePhotoUrl: json['profile_photo_url'] as String?,
      coverPhotoUrl: json['cover_photo_url'] as String?,
      paymentMethods: json['payment_methods'] as String?,
      offersDelivery: json['offers_delivery'] == true,
      deliveryArea: json['delivery_area'] as String?,
      deliveryFee: json['delivery_fee'] as String?,
      status: (json['status'] ?? 'pending') as String,
      rejectionReason: json['rejection_reason'] as String?,
      verified: json['verified'] == true,
      sdaVerified: json['sda_verified'] == true,
      featured: json['featured'] == true,
      rating: _readDouble(json['rating']),
      ratingCount: _readInt(json['rating_count']),
      isActive: json['is_active'] != false,
      approvedAt: _parseDate(json['approved_at']),
      observesSabbath: json['observes_sabbath'] == true,
      sabbathNoticeText: json['sabbath_notice_text'] as String?,
      createdAt: _parseDate(json['created_at']),
    );
  }

  static double _readDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}

/// The categories a seller picks from when applying. Kept here so the
/// setup form and the listings filter draw from the same source of truth.
class SellerCategory {
  const SellerCategory({required this.id, required this.label, required this.icon});
  final String id;
  final String label;
  final String icon;

  static const all = [
    SellerCategory(id: 'books', label: 'Bibles & Books', icon: '📖'),
    SellerCategory(id: 'clothing', label: 'Clothing & Fashion', icon: '👗'),
    SellerCategory(id: 'electronics', label: 'Electronics', icon: '📱'),
    SellerCategory(id: 'food', label: 'Food & Groceries', icon: '🍞'),
    SellerCategory(id: 'furniture', label: 'Furniture & Home', icon: '🪑'),
    SellerCategory(id: 'services', label: 'Services', icon: '🛠️'),
    SellerCategory(id: 'crafts', label: 'Crafts & Art', icon: '🎨'),
    SellerCategory(id: 'other', label: 'Other', icon: '✨'),
  ];

  static String labelFor(String id) {
    return all
        .firstWhere(
          (c) => c.id == id,
          orElse: () => const SellerCategory(
            id: 'other',
            label: 'Other',
            icon: '✨',
          ),
        )
        .label;
  }
}

const sellerProvinces = <String>[
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
