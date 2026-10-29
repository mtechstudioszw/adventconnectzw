import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/job_model.dart';
import '../utils/postgrest_filter.dart';
import '../utils/require_changed.dart';
import 'analytics_service.dart';
import 'post_limit_error.dart';

class JobService {
  JobService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _table = 'jobs';

  static Future<List<Job>> fetchJobs({
    String? search,
    String? category,

    /// Any of these fields — the landing's "Everyday work" etc.
    List<String>? categories,
    String? level,
    JobFilters filters = JobFilters.none,

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
    if (categories != null && categories.isNotEmpty) {
      query = query.inFilter('category', categories);
    }
        if (level != null && level.isNotEmpty && level != 'all') {
      query = query.eq('level', level);
    }
    if (filters.jobType != null) query = query.eq('job_type', filters.jobType!);
    if (filters.level != null) query = query.eq('level', filters.level!);
    if (filters.postType != null) {
      query = query.eq('post_type', filters.postType!);
    }
    if (filters.workArrangement != null) {
      query = query.eq('work_arrangement', filters.workArrangement!);
    }
    if (filters.urgent) query = query.eq('is_urgent', true);
    if (filters.sabbathFriendly) query = query.eq('sabbath_friendly', true);
    if (filters.sdaInstitution) query = query.eq('is_sda_institution', true);
    if (search != null && search.trim().isNotEmpty) {
      // Role, employer, skill (description/requirements) or place.
      final term = orFilterValue('%${search.trim()}%');
      query = query.or(
        'title.ilike.$term,company.ilike.$term,description.ilike.$term,'
        'requirements.ilike.$term,location.ilike.$term,province.ilike.$term',
      );
    }

    final response = await query
        .order('created_at', ascending: false)
        .limit(200);
    final jobs = (response as List)
        .map((row) => Job.fromJson(row as Map<String, dynamic>))
        .toList();
    // Featured (paid, patch 289) jobs lead, newest first among them; the
    // rest keep their order. At most three are pinned, so paying can't
    // bury every free listing. Each is labelled "Featured" on its card.
    final featured = jobs.where((j) => j.isFeatured).take(3).toList();
    if (featured.isEmpty) return jobs;
    final pinned = featured.map((j) => j.id).toSet();
    return [...featured, ...jobs.where((j) => !pinned.contains(j.id))];
  }

  static Future<Job?> fetchJobById(String id) async {
    final response = await _client
        .from(_table)
        .select()
        .eq('id', id)
        .maybeSingle();
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
    String? workArrangement,
    String? applyInstructions,
    String? applyUrl,
    String? pageId,
    double? payMin,
    double? payMax,
    String? payPeriod,
    String? payCurrency,
    bool isUrgent = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to post a job.');
    }
    final extra = <String, dynamic>{
      'work_arrangement': ?workArrangement,
      'apply_instructions': ?applyInstructions?.trim(),
      'apply_url': ?applyUrl?.trim(),
      'page_id': ?pageId,
      'pay_min': ?payMin,
      'pay_max': ?payMax,
      'pay_period': ?payPeriod,
      'pay_currency': ?payCurrency,
      if (isUrgent) 'is_urgent': true,
    };
    final inserted = await PostLimitError.guard(
      PostSection.job,
      () => _insertWithFallback({
        if (_hasRedesignColumns) ...extra,
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
      }, extra.keys),
    );
    AnalyticsService.jobPosted(category);
    return inserted['id'].toString();
  }

  /// False once patch_278's columns turn out to be missing; forms then
  /// stop sending them (and say so) instead of failing every post.
  static bool _hasRedesignColumns = true;
  static bool get redesignAvailable => _hasRedesignColumns;

  static bool _missingColumn(Object e) {
    final s = e.toString();
    return s.contains('PGRST204') ||
        s.contains('42703') ||
        s.contains('work_arrangement') ||
        s.contains('apply_instructions') ||
        s.contains('apply_url') ||
        s.contains("'page_id'") ||
        s.contains('pay_') ||
        s.contains('is_urgent');
  }

