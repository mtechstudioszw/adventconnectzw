import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/event_model.dart';

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
  }) async {
    final today = _dateOnly(DateTime.now());

    var query = _client.from(_table).select();

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
      query = query.or(
        'title.ilike.$term,description.ilike.$term,location.ilike.$term',
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

  static Future<Event?> fetchEventById(String id) async {
    final response = await _client
        .from(_table)
        .select()
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
    String? description,
    String? venue,
    String? address,
    String? province,
    String? city,
    String? category,
    int? capacity,
    String? contactName,
    String? contactPhone,
    String? coverPhotoUrl,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to post an event.');
    }
    final inserted = await _client.from(_table).insert({
      'title': title.trim(),
      'description': description?.trim(),
      'start_date': _formatDate(_dateOnly(startDate)),
      'start_time': startTime,
      'venue': venue?.trim(),
      'address': address?.trim(),
      'province': province?.trim(),
      'city': city?.trim(),
      'category': category,
      'capacity': capacity,
      'contact_name': contactName?.trim(),
      'contact_phone': contactPhone?.trim(),
      'cover_photo_url': coverPhotoUrl?.trim(),
      'organizer_id': user.id,
      'event_source': 'community',
    }).select('id').single();
    return inserted['id'].toString();
  }

  static Future<void> rsvpToEvent(String eventId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('You must be signed in to RSVP.');
    }
    await _client.from(_rsvpTable).insert({
      'user_id': user.id,
      'event_id': eventId,
    });
  }

  static Future<void> cancelRsvp(String eventId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_rsvpTable)
        .delete()
        .eq('user_id', user.id)
        .eq('event_id', eventId);
  }

  static String _formatDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
