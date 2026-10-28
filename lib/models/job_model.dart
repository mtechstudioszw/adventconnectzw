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
    this.payMin,
    this.payMax,
    this.payPeriod,
    this.payCurrency,
    this.isUrgent = false,
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

  /// Structured pay (patch_278): the numbers, the period ('hour', 'day',
  /// 'week', 'month', 'year', 'job') and an ISO currency.
  final double? payMin;
  final double? payMax;
  final String? payPeriod;
  final String? payCurrency;

  /// "Start now" — the poster needs someone urgently (patch_278).
  final bool isUrgent;

  /// "\$15 / day", "\$400–550 / month", or what the poster typed in the
  /// old free-text box. Null when no pay was given.
  String? get payLabel {
    if (payMin != null || payMax != null) {
      return formatPay(
        min: payMin,
        max: payMax,
        period: payPeriod,
        currency: payCurrency ?? 'USD',
      );
    }
    final typed = salaryRange?.trim();
    return (typed == null || typed.isEmpty) ? null : typed;
  }

  /// Shared by the card, the details page and the post form's preview.
  static String formatPay({
    double? min,
    double? max,
    String? period,
    String currency = 'USD',
  }) {
    final symbol = switch (currency) {
      'USD' => r'$',
      'GBP' => '£',
      'EUR' => '€',
      'ZAR' => 'R',
      _ => '$currency ',
    };
    String fmt(double v) {
      final whole = v == v.roundToDouble();
      final s = whole ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
      // 12500 → 12,500
      final parts = s.split('.');
      final digits = parts[0].replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
      return parts.length > 1 ? '$digits.${parts[1]}' : digits;
    }

    final amount = (min != null && max != null && max != min)
        ? '$symbol${fmt(min)}–${fmt(max)}'
        : '$symbol${fmt((min ?? max)!)}';
    final per = payPeriods[period];
    return per == null ? amount : '$amount / ${per.short}';
  }

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
    payMin: payMin,
    payMax: payMax,
    payPeriod: payPeriod,
    payCurrency: payCurrency,
    isUrgent: isUrgent,
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
      payMin: _readNullableDouble(json['pay_min']),
      payMax: _readNullableDouble(json['pay_max']),
      payPeriod: json['pay_period'] as String?,
      payCurrency: json['pay_currency'] as String?,
      isUrgent: json['is_urgent'] == true,
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
    'pay_min': payMin,
    'pay_max': payMax,
    'pay_period': payPeriod,
    'pay_currency': payCurrency,
    'is_urgent': isUrgent,
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
    final known = jobTypes[type];
    if (known != null) return known;
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

/// The three kinds of work the landing groups fields into, so a gardener
/// and a doctor both find their place in one tap (owner, 28 Oct 2026:
/// "it should accommodate everyone").
enum JobKind { everyday, skilled, professional }

extension JobKindX on JobKind {
  String get label => switch (this) {
    JobKind.everyday => 'Everyday work',
    JobKind.skilled => 'Skilled & medical',
    JobKind.professional => 'Professional',
  };

  String get blurb => switch (this) {
    JobKind.everyday => 'Home, garden, building, driving, shops',
    JobKind.skilled => 'Health, teaching, farming',
    JobKind.professional => 'Office, tech, media, ministry',
  };
}

