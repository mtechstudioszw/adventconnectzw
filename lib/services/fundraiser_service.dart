import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fundraiser_model.dart';
import 'analytics_service.dart';
import 'auth_service.dart';
import 'cache_service.dart';

/// The iPhone fundraiser — reads progress, records a pledge, remembers a
/// dismissal.
///
/// ## What this service is NOT allowed to do
///
/// It cannot make money appear. `recordPledge` writes a row the server
/// immediately clamps to `pending`; the total on the card comes back from
/// `fundraiser_status()`, which sums CONFIRMED rows only. There is
/// deliberately no method here that marks anything confirmed — see
/// database/patch_253_iphone_fundraiser.sql.
///
/// ## Why the money moves outside the app
///
/// Same reason as the existing donate screen: Play Billing is mandatory for in-app
/// digital purchases and App Store 3.2.1 forbids donations through IAP.
/// So a contribution is an EcoCash transfer, or a WhatsApp/email
/// conversation for anyone without EcoCash, and this service only records
/// that the member says they sent something. The founder confirms it
/// against the actual line.
///
/// ## Cost on the home screen
///
/// One RPC, at most once every [_refreshGap], answered from Hive in the
/// meantime so the card paints on the first frame with no network at all.
/// A failure is not an error state anywhere: the card simply does not
/// appear, which is the correct behaviour for something entirely optional.
class FundraiserService {
  FundraiserService._();

  static final SupabaseClient _client = Supabase.instance.client;

  /// Cached campaign snapshot.
  ///
  /// Unprefixed on purpose. The payload carries `dismissed` and
  /// `my_pending`, which are properties of the signed-in ACCOUNT, so it
  /// must not survive sign-out on a shared phone — and
  /// [CacheService.clearUserData] wipes exactly the unprefixed keys.
  /// A `pref:` key here would leak one member's dismissal to the next.
  static const _kCache = 'fundraiser_status_v1';

  /// Local mirror of the dismissal, so the card vanishes on tap and stays
  /// gone even if the write never reached the server (offline, or a failed
  /// request). Value is the campaign key, so a new campaign is not
  /// pre-dismissed. Unprefixed for the same reason as above.
  static const _kDismissedLocal = 'fundraiser_dismissed_v1';

  /// How often the home screen is allowed to re-ask. A fundraising bar
  /// does not need to be live; it needs to be roughly right and free.
  static const Duration _refreshGap = Duration(minutes: 30);

  /// The current snapshot. The card listens to this directly, which keeps
  /// the home screen's own state untouched — nothing there has to know
  /// this feature exists beyond dropping the widget in.
  static final ValueNotifier<FundraiserCampaign?> campaign =
      ValueNotifier<FundraiserCampaign?>(null);

  static DateTime? _lastFetch;
  static Future<void>? _inFlight;
  static bool _hydrated = false;

  /// True once a dismissal is known locally but not yet accepted by the
  /// server, so the next successful refresh can retry the write.
  static bool _dismissalNeedsSync = false;

  /// Card-shown analytics fire once per app run, not once per rebuild — a
  /// lazy sliver rebuilds this card every time it scrolls back into view.
  static bool _shownLogged = false;

  // ---------------------------------------------------------------------
  //  Reading
  // ---------------------------------------------------------------------

