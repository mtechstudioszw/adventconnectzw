/// Call-minute packs (patch 305, owner 3 Nov 2026).
///
/// Google Play ONE-TIME products, consumed after the server grants them so
/// they can be bought again. The SKUs and minute counts MIRROR `PACKS` in
/// supabase/functions/verify-boost and grant_call_minutes() in patch 305 —
/// the server's copies decide. A pack lasts 30 days and is only spent once
/// the member's own daily or monthly call allowance has run out.
///
/// Android only: the iPhone build has no payments (kHidePayments).
enum CallPack {
  small(
    sku: 'call_minutes_300',
    minutes: 300,
    title: '+5 hours of calls',
    fallbackPrice: 'US\$0.99',
  ),
  large(
    sku: 'call_minutes_1200',
    minutes: 1200,
    title: '+20 hours of calls',
    fallbackPrice: 'US\$2.99',
  );

  const CallPack({
    required this.sku,
    required this.minutes,
    required this.title,
    required this.fallbackPrice,
  });

  /// Play Console one-time product id. Create these exactly.
  final String sku;
  final int minutes;
  final String title;

  /// Shown only if Play hasn't answered with its own localised price.
  final String fallbackPrice;

  static const int validDays = 30;

  /// Account tag passed to Play. Packs credit the buyer, so there is no
  /// target; the tag just marks the purchase as a pack in Play's records.
  static const String accountTag = 'callpack';

  static CallPack? forSku(String? sku) {
    for (final p in CallPack.values) {
      if (p.sku == sku) return p;
    }
    return null;
  }

  static bool isPackSku(String? sku) => forSku(sku) != null;
}