/// A ready-made starting point for a post: picking "Gardener" fills the
/// title, field, type and a first draft of the description.
class JobRole {
  const JobRole(
    this.title, {
    this.type = 'full_time',
    this.level = 'entry',
    this.period = 'month',
    this.description = '',
    this.requirements = '',
  });
  final String title;
  final String type;
  final String level;
  final String period;
  final String description;
  final String requirements;
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
    required this.kind,
    this.roles = const [],
    this.needsPatch = false,
  });
  final String id;
  final String label;
  final IconData icon;
  final JobKind kind;
  final List<JobRole> roles;

  /// Added by patch_278; hidden from the post form until it runs.
  final bool needsPatch;

  static const all = [
    JobCategory(
      id: 'domestic_caregiving',
      label: 'Home & family',
      icon: Icons.home_outlined,
      kind: JobKind.everyday,
      roles: [
        JobRole(
          'Housekeeper',
          description:
              'Cleaning, laundry and ironing for a family home. Some cooking.',
          requirements: 'Honest and reliable\nReferences from past employers',
        ),
        JobRole(
          'Gardener',
          description:
              'Keep the garden tidy: mowing, weeding, watering and general '
              'yard work.',
          requirements: 'Experience with garden tools\nReliable and punctual',
        ),
        JobRole(
          'Nanny',
          description: 'Care for the children: meals, school runs, play.',
          requirements: 'Experience with children\nReferences',
        ),
        JobRole(
          'Caregiver',
          description: 'Daily care and company for an elderly family member.',
          requirements: 'Patient and kind\nFirst aid is a plus',
        ),
        JobRole(
          'Cook',
          description: 'Prepare healthy meals for a household.',
          requirements: 'Experience cooking for a family',
        ),
      ],
    ),
    JobCategory(
      id: 'construction_trades',
      label: 'Building & trades',
      icon: Icons.construction_outlined,
      kind: JobKind.everyday,
      roles: [
        JobRole(
          'Builder',
          type: 'contract',
          period: 'job',
          description: 'Building work — describe the job, size and timeline.',
          requirements: 'Own tools\nPhotos of past work',
        ),
        JobRole('Electrician', type: 'contract', period: 'job'),
        JobRole('Plumber', type: 'contract', period: 'job'),
        JobRole('Carpenter', type: 'contract', period: 'job'),
        JobRole('Welder', type: 'contract', period: 'job'),
        JobRole('Painter', type: 'contract', period: 'job'),
        JobRole('General hand', type: 'casual', period: 'day'),
      ],
    ),
    JobCategory(
      id: 'driving_transport',
      label: 'Driving & delivery',
      icon: Icons.local_shipping_outlined,
      kind: JobKind.everyday,
      roles: [
        JobRole(
          'Driver',
          level: 'mid',
          requirements: "Valid driver's licence\nClean record",
        ),
        JobRole('Delivery rider', type: 'casual', period: 'day'),
        JobRole('Truck driver', level: 'mid'),
      ],
    ),
    JobCategory(
      id: 'cleaning_security',
      label: 'Cleaning & security',
      icon: Icons.shield_outlined,
      kind: JobKind.everyday,
      needsPatch: true,
      roles: [
        JobRole('Cleaner'),
        JobRole('Security guard'),
        JobRole('Office cleaner', type: 'part_time'),
      ],
    ),
    JobCategory(
      id: 'hospitality_retail',
      label: 'Shops & hospitality',
      icon: Icons.storefront_outlined,
      kind: JobKind.everyday,
      needsPatch: true,
      roles: [
        JobRole('Shop assistant'),
        JobRole('Cashier'),
        JobRole('Waiter'),
        JobRole('Chef', level: 'mid'),
      ],
    ),
    JobCategory(
      id: 'healthcare',
      label: 'Health & medical',
      icon: Icons.local_hospital_outlined,
      kind: JobKind.skilled,
      roles: [
        JobRole(
          'Registered nurse',
          level: 'mid',
          requirements: 'Nursing diploma or degree\nCurrent practising licence',
        ),
        JobRole('Doctor', level: 'senior'),
        JobRole('Nurse aide'),
        JobRole('Pharmacist', level: 'mid'),
        JobRole('Lab scientist', level: 'mid'),
      ],
    ),
    JobCategory(
      id: 'teaching_education',
      label: 'Teaching',
      icon: Icons.school_outlined,
      kind: JobKind.skilled,
      roles: [
        JobRole(
          'Teacher',
          level: 'mid',
          requirements: 'Teaching qualification\nSubject specialism',
        ),
        JobRole('Tutor', type: 'part_time', period: 'hour'),
        JobRole('ECD teacher'),
        JobRole('Lecturer', level: 'senior'),
      ],
    ),
    JobCategory(
      id: 'farming_agriculture',
      label: 'Farming',
      icon: Icons.agriculture_outlined,
      kind: JobKind.skilled,
      roles: [
        JobRole('Farm worker', type: 'casual', period: 'day'),
        JobRole('Herdsman'),
        JobRole('Farm manager', level: 'senior'),
      ],
    ),
    JobCategory(
      id: 'business_admin',
      label: 'Office & finance',
      icon: Icons.business_center_outlined,
      kind: JobKind.professional,
      roles: [
        JobRole('Accountant', level: 'mid'),
        JobRole('Admin assistant'),
        JobRole('Receptionist'),
        JobRole('HR officer', level: 'mid'),
        JobRole('Sales representative'),
      ],
    ),
    JobCategory(
      id: 'it_technology',
      label: 'Tech & digital',
      icon: Icons.computer_outlined,
      kind: JobKind.professional,
      roles: [
        JobRole('Software developer', level: 'mid'),
        JobRole('IT support'),
        JobRole('Data analyst', level: 'mid'),
      ],
    ),
    JobCategory(
      id: 'creative_media',
      label: 'Media & creative',
      icon: Icons.palette_outlined,
      kind: JobKind.professional,
      needsPatch: true,
      roles: [
        JobRole('Graphic designer', type: 'contract', period: 'job'),
        JobRole('Videographer', type: 'contract', period: 'job'),
        JobRole('Musician', type: 'contract', period: 'job'),
      ],
    ),
    JobCategory(
      id: 'ministry_church',
      label: 'Church & ministry',
      icon: Icons.church_outlined,
      kind: JobKind.professional,
      roles: [
        JobRole('Pastor', level: 'senior'),
        JobRole('Bible worker'),
        JobRole('Church secretary', type: 'part_time'),
      ],
    ),
    JobCategory(
      id: 'other',
      label: 'Other',
      icon: Icons.work_outline,
      kind: JobKind.professional,
    ),
  ];

  static JobCategory? byId(String? id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  static String labelFor(String? id) => byId(id)?.label ?? 'Other';

  static List<JobCategory> ofKind(JobKind k) => [
    for (final c in all)
      if (c.kind == k && c.id != 'other') c,
  ];
}

/// Employment types the database accepts (jobs_job_type_check).
/// 'casual' arrives with patch_278.
const jobTypes = <String, String>{
  'full_time': 'Full-time',
  'part_time': 'Part-time',
  'contract': 'Contract',
  'casual': 'Casual / day work',
  'internship': 'Internship',
  'volunteer': 'Volunteer',
};

class PayPeriod {
  const PayPeriod(this.label, this.short);
  final String label;
  final String short;
}

/// Pay periods (patch_278).
const payPeriods = <String, PayPeriod>{
  'hour': PayPeriod('Per hour', 'hour'),
  'day': PayPeriod('Per day', 'day'),
  'week': PayPeriod('Per week', 'week'),
  'month': PayPeriod('Per month', 'month'),
  'year': PayPeriod('Per year', 'year'),
  'job': PayPeriod('For the job', 'job'),
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
