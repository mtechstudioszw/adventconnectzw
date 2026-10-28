import 'job_model.dart';

/// One Quick apply (patch_278). The applicant sees their own; a poster sees
/// the ones sent to their jobs, with the applicant's name and photo.
class JobApplication {
  const JobApplication({
    required this.id,
    required this.jobId,
    required this.applicantId,
    required this.status,
    required this.createdAt,
    this.message,
    this.phone,
    this.applicantName,
    this.applicantPhotoUrl,
    this.applicantCity,
    this.job,
  });

  final String id;
  final String jobId;
  final String applicantId;

  /// 'sent' | 'viewed' | 'shortlisted' | 'declined'.
  final String status;
  final DateTime createdAt;
  final String? message;
  final String? phone;
  final String? applicantName;
  final String? applicantPhotoUrl;
  final String? applicantCity;

  /// Embedded on the applicant's own list.
  final Job? job;

  bool get isShortlisted => status == 'shortlisted';
  bool get isDeclined => status == 'declined';
  bool get isNew => status == 'sent';

  /// Worded for the applicant.
  String get applicantStatusLabel => switch (status) {
    'viewed' => 'Seen by employer',
    'shortlisted' => 'Shortlisted',
    'declined' => 'Not selected',
    _ => 'Sent',
  };

  factory JobApplication.fromJson(Map<String, dynamic> json) {
    final p = json['profiles'];
    final j = json['jobs'];
    return JobApplication(
      id: json['id'].toString(),
      jobId: json['job_id'].toString(),
      applicantId: (json['applicant_id'] ?? '').toString(),
      status: (json['status'] ?? 'sent') as String,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      message: (json['message'] as String?)?.trim(),
      phone: (json['phone'] as String?)?.trim(),
      applicantName: p is Map ? p['full_name'] as String? : null,
      applicantPhotoUrl: p is Map ? p['profile_photo_url'] as String? : null,
      applicantCity: p is Map ? p['city'] as String? : null,
      job: j is Map<String, dynamic> ? Job.fromJson(j) : null,
    );
  }
}
