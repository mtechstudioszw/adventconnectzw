class Job {
  const Job({
    required this.id,
    required this.posterId,
    required this.title,
    required this.company,
    required this.createdAt,
    this.posterName = 'Recruiter',
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
  });

  final String id;
  final String posterId;
  final String posterName;
  final String title;
  final String company;
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
  final DateTime createdAt;

  bool get isFilled => status == 'filled';
  bool get isOpen => status == 'open';

  factory Job.fromJson(Map<String, dynamic> json) {
    final raw = json['requirements'];
    final reqs = raw is List
        ? raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : <String>[];
    return Job(
      id: json['id'].toString(),
      posterId: (json['poster_id'] ?? '').toString(),
      posterName: (json['poster_name'] ?? 'Recruiter') as String,
      title: (json['title'] ?? '') as String,
      company: (json['company'] ?? '') as String,
      location: json['location'] as String?,
      type: json['type'] as String?,
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
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

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
