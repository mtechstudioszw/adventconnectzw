/// True when a `profiles.premium_until` value (ISO string, DateTime or
/// null) is still in the future — i.e. that member has Premium right now.
///
/// Read from the author / participant joins so OTHER members see the
/// Premium star (owner, 4 Nov 2026: a perk only the buyer can see doesn't
/// sell). `premium_until` is kept current by the billing sync
/// (sync_premium_until) and is readable to signed-in members.
bool premiumActive(Object? premiumUntil, {DateTime? now}) {
  final DateTime? until = premiumUntil is DateTime
      ? premiumUntil
      : premiumUntil is String
          ? DateTime.tryParse(premiumUntil)
          : null;
  if (until == null) return false;
  return until.isAfter(now ?? DateTime.now());
}
