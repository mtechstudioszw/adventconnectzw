import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/church_model.dart';
import 'analytics_service.dart';

class ChurchService {
  ChurchService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _table = 'churches';
  static const _followsTable = 'church_followers';

  static Future<List<Church>> fetchChurches({
    String? search,
    String? city,
  }) async {
    var query = _client.from(_table).select();

    if (city != null && city.isNotEmpty) {
      query = query.eq('city', city);
    }

    if (search != null && search.trim().isNotEmpty) {
      final term = '%${search.trim()}%';
      query = query.or('name.ilike.$term,city.ilike.$term');
    }

    final response = await query
        .order('members_count', ascending: false)
        .limit(100);

    return (response as List)
        .map((row) => Church.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<Church?> fetchChurchById(String id) async {
    final response = await _client
        .from(_table)
        .select()
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return Church.fromJson(response);
  }

  static Future<List<String>> fetchAvailableCities() async {
    final response = await _client
        .from(_table)
        .select('city')
        .order('city');
    final cities = (response as List)
        .map((row) => (row['city'] ?? '').toString())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return cities;
  }

  static Future<Set<String>> fetchUserFollowedChurchIds() async {
    final user = _client.auth.currentUser;
    if (user == null) return <String>{};
    final response = await _client
        .from(_followsTable)
        .select('church_id')
        .eq('user_id', user.id);
    return (response as List)
        .map((row) => row['church_id'].toString())
        .toSet();
  }

  static Future<bool> isFollowing(String churchId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final response = await _client
        .from(_followsTable)
        .select('church_id')
        .eq('user_id', user.id)
        .eq('church_id', churchId)
        .maybeSingle();
    return response != null;
  }

  static Future<void> follow(String churchId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('You must be signed in to follow a church.');
    }
    await _client.from(_followsTable).insert({
      'user_id': user.id,
      'church_id': churchId,
    });
    AnalyticsService.churchFollowed(int.tryParse(churchId) ?? 0);
  }

  static Future<void> unfollow(String churchId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_followsTable)
        .delete()
        .eq('user_id', user.id)
        .eq('church_id', churchId);
  }

  /// Insert a row into `church_edit_suggestions`. Status defaults to
  /// pending and an admin reviews it from the web dashboard.
  static Future<void> suggestEdit({
    required String churchId,
    required String fieldName,
    required String currentValue,
    required String suggestedValue,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to suggest an edit.');
    }
    await _client.from('church_edit_suggestions').insert({
      'church_id': churchId,
      'suggested_by': user.id,
      'field_name': fieldName,
      'current_value': currentValue,
      'suggested_value': suggestedValue,
    });
  }

  /// Insert into `church_suggestions` — used by suggest_church_screen
  /// to nominate a new SDA church for the directory.
  static Future<void> suggestChurch({
    required String name,
    required String province,
    String? city,
    String? suburb,
    String? pastorName,
    String? contactPhone,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to suggest a church.');
    }
    await _client.from('church_suggestions').insert({
      'suggested_by': user.id,
      'church_name': name.trim(),
      'province': province,
      'city': ?city?.trim(),
      'suburb': ?suburb?.trim(),
      'pastor_name': ?pastorName?.trim(),
      'contact_phone': ?contactPhone?.trim(),
    });
  }

  /// Apply to become a church admin. Status defaults to pending — admin
  /// reviews via the web dashboard and verifies via WhatsApp.
  static Future<void> applyForChurchAdmin({
    required String churchId,
    required String role,
    String? appointmentLetterUrl,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to claim a church.');
    }
    await _client.from('church_admins').upsert({
      'church_id': churchId,
      'user_id': user.id,
      'role': role,
      'appointment_letter_url': ?appointmentLetterUrl,
      'status': 'pending',
    }, onConflict: 'church_id,user_id');
    AnalyticsService.churchClaimed(int.tryParse(churchId) ?? 0);
  }

  /// Fetch a church's announcements feed. Filters out expired rows.
  static Future<List<ChurchAnnouncement>> fetchAnnouncements({
    required String churchId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final response = await _client
        .from('announcements')
        .select()
        .eq('church_id', churchId)
        .or('expires_at.is.null,expires_at.gt.$now')
        .order('is_pinned', ascending: false)
        .order('created_at', ascending: false)
        .limit(100);
    return (response as List)
        .map((row) =>
            ChurchAnnouncement.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Post an announcement on behalf of an approved church admin.
  /// Server-side RLS enforces that the caller actually owns this role.
  static Future<void> postAnnouncement({
    required String churchId,
    required String title,
    required String body,
    String category = 'general',
    bool isPinned = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to post.');
    }
    await _client.from('announcements').insert({
      'church_id': churchId,
      'posted_by': user.id,
      'title': title.trim(),
      'body': body.trim(),
      'category': category,
      'is_pinned': isPinned,
    });
  }

  /// Approved church-admin roles for the current user. Used to gate
  /// access to the admin dashboard and to pre-fill the church picker.
  static Future<List<ChurchAdminRole>> fetchMyAdminRoles() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final response = await _client
        .from('church_admins')
        .select('*, churches(name, city)')
        .eq('user_id', user.id);
    return (response as List)
        .map((row) => ChurchAdminRole.fromJson(row as Map<String, dynamic>))
        .toList();
  }
}

class ChurchAnnouncement {
  const ChurchAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.category = 'general',
    this.isPinned = false,
  });

  final String id;
  final String title;
  final String body;
  final String category;
  final bool isPinned;
  final DateTime createdAt;

  factory ChurchAnnouncement.fromJson(Map<String, dynamic> json) {
    return ChurchAnnouncement(
      id: json['id'].toString(),
      title: (json['title'] ?? '') as String,
      body: (json['body'] ?? '') as String,
      category: (json['category'] ?? 'general') as String,
      isPinned: json['is_pinned'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class ChurchAdminRole {
  const ChurchAdminRole({
    required this.id,
    required this.churchId,
    required this.churchName,
    required this.role,
    required this.status,
    this.city,
  });

  final String id;
  final String churchId;
  final String churchName;
  final String role; // 'primary' / 'standard'
  final String status; // 'pending' / 'approved' / 'rejected'
  final String? city;

  bool get isApproved => status == 'approved';

  factory ChurchAdminRole.fromJson(Map<String, dynamic> json) {
    final church = json['churches'];
    final churchMap = church is Map<String, dynamic> ? church : null;
    return ChurchAdminRole(
      id: json['id'].toString(),
      churchId: (json['church_id'] ?? '').toString(),
      churchName: (churchMap?['name'] as String?) ?? 'Church',
      role: (json['role'] ?? 'standard') as String,
      status: (json['status'] ?? 'pending') as String,
      city: churchMap?['city'] as String?,
    );
  }
}