  /// Paint from disk. Synchronous, safe to call during build, and the
  /// reason the card never causes a layout shift on a warm start.
  static FundraiserCampaign? hydrate() {
    if (_hydrated) return campaign.value;
    _hydrated = true;
    try {
      final raw = CacheService.readString(_kCache);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          campaign.value = _applyLocalDismissal(
            FundraiserCampaign.fromJson(decoded),
          );
        }
      }
    } catch (e) {
      // A corrupt cache entry is not worth a crash on the home screen.
      debugPrint('FundraiserService.hydrate failed: $e');
      unawaited(CacheService.invalidate(_kCache));
    }
    return campaign.value;
  }

  /// Fetch the live campaign.
  ///
  /// Throttled to [_refreshGap] unless [force] is set — the contribution
  /// screen forces it on open and after a pledge, which is the only place
  /// freshness actually matters.
  static Future<void> refresh({bool force = false}) {
    final existing = _inFlight;
    if (existing != null) return existing;

    if (!force && _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _refreshGap) {
      return Future<void>.value();
    }

    final future = _fetch();
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  static Future<void> _fetch() async {
    try {
      // Signed out there is no per-user dismissal to read and nothing to
      // contribute with, so do not spend the request.
      //
      // Inside the try, not before it: reaching `currentUser` initialises
      // the Supabase client, which throws outright if the app has not
      // bootstrapped yet. An optional card must not be able to raise an
      // unhandled error during startup.
      if (AuthService.currentUser == null) return;
      final rows = await _client.rpc('fundraiser_status');
      final row = _firstRow(rows);
      if (row == null) return;

      _lastFetch = DateTime.now();
      var next = FundraiserCampaign.fromJson(row);

      // The server is authoritative about everything EXCEPT a dismissal
      // this device made while offline. Re-apply that, then push it up.
      next = _applyLocalDismissal(next);
      if (_dismissalNeedsSync && next.dismissed) {
        unawaited(_syncDismissal());
      }

      campaign.value = next;
      unawaited(CacheService.writeString(_kCache, jsonEncode(next.toJson())));

      if (next.isCompleted) {
        unawaited(AnalyticsService.logEvent('fundraiser_campaign_completed'));
      }
    } catch (e) {
      // Deliberately silent for the member. There is no error UI for an
      // optional card: it just doesn't show, and whatever was cached
      // keeps showing until it expires.
      debugPrint('FundraiserService.refresh failed: $e');
    }
  }

  static Map<String, dynamic>? _firstRow(Object? rows) {
    if (rows is List && rows.isNotEmpty) {
      final first = rows.first;
      if (first is Map<String, dynamic>) return first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    if (rows is Map<String, dynamic>) return rows;
    if (rows is Map) return Map<String, dynamic>.from(rows);
    return null;
  }

  /// A dismissal recorded on this device wins over a server row that has
  /// not caught up yet. It can never go the other way — the server is the
  /// one that can say "you dismissed this on your old phone".
  static FundraiserCampaign _applyLocalDismissal(FundraiserCampaign c) {
    if (c.dismissed) return c;
    if (CacheService.readPref(_kDismissedLocal) == c.campaignKey) {
      _dismissalNeedsSync = true;
      return c.copyWith(dismissed: true);
    }
    return c;
  }

  // ---------------------------------------------------------------------
  //  Dismissing
  // ---------------------------------------------------------------------

  /// Close the card, for good, on every device this account signs into.
  ///
  /// Order matters: local first so the card disappears on the same frame
  /// as the tap, then the server write. If the write fails the local flag
  /// still holds and [_fetch] retries the sync on the next refresh, so a
  /// dismissal made on a train is not quietly lost.
  static Future<void> dismiss() async {
    final current = campaign.value;
    final key = current?.campaignKey ?? '';

    if (current != null) campaign.value = current.copyWith(dismissed: true);
    _dismissalNeedsSync = true;

    unawaited(AnalyticsService.logEvent('fundraiser_card_dismissed'));

    try {
      if (key.isNotEmpty) await CacheService.writePref(_kDismissedLocal, key);
      if (current != null) {
        await CacheService.writeString(
          _kCache,
          jsonEncode(current.copyWith(dismissed: true).toJson()),
        );
      }
    } catch (e) {
      debugPrint('FundraiserService.dismiss could not cache: $e');
    }

    await _syncDismissal();
  }

  static Future<void> _syncDismissal() async {
    try {
      if (AuthService.currentUser == null) return;
      await _client.rpc('fundraiser_dismiss');
      _dismissalNeedsSync = false;
    } catch (e) {
      debugPrint('FundraiserService.dismiss did not reach the server: $e');
    }
  }

  // ---------------------------------------------------------------------
  //  Contributing
  // ---------------------------------------------------------------------

  /// Record that the member says they are sending [amountCents].
  ///
  /// This is a NOTE, not a payment. The row lands as `pending` no matter
  /// what this client sends, and only counts toward the total once the
  /// founder confirms the money actually arrived.
  ///
  /// Returns a [PledgeResult] rather than throwing so the screen can show
  /// friendly copy for every outcome. Nothing raw from Supabase — no SQL
  /// text, no status codes, no ids — ever reaches the member.
  static Future<PledgeResult> recordPledge({
    required int amountCents,
    String method = 'ecocash',
    String? reference,
  }) async {
    if (amountCents <= 0) return PledgeResult.invalidAmount;

    try {
      if (AuthService.currentUser == null) return PledgeResult.signedOut;

      unawaited(AnalyticsService.logEvent(
        'fundraiser_contribution_started',
        parameters: {'amount_cents': amountCents, 'method': method},
      ));

      final id = await _client.rpc('fundraiser_record_pledge', params: {
        'p_amount_cents': amountCents,
        'p_method': method,
        // Never logged to analytics, only stored: this can hold an EcoCash
        // transaction reference.
        'p_reference': reference,
      });

      if (id == null) {
        // The server declined because the campaign is no longer taking
        // anything — funded, or paused while this screen was open.
        unawaited(refresh(force: true));
        return PledgeResult.campaignClosed;
      }

      unawaited(AnalyticsService.logEvent(
        'fundraiser_contribution_recorded',
        parameters: {'amount_cents': amountCents, 'method': method},
      ));
      // The pending count changed, and the total may have too if the
      // founder was quick.
      unawaited(refresh(force: true));
      return PledgeResult.recorded;
    } catch (e) {
      debugPrint('FundraiserService.recordPledge failed: $e');
      unawaited(AnalyticsService.logEvent('fundraiser_contribution_failed'));
      final text = e.toString();
      if (text.contains('too many pending')) return PledgeResult.tooMany;
      return PledgeResult.failed;
    }
  }

  // ---------------------------------------------------------------------
  //  Super admin — the only path that can move the total
  //
  //  These are the client half of the confirm/reject RPCs. Every one of
  //  them is gated by is_super_admin() INSIDE the function, so calling
  //  them from an ordinary account raises rather than quietly succeeding.
  //  Nothing here is a security boundary; the server is.
  // ---------------------------------------------------------------------

  /// Pledges waiting to be matched against the EcoCash line.
  static Future<List<Map<String, dynamic>>> listPending() async {
    final rows = await _client.rpc('fundraiser_list_pending');
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
  }

  /// Confirm that money actually arrived.
  ///
  /// [amountCents] is what the founder SAW, which is not always what the
  /// member said they were sending — someone pledges $5 and sends $3, or
  /// rounds up. Passing null keeps the pledged amount.
  static Future<bool> confirmContribution(
    int id, {
    int? amountCents,
  }) async {
    final ok = await _client.rpc('fundraiser_confirm_contribution', params: {
      'p_id': id,
      'p_amount_cents': amountCents,
    });
    await refresh(force: true);
    return ok == true;
  }

  /// Mark a pledge as never having arrived. The row is kept, not deleted.
  static Future<bool> rejectContribution(int id, {String? note}) async {
    final ok = await _client.rpc('fundraiser_reject_contribution', params: {
      'p_id': id,
      'p_note': note,
    });
    return ok == true;
  }

  // ---------------------------------------------------------------------
  //  Analytics
  // ---------------------------------------------------------------------

  /// Log that the card was actually rendered — once per app run.
  static void noteCardShown(FundraiserCampaign c) {
    if (_shownLogged) return;
    _shownLogged = true;
    unawaited(AnalyticsService.logEvent(
      'fundraiser_card_shown',
      parameters: {'state': c.state.name, 'percent': c.percent},
    ));
  }

  static void noteSupportTapped() {
    unawaited(AnalyticsService.logEvent('fundraiser_support_tapped'));
  }

  /// Drop everything this service is holding for the member signing out.
  ///
  /// [campaign] is a static notifier, so without this the next account to
  /// sign in on the same phone inherits the previous member's dismissal
  /// flag — the card would stay hidden from someone who never closed it,
  /// until a refresh happened to land. Called from [SessionReset.onSignOut].
  ///
  /// The Hive copy is handled separately: its keys are unprefixed, and
  /// `CacheService.clearUserData()` wipes exactly those.
  static void resetForSignOut() {
    campaign.value = null;
    _lastFetch = null;
    _inFlight = null;
    _hydrated = false;
    _dismissalNeedsSync = false;
    _shownLogged = false;
  }

  @visibleForTesting
  static void debugReset() => resetForSignOut();

  @visibleForTesting
  static void debugSet(FundraiserCampaign? c) {
    _hydrated = true;
    campaign.value = c;
  }
}

/// Every way [FundraiserService.recordPledge] can end, each mapping to one
/// sentence of member-facing copy on the contribution screen.
enum PledgeResult {
  recorded,
  campaignClosed,
  tooMany,
  invalidAmount,
  signedOut,
  failed,
}
