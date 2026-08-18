class Job {
  const Job({
    required this.id,
    required this.posterId,
    required this.title,
    required this.company,
    required this.createdAt,
    this.posterName = 'Member',
    this.country,
    this.province,
    this.location,
    this.type,
    this.salaryMin,
    this.salaryMax,
    this.currency = 'USD',
    this.description,
    this.requirements = const [],
    this.category,
    this.contactPhone,
    this.companyLogoUrl,
    this.isActive = true,
    this.status = 'open',
    this.postType = 'hiring',
    this.level = 'mid',
    this.expiresAt,
  });

  final String id;
  final String posterId;
  final String posterName;
  final String title;
  final String company;

  /// ISO 3166-1 alpha-2 (patch_213). Carried so the edit form can show the
  /// country the job was actually posted under — without it the picker
  /// defaults to the poster's own country and quietly rewrites the row.
  final String? country;

  /// Zimbabwean province for ZW rows, free-text region elsewhere. Same
  /// reason as [country]: the edit form used to start blank and force the
  /// poster to re-pick, so an edit could move the job by accident.
  final String? province;

  final String? location;
  final String? type;
  final double? salaryMin;
  final double? salaryMax;
  final String currency;
  final String? description;
  final List<String> requirements;
  final String? category;
  final String? contactPhone;
  final String? companyLogoUrl;
  final bool isActive;
  final String status;
  /// 'hiring' (employer offering a role) or 'seeking' (member looking
  /// for work). Drives whether the card labels the poster as a
  /// recruiter or as the candidate.
  final String postType;
  /// 'entry' | 'mid' | 'senior'. Patch_039 default is 'mid' so legacy
  /// rows still surface in the default filter.
  final String level;
  /// patch_039: 30 days from posting by default, bumped via renew_job.
  /// Server-side cron strips expired rows from the public feed.
  final DateTime? expiresAt;
  final DateTime createdAt;

  bool get isFilled => status == 'filled';
  bool get isOpen => status == 'open';
  bool get isHiring => postType == 'hiring';
  bool get isSeeking => postType == 'seeking';

  /// True when the post is past its 30-day shelf life. Even if the
  /// row is still active, JobsScreen should mark it Expired and
  /// the owner gets a Renew CTA.
  bool get isExpired {
    final t = expiresAt;
    if (t == null) return false;
    return t.isBefore(DateTime.now());
  }

  /// Whole days remaining until expiry, clamped to 0. Null when the
  /// row pre-dates patch_039 (shouldn't happen post-backfill).
  int? get daysUntilExpiry {
    final t = expiresAt;
    if (t == null) return null;
    final diff = t.difference(DateTime.now()).inHours;
    if (diff <= 0) return 0;
    return (diff / 24).ceil();
  }

  String levelLabel() {
    switch (level) {
      case 'entry':
        return 'Entry level';
      case 'senior':
        return 'Senior level';
      case 'mid':
      default:
        return 'Mid level';
    }
  }

  factory Job.fromJson(Map<String, dynamic> json) {
    final raw = json['requirements'];
    final reqs = raw is List
        ? raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : <String>[];
    final postType = (json['post_type'] ?? 'hiring').toString();
    return Job(
      id: json['id'].toString(),
      posterId: (json['poster_id'] ?? '').toString(),
      posterName: (json['poster_name'] ??
          (postType == 'seeking' ? 'Job seeker' : 'Recruiter')) as String,
      title: (json['title'] ?? '') as String,
      company: (json['company'] ?? '') as String,
      country: json['country'] as String?,
      province: json['province'] as String?,
      location: json['location'] as String?,
      // DB uses `job_type`; old payloads sometimes used `type`. Accept both.
      type: (json['job_type'] ?? json['type']) as String?,
      salaryMin: _readNullableDouble(json['salary_min']),
      salaryMax: _readNullableDouble(json['salary_max']),
      currency: (json['currency'] ?? 'USD') as String,
      description: json['description'] as String?,
      requirements: reqs,
      category: json['category'] as String?,
      contactPhone: json['contact_phone'] as String?,
      companyLogoUrl: json['company_logo_url'] as String?,
      isActive: json['is_active'] != false,
      status: (json['status'] ?? 'open') as String,
      postType: postType,
      level: (json['level'] ?? 'mid') as String,
      expiresAt:
          DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  /// Round-trip JSON for offline cache. Uses the same column names the
  /// API returns so `fromJson` can hydrate it without special-casing.
  Map<String, dynamic> toJson() => {
        'id': id,
        'poster_id': posterId,
        'poster_name': posterName,
        'title': title,
        'company': company,
        'country': country,
        'province': province,
        'location': location,
        'job_type': type,
        'salary_min': salaryMin,
        'salary_max': salaryMax,
        'currency': currency,
        'description': description,
        'requirements': requirements,
        'category': category,
        'contact_phone': contactPhone,
        'company_logo_url': companyLogoUrl,
        'is_active': isActive,
        'status': status,
        'post_type': postType,
        'level': level,
        'expires_at': expiresAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  String formatSalary() {
    if (salaryMin == null && salaryMax == null) return 'Negotiable';
    final symbol = currency == 'USD' ? r'$' : '$currency ';
    String fmt(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    if (salaryMin != null && salaryMax != null) {
      return '$symbol${fmt(salaryMin!)} – $symbol${fmt(salaryMax!)}';
    }
    final v = salaryMin ?? salaryMax!;
    return '$symbol${fmt(v)}';
  }

  String formatType() {
    if (type == null || type!.isEmpty) return 'Full-time';
    return type!
        .split('-')
        .map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1))
        .join('-');
  }

  static double? _readNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }
}

class JobCategory {
  const JobCategory({required this.id, required this.label});
  final String id;
  final String label;

  static const all = [
    JobCategory(id: 'all', label: 'All jobs'),
    JobCategory(id: 'tech', label: 'Tech'),
    JobCategory(id: 'healthcare', label: 'Healthcare'),
    JobCategory(id: 'education', label: 'Education'),
    JobCategory(id: 'sales', label: 'Sales'),
    JobCategory(id: 'engineering', label: 'Engineering'),
    JobCategory(id: 'hospitality', label: 'Hospitality'),
    JobCategory(id: 'other', label: 'Other'),
  ];
}

/// Experience tier for a job posting. Drives the level filter on
/// JobsScreen + the tier selector on PostJobScreen.
class JobLevel {
  const JobLevel({
    required this.id,
    required this.label,
    required this.helper,
  });
  final String id;
  final String label;
  final String helper;

  static const entry = JobLevel(
    id: 'entry',
    label: 'Entry',
    helper: 'No formal experience required. Great for first jobs.',
  );
  static const mid = JobLevel(
    id: 'mid',
    label: 'Mid',
    helper: '1–4 years of experience expected.',
  );
  static const senior = JobLevel(
    id: 'senior',
    label: 'Senior',
    helper: '5+ years of experience or team-lead expectations.',
  );

  static const all = [entry, mid, senior];

  static JobLevel byId(String id) =>
      all.firstWhere((l) => l.id == id, orElse: () => mid);
}
