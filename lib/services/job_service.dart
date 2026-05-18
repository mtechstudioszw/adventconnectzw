import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/job_model.dart';
import 'analytics_service.dart';

class JobService {
  JobService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _table = 'jobs';

  static Future<List<Job>> fetchJobs({
    String? search,
    String? category,
  }) async {
    var query = _client.from(_table).select().eq('status', 'open');

    if (category != null && category.isNotEmpty && category != 'all') {
      query = query.eq('category', category);
    }
    if (search != null && search.trim().isNotEmpty) {
      final term = '%${search.trim()}%';
      query = query.or(
        'title.ilike.$term,company.ilike.$term,description.ilike.$term',
      );
    }

    final response =
        await query.order('created_at', ascending: false).limit(200);
    return (response as List)
        .map((row) => Job.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<Job?> fetchJobById(String id) async {
    final response =
        await _client.from(_table).select().eq('id', id).maybeSingle();
    if (response == null) return null;
    return Job.fromJson(response);
  }

  static Future<String> postJob({
    required String title,
    required String description,
    required String category,
    required String province,
    required String location,
    String? company,
    String? requirements,
    String jobType = 'full_time',
    String postType = 'hiring',
    String? salaryRange,
    bool sabbathFriendly = false,
    bool isSdaInstitution = false,
    String? contactPhone,
    String? contactEmail,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to post a job.');
    }
    final inserted = await _client.from(_table).insert({
      'poster_id': user.id,
      'title': title.trim(),
      'company': company?.trim(),
      'description': description.trim(),
      'requirements': requirements?.trim(),
      'category': category,
      'job_type': jobType,
      'post_type': postType,
      'salary_range': salaryRange?.trim(),
      'province': province.trim(),
      'location': location.trim(),
      'sabbath_friendly': sabbathFriendly,
      'is_sda_institution': isSdaInstitution,
      'contact_phone': contactPhone?.trim(),
      'contact_email': contactEmail?.trim(),
    }).select('id').single();
    AnalyticsService.jobPosted(category);
    return inserted['id'].toString();
  }

  /// Flip an open job to 'filled'. RLS already restricts this to the
  /// poster. Server-side trigger `notify_job_filled` then drops a
  /// success notification for the poster (patch_007).
  static Future<void> markAsFilled(String jobId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update a job.');
    }
    await _client
        .from(_table)
        .update({'status': 'filled'})
        .eq('id', jobId)
        .eq('poster_id', user.id);
  }

  /// Flip a filled job back to 'open' so applicants can see it again.
  /// RLS restricts this to the poster.
  static Future<void> reopen(String jobId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update a job.');
    }
    await _client
        .from(_table)
        .update({'status': 'open'})
        .eq('id', jobId)
        .eq('poster_id', user.id);
  }
}
