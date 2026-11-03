/// The single-feature products (owner, 3 Nov 2026): "someone may only need
/// the ID check" — about a dollar each, beside the Premium bundles.
///
/// The SERVER decides what each one grants (patch 309, verify-purchase,
/// verify-boost); these are the ids and the price shown before Play
/// answers with the member's own currency.
class SmallProducts {
  SmallProducts._();

  /// Subscription, US$1/month: the gold tick only, after the ID check.
  /// A separate product from `premium_monthly` on purpose — it must never
  /// unlock any Premium perk.
  static const String verifiedSku = 'verified_monthly';
  static const String verifiedFallbackPrice = 'US\$1.00';

  /// One-time, US$1: 50 Advent AI questions that never expire.
  static const String aiPackSku = 'ai_questions_50';
  static const int aiPackQuestions = 50;
  static const String aiPackFallbackPrice = 'US\$1.00';

  static bool isVerifiedSku(String? id) => id == verifiedSku;
  static bool isAiPackSku(String? id) => id == aiPackSku;
}
