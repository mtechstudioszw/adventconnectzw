import 'package:flutter/material.dart';

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
    this.salaryRange,
    this.sabbathFriendly = false,
    this.isSdaInstitution = false,
    this.contactEmail,
    this.workArrangement,
    this.applyInstructions,
    this.applyUrl,
    this.pageId,
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

  /// What the poster typed in the salary box ("\$400 – \$550"). The
  /// `jobs` table stores salary ONLY as this text — there are no
  /// salary_min / salary_max columns — so every job used to read
  /// "Negotiable" whatever its poster entered.
  final String? salaryRange;

  /// Saved by the post form all along, and never read back: not shown on
  /// cards, and wiped by an edit because the form started them empty.
  final bool sabbathFriendly;
  final bool isSdaInstitution;
  final String? contactEmail;

  /// 'on_site' | 'remote' | 'hybrid' (patch_278). Null on older rows.
  final String? workArrangement;

  /// How to apply, in the employer's words (patch_278).
  final String? applyInstructions;

  /// An application form link (patch_278).
  final String? applyUrl;

  /// The employer's organization Page — its company profile (patch_278).
  final String? pageId;

  String? get workArrangementLabel => switch (workArrangement) {
    'on_site' => 'On-site',
    'remote' => 'Remote',
    'hybrid' => 'Hybrid',
    _ => null,
  };

  /// Every field carried. The details screen rebuilt the job by hand after
  /// "Mark as filled" / "Reopen" and dropped country, province, post type,
  /// level and expiry — so the page lost them until it was reopened.
  Job copyWith({String? status}) => Job(
    id: id,
    posterId: posterId,
    posterName: posterName,
    title: title,
    company: company,
    createdAt: createdAt,
    country: country,
    province: province,
    location: location,
    type: type,
    salaryMin: salaryMin,
    salaryMax: salaryMax,
    currency: currency,
    description: description,
    requirements: requirements,
    category: category,
    contactPhone: contactPhone,
    companyLogoUrl: companyLogoUrl,
    isActive: isActive,
    status: status ?? this.status,
    postType: postType,
    level: level,
    expiresAt: expiresAt,
    salaryRange: salaryRange,
    sabbathFriendly: sabbathFriendly,
    isSdaInstitution: isSdaInstitution,
    contactEmail: contactEmail,
    workArrangement: workArrangement,
    applyInstructions: applyInstructions,
    applyUrl: applyUrl,
    pageId: pageId,
  );

  /// "Town, Province", without saying "Harare, Harare" twice.
  String get place {
    final parts = <String>[];
    for (final p in [location, province]) {
      final v = (p ?? '').trim();
      if (v.isEmpty) continue;
      if (parts.any((x) => x.toLowerCase() == v.toLowerCase())) continue;
      parts.add(v);
    }
    return parts.join(', ');
  }

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
    // The column is TEXT (one requirement per line, as the form writes it);
    // a list is still accepted for old cached payloads. Reading only lists
    // meant requirements never showed on any job.
    final reqs = raw is List
        ? raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : raw is String
        ? raw
              .split('\n')
              .map((l) => l.replaceFirst(RegExp(r'^\s*[-•*]\s*'), '').trim())
              .where((l) => l.isNotEmpty)
              .toList()
        : <String>[];
    final postType = (json['post_type'] ?? 'hiring').toString();
    return Job(
      id: json['id'].toString(),
      posterId: (json['poster_id'] ?? '').toString(),
      posterName:
          (json['poster_name'] ??
                  (postType == 'seeking' ? 'Job seeker' : 'Recruiter'))
              as String,
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
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      salaryRange: (json['salary_range'] as String?)?.trim(),
      sabbathFriendly: json['sabbath_friendly'] == true,
      isSdaInstitution: json['is_sda_institution'] == true,
      contactEmail: json['contact_email'] as String?,
      workArrangement: json['work_arrangement'] as String?,
      applyInstructions: (json['apply_instructions'] as String?)?.trim(),
      applyUrl: (json['apply_url'] as String?)?.trim(),
      pageId: json['page_id']?.toString(),
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
    'salary_range': salaryRange,
    'sabbath_friendly': sabbathFriendly,
    'is_sda_institution': isSdaInstitution,
    'contact_email': contactEmail,
    'work_arrangement': workArrangement,
    'apply_instructions': applyInstructions,
    'apply_url': applyUrl,
    'page_id': pageId,
  };

  String formatSalary() {
    final typed = salaryRange;
    if (typed != null && typed.isNotEmpty) return typed;
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
    // DB values are snake_case ("full_time"); splitting only on '-' showed
    // "Full_time" on every card.
    final words = type!.split(RegExp('[-_]')).join('-');
    return words[0].toUpperCase() + words.substring(1);
  }

  static double? _readNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }
}

/// Job categories — ONE list for posting and browsing, with the ids the
/// database's jobs_category_check accepts.
///
/// The browse chips used to carry their own ids ('tech', 'education',
/// 'sales'…) that the database never stores, so picking any of them always
/// showed "no jobs".
class JobCategory {
  const JobCategory({
    required this.id,
    required this.label,
    required this.icon,
  });
  final String id;
  final String label;
  final IconData icon;

  static const all = [
    JobCategory(
      id: 'teaching_education',
      label: 'Teaching & Education',
      icon: Icons.school_outlined,
    ),
    JobCategory(
      id: 'healthcare',
      label: 'Healthcare',
      icon: Icons.local_hospital_outlined,
    ),
    JobCategory(
      id: 'it_technology',
      label: 'IT & Technology',
      icon: Icons.computer_outlined,
    ),
    JobCategory(
      id: 'business_admin',
      label: 'Business & Admin',
      icon: Icons.business_center_outlined,
    ),
    JobCategory(
      id: 'ministry_church',
      label: 'Ministry & Church',
      icon: Icons.church_outlined,
    ),
    JobCategory(
      id: 'construction_trades',
      label: 'Construction & Trades',
      icon: Icons.construction_outlined,
    ),
    JobCategory(
      id: 'farming_agriculture',
      label: 'Farming & Agriculture',
      icon: Icons.agriculture_outlined,
    ),
    JobCategory(
      id: 'driving_transport',
      label: 'Driving & Transport',
      icon: Icons.local_shipping_outlined,
    ),
    JobCategory(
      id: 'domestic_caregiving',
      label: 'Domestic & Caregiving',
      icon: Icons.volunteer_activism_outlined,
    ),
    JobCategory(id: 'other', label: 'Other', icon: Icons.work_outline),
  ];

  static JobCategory? byId(String? id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  static String labelFor(String? id) => byId(id)?.label ?? 'Other';
}

/// Employment types the database accepts (jobs_job_type_check).
const jobTypes = <String, String>{
  'full_time': 'Full-time',
  'part_time': 'Part-time',
  'contract': 'Contract',
  'internship': 'Internship',
  'volunteer': 'Volunteer',
};

/// Work arrangements (patch_278).
const workArrangements = <String, String>{
  'on_site': 'On-site',
  'hybrid': 'Hybrid',
  'remote': 'Remote',
};

/// Experience tier for a job posting. Drives the level filter on
/// JobsScreen + the tier selector on PostJobScreen.
class JobLevel {
  const JobLevel({required this.id, required this.label, required this.helper});
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