  /// Asks the server once whether patch_278 has run, so forms can offer
  /// its choices (casual work, the new fields, structured pay) only when
  /// the database will accept them.
  static Future<bool> probeRedesign() async {
    if (_probed) return _hasRedesignColumns;
    try {
      await _client.from(_table).select('id, is_urgent').limit(1);
      _hasRedesignColumns = true;
      _probed = true;
    } catch (e) {
      if (_missingColumn(e)) {
        _hasRedesignColumns = false;
        _probed = true;
      }
    }
    return _hasRedesignColumns;
  }

  static bool _probed = false;

  @visibleForTesting
  static void debugResetRedesign() {
    _probed = false;
    _hasRedesignColumns = true;
  }

  /// Insert; if the new columns don't exist yet, retry once without them.
  /// Safe to retry: PostgREST refuses an unknown column before writing.
  static Future<Map<String, dynamic>> _insertWithFallback(
    Map<String, dynamic> row,
    Iterable<String> newKeys,
  ) async {
    try {
      return await _client.from(_table).insert(row).select('id').single();
    } catch (e) {
      if (!_hasRedesignColumns || !_missingColumn(e)) rethrow;
      _hasRedesignColumns = false;
      final trimmed = {...row}..removeWhere((k, _) => newKeys.contains(k));
      return _client.from(_table).insert(trimmed).select('id').single();
    }
  }

  /// Owner-only edit. Touches the same writable fields as the post
  /// form. RLS limits the row to the poster; the `.eq('poster_id')`
  /// is belt-and-braces.
  static String? _blankToNull(String v) => v.trim().isEmpty ? null : v.trim();

  static Future<void> updateJob({
    required String jobId,
    String? title,
    String? company,
    String? description,
    String? requirements,
    String? category,
    String? jobType,

    /// 'hiring' or 'seeking'. The edit form has the toggle; without this
    /// parameter switching it was silently discarded.
    String? postType,
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
    String? workArrangement,
    String? applyInstructions,
    String? applyUrl,
    String? pageId,

    /// Pay is written as a set whenever [payPeriod] is passed, so clearing
    /// the amount clears it (null) rather than leaving the old number.
    double? payMin,
    double? payMax,
    String? payPeriod,
    String? payCurrency,
    bool? isUrgent,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update a job.');
    }
    final updates = <String, dynamic>{
      if (_hasRedesignColumns) ...{
        'work_arrangement': ?workArrangement,
        // '' clears these: an empty apply_url would fail its http check
        // and an empty page_id isn't a uuid.
        if (applyInstructions != null)
          'apply_instructions': _blankToNull(applyInstructions),
        if (applyUrl != null) 'apply_url': _blankToNull(applyUrl),
        if (pageId != null) 'page_id': _blankToNull(pageId),
        if (payPeriod != null) ...{
          'pay_min': payMin,
          'pay_max': payMax,
          'pay_period': _blankToNull(payPeriod),
          'pay_currency': payCurrency,
        },
        'is_urgent': ?isUrgent,
      },
      'title': ?title?.trim(),
      'company': ?company?.trim(),
      'description': ?description?.trim(),
      'requirements': ?requirements?.trim(),
      'category': ?category,
      'job_type': ?jobType,
      'post_type': ?postType,
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
    requireChanged(
      await _client
          .from(_table)
          .update(updates)
          .eq('id', jobId)
          .eq('poster_id', user.id)
          .select('id'),
      'job $jobId',
    );
  }

  /// Owner-only delete. Permanently removes the row + its
  /// applications cascade.
  static Future<void> deleteJob(String jobId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to delete a job.');
    }
    requireChanged(
      await _client
          .from(_table)
          .delete()
          .eq('id', jobId)
          .eq('poster_id', user.id)
          .select('id'),
      'job $jobId',
    );
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
    requireChanged(
      await _client
          .from(_table)
          .update({'status': 'filled'})
          .eq('id', jobId)
          .eq('poster_id', user.id)
          .select('id'),
      'job $jobId',
    );
  }

