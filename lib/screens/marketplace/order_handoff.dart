import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/countries.dart';
import '../../models/order_model.dart';
import '../../services/messaging_service.dart';
import '../../services/order_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Sending a placed order to its seller.
///
/// There are no payment rails, so this handoff *is* the transaction: the
/// order row is the record, and this is how the seller finds out about it.
/// Both channels carry the same itemised message and order reference.
class OrderHandoff {
  OrderHandoff._();

  /// WhatsApp. Primary channel because it is where Zimbabwean sellers
  /// already are — an in-app message they never open helps nobody.
  static Future<void> viaWhatsApp(
    BuildContext context,
    MarketOrder order,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final phone = order.sellerPhone?.trim() ?? '';
    if (phone.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'This seller hasn\'t shared a phone number. Try Advent Chat.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      return;
    }
    // Normalised against the seller's own country — see
    // Countries.toWhatsAppDigits. A seller who typed `0778 092 494` used to
    // produce wa.me/0778092494, which opens an error page, and this handoff
    // IS the transaction: a link that does not open loses the sale.
    final digits = Countries.toWhatsAppDigits(
      phone,
      countryCode: order.sellerCountry,
    );
    final message = OrderService.handoffMessage(order);
    if (digits == null || digits.isEmpty) {
      await Clipboard.setData(ClipboardData(text: message));
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.darkNavy,
          content: Text(
            'That number looks incomplete. Order details copied — send them '
            'to $phone yourself.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      return;
    }
    final uri = Uri.parse(
      'https://wa.me/$digits?text=${Uri.encodeComponent(message)}',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
      throw Exception('launch failed');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: message));
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.darkNavy,
          content: Text(
            'WhatsApp not installed. Order details copied — paste them to $phone.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  /// In-app chat. Opens (or reuses) the thread with the seller and drops
  /// the itemised order in as an editable draft rather than auto-sending,
  /// matching how product enquiries already behave.
  static Future<void> viaAdventChat(
    BuildContext context,
    MarketOrder order,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final convo = await MessagingService.createConversation(
        otherUserId: order.sellerId,
        otherUserName: order.sellerName ?? 'Seller',
        source: 'marketplace',
        isBusiness: true,
      ).timeout(const Duration(seconds: 15));
      final first = order.items.isEmpty ? null : order.items.first;
      ChatLaunchIntent.set(
        draft: OrderService.handoffMessage(order),
        productId: first?.productId,
        productImageUrl: first?.imageUrlSnapshot,
        productTitle: order.itemCount > 1
            ? '${order.reference} · ${order.itemCount} items'
            : first?.titleSnapshot,
        productPrice: order.formatSubtotal(),
      );
      if (!context.mounted) return;
      router.pushNamed('chat', pathParameters: {'id': convo.id}, extra: convo);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not open the chat. Try WhatsApp instead.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }
}
