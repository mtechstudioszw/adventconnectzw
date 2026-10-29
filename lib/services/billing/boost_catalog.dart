/// What a member can pay to put in front of more people (patch 289).
///
/// Each boost is a Google Play ONE-TIME product, consumed after the
/// server grants it so it can be bought again. The SKUs and day counts
/// MIRROR `SKUS` in supabase/functions/verify-boost and
/// `use_boost_credit()` in patch 289 — the server's copies decide.
///
/// Paid placement is always labelled "Promoted" where it shows, and is
/// never mixed into the organic ranking (see MarketRanking).
enum BoostKind {
  /// A Marketplace listing in the Promoted row, with a badge.
  listing(
    sku: 'boost_listing_7d',
    targetType: 'product',
    tag: 'p',
    days: 7,
    title: 'Boost this listing',
    blurb: 'Shown in Marketplace\'s Promoted row for 7 days.',
    fallbackPrice: 'US\$1.00',
  ),

  /// A job pinned to the top of Jobs as Featured.
  job(
    sku: 'boost_job_14d',
    targetType: 'job',
    tag: 'j',
    days: 14,
    title: 'Feature this job',
    blurb: 'Pinned at the top of Jobs as Featured for 14 days.',
    fallbackPrice: 'US\$2.00',
  );

  const BoostKind({
    required this.sku,
    required this.targetType,
    required this.tag,
    required this.days,
    required this.title,
    required this.blurb,
    required this.fallbackPrice,
  });

  /// Play Console product id. NOT YET CREATED — until it is, the boost
  /// sheet says buying isn't available yet and Business credits still work.
  final String sku;

  /// `boosts.target_type`.
  final String targetType;
  final String tag;
  final int days;
  final String title;
  final String blurb;

  /// Shown only if the store hasn't answered with its own localised price.
  final String fallbackPrice;

  /// Passed to Play as the purchase's account tag, so the server learns
  /// WHICH listing was paid for from Play's own record — even if the app
  /// is killed before it can say. "boost:p:42".
  String accountTag(int targetId) => 'boost:$tag:$targetId';

  static BoostKind? forSku(String? sku) {
    for (final k in BoostKind.values) {
      if (k.sku == sku) return k;
    }
    return null;
  }

  static bool isBoostSku(String? sku) => forSku(sku) != null;
}