  /// Flip a filled job back to 'open' so applicants can see it again.
  /// RLS restricts this to the poster.
  static Future<void> reopen(String jobId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update a job.');
    }
    requireChanged(
      await _client
          .from(_table)
          .update({'status': 'open'})
          .eq('id', jobId)
          .eq('poster_id', user.id)
          .select('id'),
      'job $jobId',
    );
  }

  /// The poster's own listings, every status — pending, open, filled,
  /// expired, rejected — newest first. RLS lets you read your own pending
  /// and rejected rows.
  static Future<List<Job>> fetchMyJobs() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return const [];
    final rows = await _client
        .from(_table)
        .select()
        .eq('poster_id', me)
        .order('created_at', ascending: false);
    return [
      for (final r in rows as List) Job.fromJson(r as Map<String, dynamic>),
    ];
  }

  // ---- Saved jobs (patch_278) ----------------------------------------

  static final ValueNotifier<Set<String>> savedIds = ValueNotifier(const {});
  static bool savedAvailable = true;

  static Future<void> loadSaved() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    try {
      final rows = await _client
          .from('saved_jobs')
          .select('job_id')
          .eq('user_id', me);
      savedAvailable = true;
      savedIds.value = {
        for (final r in rows as List) (r as Map)['job_id'].toString(),
      };
    } catch (e) {
      if (e.toString().contains('saved_jobs') ||
          e.toString().contains('PGRST205') ||
          e.toString().contains('42P01')) {
        savedAvailable = false;
      }
    }
  }

  static Future<void> setSaved(String jobId, bool saved) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const AuthException('Sign in to save jobs.');
    final before = savedIds.value;
    savedIds.value = saved ? {...before, jobId} : ({...before}..remove(jobId));
    try {
      if (saved) {
        await _client.from('saved_jobs').insert({
          'user_id': me,
          'job_id': int.parse(jobId),
        });
      } else {
        await _client
            .from('saved_jobs')
            .delete()
            .eq('user_id', me)
            .eq('job_id', int.parse(jobId));
      }
    } catch (e) {
      savedIds.value = before;
      if (e.toString().contains('saved_jobs') ||
          e.toString().contains('PGRST205')) {
        savedAvailable = false;
      }
      rethrow;
    }
  }

  static Future<List<Job>> fetchSavedJobs() async {
    final ids = savedIds.value.map(int.parse).toList();
    if (ids.isEmpty) return const [];
    final rows = await _client.from(_table).select().inFilter('id', ids);
    return [
      for (final r in rows as List) Job.fromJson(r as Map<String, dynamic>),
    ];
  }
}

/// Filters on the Jobs landing (applied in the query).
class JobFilters {
  const JobFilters({
    this.jobType,
    this.level,
    this.workArrangement,
    this.postType,
    this.sabbathFriendly = false,
    this.sdaInstitution = false,
    this.urgent = false,
  });
  final String? jobType;
  final String? level;
  final String? workArrangement;

  /// 'hiring' (vacancies) or 'seeking' (people looking for work).
  final String? postType;
  final bool sabbathFriendly;
  final bool sdaInstitution;

  /// "Start now" (patch_278).
  final bool urgent;

  static const none = JobFilters();

  JobFilters copyWith({
    Object? jobType = _keep,
    Object? level = _keep,
    Object? workArrangement = _keep,
    Object? postType = _keep,
    bool? sabbathFriendly,
    bool? sdaInstitution,
    bool? urgent,
  }) => JobFilters(
    jobType: jobType == _keep ? this.jobType : jobType as String?,
    level: level == _keep ? this.level : level as String?,
    workArrangement: workArrangement == _keep
        ? this.workArrangement
        : workArrangement as String?,
    postType: postType == _keep ? this.postType : postType as String?,
    sabbathFriendly: sabbathFriendly ?? this.sabbathFriendly,
    sdaInstitution: sdaInstitution ?? this.sdaInstitution,
    urgent: urgent ?? this.urgent,
  );

  static const _keep = Object();

  int get activeCount => [
    jobType != null,
    level != null,
    workArrangement != null,
    postType != null,
    sabbathFriendly,
    sdaInstitution,
    urgent,
  ].where((b) => b).length;

  bool get isEmpty => activeCount == 0;
}
