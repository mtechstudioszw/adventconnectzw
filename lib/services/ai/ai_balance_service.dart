import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_tiers.dart';

/// Why Advent AI will not answer right now.
///
/// The server decides this. The values below exist so the app can render
/// the right words ([AiGateCopy]) without asking a second time — they are
/// a *mirror* of the server's decision, never the decision itself.
enum AiGateReason {
  /// Allowed. The only value that lets a message be sent.
  ok,

  /// Free sample used up, not a subscriber. The one state that sells.
  outOfFree,

  /// Subscriber who has spent this month's allowance.
  outOfAllowance,

  /// The app-wide daily free pool is spent. Nothing to do with this
  /// member — they never got their sample. See the circuit breaker in
  /// `advent-ai/spend_guard.ts`.
  freePoolClosed,

  /// Provider outage, quota exhaustion or billing failure. Hits
  /// subscribers too, so nothing may be sold in this state.
  serviceSuspended,

  /// Advent AI switched off for this account after abuse.
  blocked,
}

/// The member's Advent AI standing, as last reported **by the server**.
///
/// # Security posture — read this before changing anything here
///
/// This class is a **display cache**. It exists so the composer can grey
/// itself out and the paywall can render without a round trip. It is not
/// a permission check, and nothing in it is trusted by the backend.
///
/// Every field arrives from `ai_my_balance()` (patch 234), a SECURITY
/// DEFINER RPC
/// that reads `auth.uid()` server-side. There is no setter, no local
/// arithmetic, and no way for the app to hand a balance to the server:
///
///   * **The send path never sends a balance.** The Edge Function
///     re-reads the member's standing from the database inside the same
///     transaction that debits it, keyed on the JWT it verified itself.
///     A rooted device editing this object changes what its own screen
///     says and nothing else — the next send is still refused.
///   * **`remaining` is not decremented locally** on an optimistic
///     send. It is replaced by the authoritative figure the Edge
///     Function returns with the response. A client that guesses drifts;
///     a client that echoes cannot.
///   * **`isBlocked` is advisory.** The block is enforced in the Edge
///     Function and again by RLS on `ai_messages`. This flag only stops
///     the app from rendering a composer that would be refused anyway.
///
/// The rule the whole feature rests on: **the client renders state, the
/// server owns it.** Any future change that lets this class *compute* a
/// balance rather than receive one has broken that rule.
@immutable
class AiBalance {
  const AiBalance({
    required this.reason,
    required this.remaining,
    required this.grant,
    required this.isPremium,
    this.freeRemaining = 0,
    this.resetsOn,
  });

  /// The server's verdict.
  final AiGateReason reason;

  /// Messages left in the current window. Display only.
  final int remaining;

  /// The size of the window, so the UI can render "3 of 10 left"
  /// without a second source of truth.
  final int grant;

  /// How much of [remaining] is the free sample rather than a Premium
  /// allowance. Kept separate because the two are spent free-first and
  /// the copy differs: a member finishing their sample gets the one
  /// screen that sells, a subscriber finishing their allowance must not.
  final int freeRemaining;

  /// Whether the server considers this member a subscriber. Deliberately
  /// **not** read from [PremiumService] — that cache is for gating ads
  /// and can legitimately lag a fresh purchase. The AI's copy must match
  /// what the AI's own backend believes, or a member who just subscribed
  /// gets shown the "go Premium" wall.
  final bool isPremium;

  /// When [remaining] refills. Null for free members (no refill).
  final DateTime? resetsOn;

  /// What is left of the **Premium allowance alone**, with the free
  /// sample excluded.
  ///
  /// # The "508 of 500" bug (found 25 Aug 2026)
  ///
  /// [remaining] is `total_remaining` — free sample plus allowance. A
  /// subscriber who still had 8 unspent free units therefore read
  /// 8 + 500, and the Premium screen rendered "508 of 500 left" against
  /// a progress bar that had to clamp itself to full. It also hid the
  /// "you have asked N questions this month" line, because
  /// `grant - remaining` was negative.
  ///
  /// Anything drawing the allowance meter must use THIS, not [remaining].
  /// [remaining] is still the right figure for "can I ask a question",
  /// which is why it is the one [canUse] reads.
  int get allowanceRemaining =>
      grant <= 0 ? 0 : (remaining - freeRemaining).clamp(0, grant);

  /// Questions spent out of the Premium allowance this month.
  int get allowanceUsed => grant <= 0 ? 0 : grant - allowanceRemaining;

  /// The only question the UI should ask.
  bool get canUse => reason == AiGateReason.ok && remaining > 0;

  /// True when the member should be nudged before they hit the wall.
  /// Arriving at zero unwarned is what makes a paywall feel like a trap.
  bool get isRunningLow => canUse && remaining <= AiTiers.warnAtRemaining;

  /// A safe standing to start from before the first fetch: usable, so a
  /// member with a working balance sees no flicker of a paywall, but
  /// zero-length so nothing can actually be spent against it. The send
  /// path is authoritative either way.
  static const unknown = AiBalance(
    reason: AiGateReason.ok,
    remaining: 0,
    grant: 0,
    isPremium: false,
  );

