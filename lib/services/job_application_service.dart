import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/job_application_model.dart';
import '../utils/require_changed.dart';

/// Quick apply, the poster's Applicants list and job alerts (patch_278).
///
/// Everything degrades honestly before the patch runs: [available] turns
/// false on the first "table doesn't exist" and the screens fall back to
/// the poster's own contact details.
class JobApplicationService {
  JobApplicationService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static bool available = true;

  /// Jobs the signed-in member has applied to, for the "Applied" state.
  static final ValueNotifier<Set<String>> appliedJobIds = ValueNotifier(
    const {},
  );

  static bool _missingTable(Object e) {
    final s = e.toString();
    return s.contains('PGRST205') ||
        s.contains('42P01') ||
        s.contains('job_applications') && s.contains('does not exist') ||
        s.contains("Could not find the table");
  }

  static Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      final out = await run();
      available = true;
      return out;
    } catch (e) {
      if (_missingTable(e)) available = false;
      rethrow;
    }
  }

  static const _applicantCols =
      'id, job_id, applicant_id, message, phone, status, created_at, '
      'profiles!job_applications_applicant_id_fkey(full_name, profile_photo_url, city)';

  static Future<void> apply({
    required String jobId,
    String? message,
    String? phone,
  }) => _guard(() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const AuthException('Sign in to apply.');
    await _client.from('job_applications').insert({
      'job_id': int.parse(jobId),
      'applicant_id': me,
      if ((message ?? '').trim().isNotEmpty) 'message': message!.trim(),
      if ((phone ?? '').trim().isNotEmpty) 'phone': phone!.trim(),
    });
    appliedJobIds.value = {...appliedJobIds.value, jobId};
  });

  static Future<void> withdraw(String applicationId, String jobId) =>
      _guard(() async {
        requireChanged(
          await _client
              .from('job_applications')
              .delete()
              .eq('id', int.parse(applicationId))
              .select('id'),
          'application $applicationId',
        );
        appliedJobIds.value = {...appliedJobIds.value}..remove(jobId);
      });

  /// The member's own applications, newest first, each with its job.
  static Future<List<JobApplication>> mine() => _guard(() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return const <JobApplication>[];
    final rows = await _client
        .from('job_applications')
        .select(
          'id, job_id, applicant_id, message, phone, status, '
          'created_at, jobs(*)',
        )
        .eq('applicant_id', me)
        .order('created_at', ascending: false);
    final list = [
      for (final r in rows as List)
        JobApplication.fromJson(r as Map<String, dynamic>),
    ];
    appliedJobIds.value = {for (final a in list) a.jobId};
    return list;
  });

  /// Loads [appliedJobIds] quietly; never throws.
  static Future<void> loadApplied() async {
    if (_client.auth.currentUser == null) return;
    try {
      await mine();
    } catch (_) {}
  }

  /// Applications to one of the poster's jobs (RLS: posters see only
  /// their own jobs' applications).
  static Future<List<JobApplication>> forJob(String jobId) => _guard(() async {
    final rows = await _client
        .from('job_applications')
        .select(_applicantCols)
        .eq('job_id', int.parse(jobId))
        .order('created_at', ascending: false);
    return [
      for (final r in rows as List)
        JobApplication.fromJson(r as Map<String, dynamic>),
    ];
  });

  /// 'viewed' | 'shortlisted' | 'declined'.
  static Future<void> setStatus(String applicationId, String status) =>
      _guard(() async {
        requireChanged(
          await _client
              .from('job_applications')
              .update({'status': status})
              .eq('id', int.parse(applicationId))
              .select('id'),
          'application $applicationId',
        );
      });

  /// The real number of applications to a job, or null when unknown.
  static Future<int?> count(String jobId) async {
    try {
      final n = await _client.rpc(
        'job_applicant_count',
        params: {'p_job_id': int.parse(jobId)},
      );
      return (n as num).toInt();
    } catch (_) {
      return null;
    }
  }
}

/// "Tell me when a job like this is posted" (patch_278).
class JobAlert {
  const JobAlert({
    required this.id,
    this.category,
    this.jobType,
    this.country,
    this.keyword,
  });
  final String id;
  final String? category;
  final String? jobType;
  final String? country;
  final String? keyword;

  factory JobAlert.fromJson(Map<String, dynamic> j) => JobAlert(
    id: j['id'].toString(),
    category: j['category'] as String?,
    jobType: j['job_type'] as String?,
    country: j['country'] as String?,
    keyword: j['keyword'] as String?,
  );

  bool matches({String? category, String? jobType, String? country}) =>
      this.category == category &&
      this.jobType == jobType &&
      this.country == country &&
      keyword == null;
}

class JobAlertService {
  JobAlertService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static final ValueNotifier<List<JobAlert>> alerts = ValueNotifier(const []);
  static bool available = true;

  static Future<List<JobAlert>> load() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return const [];
    try {
      final rows = await _client
          .from('job_alerts')
          .select()
          .eq('user_id', me)
          .order('created_at');
      available = true;
      return alerts.value = [
        for (final r in rows as List)
          JobAlert.fromJson(r as Map<String, dynamic>),
      ];
    } catch (e) {
      final s = e.toString();
      if (s.contains('PGRST205') || s.contains('42P01')) available = false;
      return alerts.value;
    }
  }

  static Future<void> create({
    String? category,
    String? jobType,
    String? country,
    String? keyword,
  }) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const AuthException('Sign in to get job alerts.');
    final row = await _client
        .from('job_alerts')
        .insert({
          'user_id': me,
          'category': category,
          'job_type': jobType,
          'country': country,
          if ((keyword ?? '').trim().isNotEmpty) 'keyword': keyword!.trim(),
        })
        .select()
        .single();
    alerts.value = [...alerts.value, JobAlert.fromJson(row)];
  }

  static Future<void> delete(String id) async {
    final before = alerts.value;
    alerts.value = [
      for (final a in before)
        if (a.id != id) a,
    ];
    try {
      await _client.from('job_alerts').delete().eq('id', int.parse(id));
    } catch (_) {
      alerts.value = before;
      rethrow;
    }
  }
}
