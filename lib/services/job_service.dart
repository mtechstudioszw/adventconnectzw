import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/job_model.dart';
import 'analytics_service.dart';
import 'post_limit_error.dart';

class JobService {
  JobService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _table = 'jobs';

  static Future<List<Job>> fetchJobs({
    String? search,
    String? category,
    String? level,
    /// ISO 3166-1 alpha-2. Null means worldwide.
    ///
    /// Jobs are country-scoped by default for the same reason as the
    /// marketplace: almost every posting here is a local role with a phone
    /// number attached, and a vacancy in another country is one the reader
    /// cannot take. "Remote" is the exception the Worldwide toggle exists
    /// for.
    String? country,
  }) async {
    // Hide expired rows from the public feed. patch_039's pg_cron
    // also flips status='expired' once a day, but filtering by
    // expires_at gives us up-to-the-minute correctness.
    var query = _client
        .from(_table)
        .select()
        .eq('status', 'open')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String());

    if (country != null && country.isNotEmpty) {
      query = query.eq('country', country);
    }
    if (category != null && category.isNotEmpty && category != 'all') {
      query = query.eq('category', category);
    }
    if (level != null && level.isNotEmpty && level != 'all') {
      query = query.eq('level', level);
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
    required String location,
    /// ISO 3166-1 alpha-2 (patch_213). Always send it — the column DEFAULTs
    /// to 'ZW', so a Nairobi vacancy posted without it reads as Zimbabwean.
    String? country,
    /// Province for ZW, free-text region elsewhere. Optional as of
    /// patch_213, which dropped the NOT NULL that made every non-Zimbabwean
    /// job listing impossible to insert.
    String? province,
    String? company,
    String? requirements,
    String jobType = 'full_time',
    String postType = 'hiring',
    String level = 'mid',
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
    final inserted = await PostLimitError.guard(
      PostSection.job,
      () => _client.from(_table).insert({
        'poster_id': user.id,
        'title': title.trim(),
        'company': company?.trim(),
        'description': description.trim(),
        'requirements': requirements?.trim(),
        'category': category,
        'job_type': jobType,
        'post_type': postType,
        'level': level,
        'salary_range': salaryRange?.trim(),
        'country': country,
        'province': province?.trim(),
        'location': location.trim(),
        'sabbath_friendly': sabbathFriendly,
        'is_sda_institution': isSdaInstitution,
        'contact_phone': contactPhone?.trim(),
        'contact_email': contactEmail?.trim(),
      }).select('id').single(),
    );
    AnalyticsService.jobPosted(category);
    return inserted['id'].toString();
  }

  /// Owner-only edit. Touches the same writable fields as the post
  /// form. RLS limits the row to the poster; the `.eq('poster_id')`
  /// is belt-and-braces.
  static Future<void> updateJob({
    required String jobId,
    String? title,
    String? company,
    String? description,
    String? requirements,
    String? category,
    String? jobType,
    String? level,
    String? salaryRange,
    /// ISO 3166-1 alpha-2 (patch_213). Travels with [province].
    String? country,
    String? province,
    String? location,
    bool? sabbathFriendly,
    bool? isSdaInstitution,
    String? contactPhone,
    String? contactEmail,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update a job.');
    }
    final updates = <String, dynamic>{
      'title': ?title?.trim(),
      'company': ?company?.trim(),
      'description': ?description?.trim(),
      'requirements': ?requirements?.trim(),
      'category': ?category,
      'job_type': ?jobType,
      'level': ?level,
      'salary_range': ?salaryRange?.trim(),
      // Written as a pair. Note the asymmetry: country uses `?` because
      // omitting it means "not editing location", but province is guarded
      // on COUNTRY and written even when null — `?province` would skip the
      // null and strand a Zimbabwean province on a job just moved to Kenya.
      'country': ?country,
      if (country != null) 'province': province?.trim(),
      'location': ?location?.trim(),
      'sabbath_friendly': ?sabbathFriendly,
      'is_sda_institution': ?isSdaInstitution,
      'contact_phone': ?contactPhone?.trim(),
      'contact_email': ?contactEmail?.trim(),
    };
    await _client
        .from(_table)
        .update(updates)
        .eq('id', jobId)
        .eq('poster_id', user.id);
  }

  /// Owner-only delete. Permanently removes the row + its
  /// applications cascade.
  static Future<void> deleteJob(String jobId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to delete a job.');
    }
    await _client
        .from(_table)
        .delete()
        .eq('id', jobId)
        .eq('poster_id', user.id);
  }

  /// patch_039: bumps expires_at to NOW() + 30 days and flips
  /// status='expired' back to 'open' if needed. Backed by the
  /// renew_job SECURITY DEFINER RPC which validates ownership.
  static Future<Job> renewJob(String jobId) async {
    final response = await _client.rpc(
      'renew_job',
      params: {'p_job_id': int.parse(jobId)},
    );
    final row = response is List
        ? response.first as Map<String, dynamic>
        : response as Map<String, dynamic>;
    return Job.fromJson(row);
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
