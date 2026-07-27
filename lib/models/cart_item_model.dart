import 'product_model.dart';

/// One line in the device-local basket.
///
/// Everything the checkout needs is denormalised onto the item at the
/// moment it was added — title, price, seller phone. The basket has to
/// survive offline and across app restarts without re-fetching products,
/// and the price the buyer agreed to is the price they saw, not whatever
/// the seller edits it to later.
class CartItem {
  const CartItem({
    required this.productId,
    required this.title,
    required this.price,
    required this.currency,
    required this.sellerId,
    required this.sellerName,
    required this.qty,
    required this.addedAt,
    this.imageUrl,
    this.sellerPhone,
  });

  final String productId;
  final String title;
  final double price;
  final String currency;
  final String sellerId;
  final String sellerName;
  final String? sellerPhone;
  final String? imageUrl;
  final int qty;
  final DateTime addedAt;

  double get lineTotal => price * qty;

  /// Basket lines cap at 99 to match the `order_items_qty_check`
  /// constraint — going over would fail at checkout, not at tap time.
  static const int maxQty = 99;

  CartItem copyWith({int? qty}) => CartItem(
    productId: productId,
    title: title,
    price: price,
    currency: currency,
    sellerId: sellerId,
    sellerName: sellerName,
    sellerPhone: sellerPhone,
    imageUrl: imageUrl,
    qty: qty ?? this.qty,
    addedAt: addedAt,
  );

  factory CartItem.fromProduct(Product product, {int qty = 1}) => CartItem(
    productId: product.id,
    title: product.title,
    price: product.price,
    currency: product.currency,
    sellerId: product.sellerId,
    sellerName: product.sellerName,
    sellerPhone: product.sellerPhone,
    imageUrl: product.imageUrls.isEmpty ? null : product.imageUrls.first,
    qty: qty,
    addedAt: DateTime.now(),
  );

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
    productId: json['product_id'].toString(),
    title: (json['title'] ?? '') as String,
    price: _readDouble(json['price']),
    currency: (json['currency'] ?? 'USD') as String,
    sellerId: (json['seller_id'] ?? '').toString(),
    sellerName: (json['seller_name'] ?? 'Seller') as String,
    sellerPhone: json['seller_phone'] as String?,
    imageUrl: json['image_url'] as String?,
    qty: (json['qty'] as num?)?.toInt() ?? 1,
    addedAt:
        DateTime.tryParse(json['added_at']?.toString() ?? '') ??
        DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'title': title,
    'price': price,
    'currency': currency,
    'seller_id': sellerId,
    'seller_name': sellerName,
    'seller_phone': sellerPhone,
    'image_url': imageUrl,
    'qty': qty,
    'added_at': addedAt.toIso8601String(),
  };

  static double _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  String formatPrice() => _format(price, currency);
  String formatLineTotal() => _format(lineTotal, currency);

  static String _format(double amount, String currency) {
    final symbol = currency == 'USD' ? r'$' : '$currency ';
    if (amount == amount.roundToDouble()) {
      return '$symbol${amount.toStringAsFixed(0)}';
    }
    return '$symbol${amount.toStringAsFixed(2)}';
  }
}

/// The basket sliced into one unit of checkout. A basket spanning three
/// shops becomes three [SellerBasket]s, and each writes its own order.
///
/// Grouped by seller AND currency: two prices in different currencies
/// cannot be summed into one honest subtotal, and `place_order` rejects a
/// mixed-currency order outright. A seller listing in both USD and ZWL
/// therefore yields two orders rather than one wrong one.
class SellerBasket {
  const SellerBasket({
    required this.sellerId,
    required this.sellerName,
    required this.currency,
    required this.items,
    this.sellerPhone,
  });

  final String sellerId;
  final String sellerName;
  final String? sellerPhone;
  final String currency;
  final List<CartItem> items;

  /// Stable identity for this checkout unit — seller plus currency.
  String get key => '$sellerId|$currency';

  int get itemCount => items.fold(0, (sum, item) => sum + item.qty);

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.lineTotal);

  String formatSubtotal() => CartItem._format(subtotal, currency);

  /// Payload for the `place_order` RPC. Only ids and quantities go up —
  /// the server snapshots the authoritative price itself.
  List<Map<String, dynamic>> toRpcItems() => items
      .map((e) => {'product_id': int.tryParse(e.productId), 'qty': e.qty})
      .where((e) => e['product_id'] != null)
      .toList();
}
