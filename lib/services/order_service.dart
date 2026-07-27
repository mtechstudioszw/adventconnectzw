import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_item_model.dart';
import '../models/order_model.dart';

/// Server side of the basket. Nothing here runs while the user shops —
/// [CartService] owns that, on-device. This begins at checkout.
class OrderService {
  OrderService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _table = 'orders';

  /// Place one basket as one order. Returns the created order id.
  ///
  /// Goes through the `place_order` RPC rather than two inserts so the
  /// order and its lines commit together, and so prices are snapshotted
  /// from the products table server-side — the client's cached price is
  /// never trusted.
  static Future<String> placeBasket(
    SellerBasket basket, {
    String? note,
    String? buyerName,
    String? buyerPhone,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to place an order.');
    }
    final items = basket.toRpcItems();
    if (items.isEmpty) {
      throw StateError('This basket has no orderable items.');
    }
    final id = await _client.rpc(
      'place_order',
      params: {
        'p_seller_id': basket.sellerId,
        'p_items': items,
        'p_note': note,
        'p_buyer_name': buyerName,
        'p_buyer_phone': buyerPhone,
      },
    );
    return id.toString();
  }

  /// Orders the signed-in user placed, newest first.
  static Future<List<MarketOrder>> fetchMyOrders() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final rows = await _client
        .from(_table)
        .select('*, order_items(*)')
        .eq('buyer_id', user.id)
        .order('created_at', ascending: false);
    final orders = (rows as List)
        .map((r) => MarketOrder.fromJson(r as Map<String, dynamic>))
        .toList();
    return _hydrateSellers(orders);
  }

  /// Orders placed WITH the signed-in user, i.e. their sales inbox.
  static Future<List<MarketOrder>> fetchSellerOrders() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final rows = await _client
        .from(_table)
        .select('*, order_items(*)')
        .eq('seller_id', user.id)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => MarketOrder.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  static Future<MarketOrder?> fetchById(String orderId) async {
    final row = await _client
        .from(_table)
        .select('*, order_items(*)')
        .eq('id', orderId)
        .maybeSingle();
    if (row == null) return null;
    final hydrated = await _hydrateSellers([MarketOrder.fromJson(row)]);
    return hydrated.first;
  }

  /// Move an order's status. RLS lets either party update, and the
  /// `orders_freeze_financials` trigger stops anything but status (and the
  /// note) from changing — so this cannot be used to rewrite a total.
  static Future<void> updateStatus(String orderId, String status) async {
    if (!MarketOrder.statuses.contains(status)) {
      throw ArgumentError('unknown order status: $status');
    }
    await _client.from(_table).update({'status': status}).eq('id', orderId);
  }

  /// Attach seller display fields. `orders` stores only `seller_id`; the
  /// name and phone live on the sellers row, and are looked up in one
  /// batched query rather than per-order.
  static Future<List<MarketOrder>> _hydrateSellers(
    List<MarketOrder> orders,
  ) async {
    if (orders.isEmpty) return orders;
    final ids = orders.map((o) => o.sellerId).toSet().toList();
    try {
      final rows = await _client
          .from('sellers')
          .select('auth_user_id, business_name, phone, whatsapp')
          .inFilter('auth_user_id', ids);
      final byId = <String, Map<String, dynamic>>{
        for (final r in (rows as List))
          (r as Map<String, dynamic>)['auth_user_id'].toString(): r,
      };
      return orders.map((o) {
        final seller = byId[o.sellerId];
        if (seller == null) return o;
        final whatsapp = (seller['whatsapp'] as String?)?.trim();
        return MarketOrder(
          id: o.id,
          buyerId: o.buyerId,
          sellerId: o.sellerId,
          status: o.status,
          currency: o.currency,
          subtotal: o.subtotal,
          itemCount: o.itemCount,
          note: o.note,
          buyerName: o.buyerName,
          buyerPhone: o.buyerPhone,
          createdAt: o.createdAt,
          updatedAt: o.updatedAt,
          items: o.items,
          sellerName: seller['business_name'] as String?,
          sellerPhone: whatsapp?.isNotEmpty == true
              ? whatsapp
              : seller['phone'] as String?,
        );
      }).toList();
    } catch (_) {
      // Display sugar only — never fail an order list over it.
      return orders;
    }
  }

  /// The message sent to the seller after checkout. Deliberately worded
  /// as a request, lists the itemised lines, and carries the reference so
  /// the seller can find the order in their dashboard.
  static String handoffMessage(MarketOrder order) {
    final buffer = StringBuffer()
      ..writeln('Hi${order.sellerName == null ? '' : ' ${order.sellerName}'}, '
          'I\'d like to order this from Advent Connect ZW:')
      ..writeln();
    for (final line in order.items) {
      buffer.writeln(
        '• ${line.titleSnapshot} × ${line.qty} — ${line.formatLineTotal()}',
      );
    }
    buffer
      ..writeln()
      ..writeln('Total: ${order.formatSubtotal()}')
      ..writeln('Order ref: ${order.reference}');
    if (order.note?.trim().isNotEmpty == true) {
      buffer
        ..writeln()
        ..writeln('Note: ${order.note!.trim()}');
    }
    return buffer.toString();
  }
}