  factory AiBalance.fromJson(Map<String, dynamic> json) {
    return AiBalance(
      reason: _reasonFrom(json['reason'] as String?),
      // Clamped, not trusted. A negative figure from a bad migration
      // would otherwise render "-4 messages left".
      remaining:
          ((json['total_remaining'] as num?)?.toInt() ?? 0).clamp(0, 1000000),
      freeRemaining:
          ((json['free_remaining'] as num?)?.toInt() ?? 0).clamp(0, 1000000),
      grant:
          ((json['allowance_units'] as num?)?.toInt() ?? 0).clamp(0, 1000000),
      isPremium: json['is_premium'] as bool? ?? false,
      resetsOn: DateTime.tryParse(json['resets_on'] as String? ?? '')?.toLocal(),
    );
  }

  /// Unknown strings fail **closed**, onto the one state that sells
  /// nothing and blames nobody. A server that grows a new reason this
  /// build has never heard of must not be able to unlock the composer.
  static AiGateReason _reasonFrom(String? raw) {
    switch (raw) {
      case 'ok':
        return AiGateReason.ok;
      case 'out_of_free':
        return AiGateReason.outOfFree;
      case 'out_of_allowance':
        return AiGateReason.outOfAllowance;
      case 'free_pool_closed':
        return AiGateReason.freePoolClosed;
      case 'blocked':
        return AiGateReason.blocked;
      case 'service_suspended':
      default:
        return AiGateReason.serviceSuspended;
    }
  }
}

/// Reads and republishes the member's Advent AI standing.
///
/// Follows [PremiumService]'s shape on purpose — a `ValueListenable` the
/// widgets watch, refreshed at known moments rather than polled. Polling
/// a balance every few seconds would cost more in Supabase egress than
/// the AI messages it guards.
class AiBalanceService {
  AiBalanceService._();

  /// The client, or null when Supabase has not been initialised yet.
  ///
  /// `Supabase.instance` ASSERTS rather than returning null before
  /// `initialize()` completes, so every read has to be guarded. This is
  /// not a test-only concern: `AppBootstrap.startSupabaseInit()` is
  /// deliberately not awaited (see main.dart), so anything that paints
  /// early enough can reach this before the instance exists, and an
  /// assertion thrown from a widget's initState takes the screen down.
  ///
  /// Returning null and reporting [AiBalance.unknown] is the right
  /// failure: the balance is a display cache, the send path re-checks
  /// server-side regardless, and a moment of "unknown" costs nothing.
  static SupabaseClient? get _clientOrNull {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static final ValueNotifier<AiBalance> _balance =
      ValueNotifier<AiBalance>(AiBalance.unknown);

  /// Watch this to keep a composer, a header pill or the paywall in sync.
  static ValueListenable<AiBalance> get balance => _balance;

  static AiBalance get current => _balance.value;

  /// Collapses the burst of refreshes that follows a screen open, a
  /// purchase callback and a send all landing together.
  static Future<AiBalance>? _inFlight;

  /// Re-read the member's standing.
  ///
  /// Deliberately **not** cached to disk. A stale balance restored from
  /// Hive on next launch would show a member messages they do not have,
  /// and the refusal would arrive only after they had typed a question.
  /// A brief unknown state is the better failure.
  static Future<AiBalance> refresh() {
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  static Future<AiBalance> _fetch() async {
    final client = _clientOrNull;

    // Not initialised yet, or signed out: no standing to have. Neither
    // is an error state, and neither may throw — this runs from
    // initState on more than one screen.
    if (client == null || client.auth.currentUser == null) {
      _balance.value = AiBalance.unknown;
      return _balance.value;
    }
    try {
      // No arguments. The function reads auth.uid() itself — passing a
      // user id from the client would be the exact hole this feature is
      // built to avoid.
      // ai_my_balance() RETURNS TABLE, so PostgREST hands back a LIST of
      // one row rather than an object. Reading it as a map silently
      // yields nothing and every member looks out of credit.
      final rows = await client.rpc('ai_my_balance').timeout(
            const Duration(seconds: 8),
          );
      if (rows is List && rows.isNotEmpty) {
        _balance.value =
            AiBalance.fromJson(Map<String, dynamic>.from(rows.first as Map));
      } else {
        // A signed-in member with no row means auth.uid() was null to
        // Postgres — an expired JWT. Treat as unknown, not as zero.
        _balance.value = AiBalance.unknown;
      }
    } on TimeoutException {
      // Keep whatever we last knew. The send path re-checks anyway, so a
      // slow network must not present itself as a paywall.
    } catch (_) {
      // Same reasoning. Errors here are never surfaced as copy — the
      // member finds out at send time, with the server's real reason.
    }
    return _balance.value;
  }

  /// Adopt the authoritative figure the Edge Function returned alongside
  /// an answer. This is how [remaining] moves — never local arithmetic.
  static void adopt(AiBalance fresh) => _balance.value = fresh;

  /// Sign-out. Mirrors [PremiumService.clear] so a shared device cannot
  /// show the next member the last one's allowance.
  static void clear() => _balance.value = AiBalance.unknown;
}
