import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/event_model.dart';
import 'post_limit_error.dart';
import 'analytics_service.dart';

class EventService {
  EventService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _table = 'events';
  static const _rsvpTable = 'event_rsvps';

  static Future<List<Event>> fetchEvents({
    String? search,
    bool upcomingOnly = true,
    DateTime? from,
    DateTime? to,
    /// ISO 3166-1 alpha-2. Null means worldwide.
    ///
    /// Events are country-scoped by default for the same reason as the
    /// marketplace: a camp meeting is something you attend, and one on
    /// another continent is not an invitation, it is clutter above the
    /// ones you could actually reach.
    String? country,
  }) async {
    final today = _dateOnly(DateTime.now());

    var query = _client
        .from(_table)
        .select('*, profiles!events_organizer_id_fkey(id, full_name)')
        // Only show events that passed super-admin review. Community events
        // default to status='pending' on insert and must be approved before
        // they appear publicly (the organizer still sees their own pending
        // ones under Profile → My events). This is the approval gate the
        // tester found missing — posts were going live unreviewed.
        .eq('status', 'approved');

    if (country != null && country.isNotEmpty) {
      query = query.eq('country', country);
    }

    if (upcomingOnly) {
      query = query.gte('start_date', _formatDate(today));
    } else {
      query = query.lt('start_date', _formatDate(today));
    }

    if (from != null) {
      query = query.gte('start_date', _formatDate(_dateOnly(from)));
    }
    if (to != null) {
      query = query.lte('start_date', _formatDate(_dateOnly(to)));
    }

    if (search != null && search.trim().isNotEmpty) {
      final term = '%${search.trim()}%';
      // Events table has separate `venue` + `city` columns (no
      // `location` column — the model composes that string from
      // venue/city at hydrate time). Searching the non-existent
      // location column was failing silently, leaving the search
      // bar permanently returning zero results.
      query = query.or(
        'title.ilike.$term,description.ilike.$term,venue.ilike.$term,city.ilike.$term',
      );
    }

    final response = await query
        .order('start_date', ascending: upcomingOnly)
        .order('start_time', ascending: upcomingOnly)
        .limit(200);

    return (response as List)
        .map((row) => Event.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Events the current user posted (organized). Used by the Profile
  /// → My events screen's "Posted" tab so the user can find rows
  /// they created (which the RSVP-based list won't surface unless
  /// they also RSVP'd to their own event).
  static Future<List<Event>> fetchMyPostedEvents() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final response = await _client
        .from(_table)
        .select('*, profiles!events_organizer_id_fkey(id, full_name)')
        .eq('organizer_id', user.id)
        .order('start_date', ascending: false)
        .limit(200);
    return (response as List)
        .map((row) => Event.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Approved, upcoming events posted by a church (church_id set). Surfaced as
  /// a featured strip at the top of Home so official church events stand out
  /// from regular community events.
  static Future<List<Event>> fetchFeaturedChurchEvents({int limit = 10}) async {
    final today = _dateOnly(DateTime.now());
    try {
      final response = await _client
          .from(_table)
          .select(
              '*, profiles!events_organizer_id_fkey(id, full_name), churches(name, profile_photo_url)')
          .eq('status', 'approved')
          .not('church_id', 'is', null)
          .gte('start_date', _formatDate(today))
          .order('start_date', ascending: true)
          .limit(limit);
      return (response as List)
          .map((row) => Event.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<Event?> fetchEventById(String id) async {
    final response = await _client
        .from(_table)
        // Join the church so church-hosted events can be credited to the
        // church (name + logo) instead of the individual admin organizer.
        .select(
            '*, profiles!events_organizer_id_fkey(id, full_name), churches(name, profile_photo_url)')
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return Event.fromJson(response);
  }

  static Future<Set<String>> fetchUserRsvpedEventIds() async {
    final user = _client.auth.currentUser;
    if (user == null) return <String>{};
    final response = await _client
        .from(_rsvpTable)
        .select('event_id')
        .eq('user_id', user.id);
    return (response as List)
        .map((row) => row['event_id'].toString())
        .toSet();
  }

  static Future<bool> isRsvped(String eventId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final response = await _client
        .from(_rsvpTable)
        .select('event_id')
        .eq('user_id', user.id)
        .eq('event_id', eventId)
        .maybeSingle();
    return response != null;
  }

  static Future<String> postEvent({
    required String title,
    required DateTime startDate,
    required String startTime,
    DateTime? endDate,
    String? endTime,
    String? description,
    String? venue,
    String? address,
    /// ISO 3166-1 alpha-2 (patch_213). Always send it — `events.country`
    /// DEFAULTs to 'ZW', so an event posted from Nairobi without this is
    /// filed under Zimbabwe.
    String? country,
    /// Province for ZW, free-text region elsewhere.
    String? province,
    String? city,
    String? category,
    int? capacity,
    String? contactName,
    String? contactPhone,
    String? coverPhotoUrl,
    String? churchId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to post an event.');
    }
    final endDateStr =
        endDate == null ? null : _formatDate(_dateOnly(endDate));
    final row = <String, dynamic>{
      'title': title.trim(),
      'description': description?.trim(),
      'start_date': _formatDate(_dateOnly(startDate)),
      'start_time': startTime,
      'end_date': ?endDateStr,
      'end_time': ?endTime,
      'venue': venue?.trim(),
      'address': address?.trim(),
      'country': country,
      'province': province?.trim(),
      'city': city?.trim(),
      'category': category,
      'capacity': capacity,
      'contact_name': contactName?.trim(),
      'contact_phone': contactPhone?.trim(),
      'cover_photo_url': coverPhotoUrl?.trim(),
      'organizer_id': user.id,
      'event_source': churchId != null ? 'church' : 'community',
      if (churchId != null) 'church_id': int.tryParse(churchId) ?? churchId,
    };
    Map<String, dynamic> inserted;
    try {
      inserted = await PostLimitError.guard(
        PostSection.event,
        () => _client.from(_table).insert(row).select('id').single(),
      );
    } catch (e) {
      // Re-surface daily-limit errors instead of falling through to the
      // legacy-schema retry, which would silently consume a second slot.
      if (PostLimitError.matches(e)) rethrow;
      // Retry without the end_* columns when the migration hasn't been
      // applied yet, so existing deployments don't 400 on every post.
      row.remove('end_date');
      row.remove('end_time');
      inserted = await PostLimitError.guard(
        PostSection.event,
        () => _client.from(_table).insert(row).select('id').single(),
      );
    }
    return inserted['id'].toString();
  }

  /// Update an event the current user posted. Server-side RLS enforces
  /// that organizer_id == auth.uid().
  static Future<void> updateEvent({
    required String eventId,
    required String title,
    required DateTime startDate,
    required String startTime,
    DateTime? endDate,
    String? endTime,
    String? description,
    String? venue,
    String? city,
    /// ISO 3166-1 alpha-2 (patch_213). Travels with [province].
    String? country,
    String? province,
    String? category,
    int? capacity,
    String? contactName,
    String? contactPhone,
    String? coverPhotoUrl,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to edit your event.');
    }
    final updates = <String, dynamic>{
      'title': title.trim(),
      'description': description?.trim(),
      'start_date': _formatDate(_dateOnly(startDate)),
      'start_time': startTime,
      // Pass nulls explicitly so clearing an end date in the form
      // actually removes it from the row (not just leaves the previous
      // value in place).
      'end_date': endDate == null ? null : _formatDate(_dateOnly(endDate)),
      'end_time': endTime,
      'venue': venue?.trim(),
      'city': city?.trim(),
      // Written as a pair, province included when null — the same rule the
      // other update paths follow, so moving an event to Kenya clears the
      // stale Zimbabwean province instead of stranding it.
      'country': ?country,
      'province': province?.trim(),
      'category': category,
      'capacity': capacity,
      'contact_name': contactName?.trim(),
      'contact_phone': contactPhone?.trim(),
      'cover_photo_url': coverPhotoUrl?.trim(),
    };
    try {
      await _client
          .from(_table)
          .update(updates)
          .eq('id', eventId)
          .eq('organizer_id', user.id);
    } catch (_) {
      updates.remove('end_date');
      updates.remove('end_time');
      await _client
          .from(_table)
          .update(updates)
          .eq('id', eventId)
          .eq('organizer_id', user.id);
    }
  }

  static Future<void> rsvpToEvent(String eventId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('You must be signed in to RSVP.');
    }
    // UPSERT (not insert) so re-RSVPing never fails on the
    // UNIQUE(event_id, user_id) constraint — the previous plain insert
    // threw a duplicate-key error when the local "going" state was stale,
    // which is why RSVPs appeared to "forget". event_id is cast to int to
    // match the bigint column.
    await _client.from(_rsvpTable).upsert({
      'user_id': user.id,
      'event_id': int.tryParse(eventId) ?? eventId,
      'status': 'going',
    }, onConflict: 'event_id,user_id');
    AnalyticsService.eventRsvp(int.tryParse(eventId) ?? 0, 'going');
  }

  static Future<void> cancelRsvp(String eventId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_rsvpTable)
        .delete()
        .eq('user_id', user.id)
        .eq('event_id', int.tryParse(eventId) ?? eventId);
  }

  static Future<List<Event>> adminFetchPendingEvents() async {
    final response = await _client.rpc('admin_list_pending_events');
    return (response as List)
        .map((row) => Event.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<void> adminApproveEvent(String eventId) async {
    await _client.rpc(
      'admin_approve_event',
      params: {'p_id': int.parse(eventId)},
    );
  }

  static Future<void> adminRejectEvent(String eventId) async {
    await _client.rpc(
      'admin_reject_event',
      params: {'p_id': int.parse(eventId)},
    );
  }

  static String _formatDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
