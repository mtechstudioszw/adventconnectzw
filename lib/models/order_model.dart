/// A placed order. One per seller per currency — a basket spanning three
/// shops becomes three of these.
///
/// There are no payment rails, so an order is a *request to buy*, not a
/// completed purchase. Every buyer-facing string must say so; calling
/// this "paid" anywhere would be a lie the app can't back up.
class MarketOrder {
  const MarketOrder({
    required this.id,
    required this.buyerId,
    required this.sellerId,
    required this.status,
    required this.currency,
    required this.subtotal,
    required this.itemCount,
    required this.createdAt,
    this.note,
    this.buyerName,
    this.buyerPhone,
    this.updatedAt,
    this.items = const [],
    this.sellerName,
    this.sellerPhone,
    this.sellerCountry,
  });

  final String id;
  final String buyerId;
  final String sellerId;
  final String status;
  final String currency;
  final double subtotal;
  final int itemCount;
  final String? note;
  final String? buyerName;
  final String? buyerPhone;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<OrderLine> items;

  /// Hydrated from the sellers table for display — not an orders column.
  final String? sellerName;
  final String? sellerPhone;

  /// The seller's ISO-2 country, hydrated alongside the phone. Needed to
  /// normalise [sellerPhone] for `wa.me`: a number typed in national form
  /// is meaningless without knowing whose country it belongs to.
  final String? sellerCountry;

  bool get isPending => status == 'pending';
  bool get isConfirmed => status == 'confirmed';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  /// Terminal states can't be moved out of by either party.
  bool get isOpen => isPending || isConfirmed;

  /// Short human reference used in the WhatsApp handoff so a seller can
  /// tie the message back to the row in their dashboard.
  String get reference => 'AC-$id';

  static const statuses = ['pending', 'confirmed', 'completed', 'cancelled'];

  static String labelFor(String status) => switch (status) {
    'pending' => 'Awaiting seller',
    'confirmed' => 'Confirmed',
    'completed' => 'Completed',
    'cancelled' => 'Cancelled',
    _ => status,
  };

  MarketOrder copyWith({String? status, List<OrderLine>? items}) => MarketOrder(
    id: id,
    buyerId: buyerId,
    sellerId: sellerId,
    status: status ?? this.status,
    currency: currency,
    subtotal: subtotal,
    itemCount: itemCount,
    note: note,
    buyerName: buyerName,
    buyerPhone: buyerPhone,
    createdAt: createdAt,
    updatedAt: updatedAt,
    items: items ?? this.items,
    sellerName: sellerName,
    sellerPhone: sellerPhone,
    // Carried, not dropped: copyWith is how a status change is applied, and
    // losing the country here would leave the WhatsApp handoff unable to
    // dial the seller from the moment the order is confirmed.
    sellerCountry: sellerCountry,
  );

  factory MarketOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['order_items'];
    return MarketOrder(
      id: json['id'].toString(),
      buyerId: (json['buyer_id'] ?? '').toString(),
      sellerId: (json['seller_id'] ?? '').toString(),
      status: (json['status'] ?? 'pending') as String,
      currency: (json['currency'] ?? 'USD') as String,
      subtotal: _readDouble(json['subtotal']),
      itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
      note: json['note'] as String?,
      buyerName: json['buyer_name'] as String?,
      buyerPhone: json['buyer_phone'] as String?,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      items: rawItems is List
          ? rawItems
                .map((e) => OrderLine.fromJson(e as Map<String, dynamic>))
                .toList()
          : const [],
      sellerName: json['seller_name'] as String?,
      sellerPhone: json['seller_phone'] as String?,
      sellerCountry: json['seller_country'] as String?,
    );
  }

  String formatSubtotal() => formatMoney(subtotal, currency);

  static double _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}

/// An immutable line on a placed order. Every display field is a snapshot
/// taken at checkout, so a seller editing or deleting the product later
/// cannot rewrite what was ordered.
class OrderLine {
  const OrderLine({
    required this.id,
    required this.titleSnapshot,
    required this.priceSnapshot,
    required this.currency,
    required this.qty,
    this.productId,
    this.imageUrlSnapshot,
  });

  final String id;

  /// Null once the underlying product is deleted — the snapshot fields
  /// still render, there's just nothing left to navigate to.
  final String? productId;
  final String titleSnapshot;
  final double priceSnapshot;
  final String currency;
  final int qty;
  final String? imageUrlSnapshot;

  double get lineTotal => priceSnapshot * qty;

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
    id: json['id'].toString(),
    productId: json['product_id']?.toString(),
    titleSnapshot: (json['title_snapshot'] ?? '') as String,
    priceSnapshot: MarketOrder._readDouble(json['price_snapshot']),
    currency: (json['currency'] ?? 'USD') as String,
    qty: (json['qty'] as num?)?.toInt() ?? 1,
    imageUrlSnapshot: json['image_url_snapshot'] as String?,
  );

  String formatPrice() => formatMoney(priceSnapshot, currency);
  String formatLineTotal() => formatMoney(lineTotal, currency);
}

String formatMoney(double amount, String currency) {
  final symbol = currency == 'USD' ? r'$' : '$currency ';
  if (amount == amount.roundToDouble()) {
    return '$symbol${amount.toStringAsFixed(0)}';
  }
  return '$symbol${amount.toStringAsFixed(2)}';
}
