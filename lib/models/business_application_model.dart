/// A user's request to be upgraded to a Business account. Mirrors
/// public.business_applications (patch_013). The status moves through
/// pending → approved | rejected and only ever flips via the external
/// admin panel.
enum BusinessApplicationStatus { pending, approved, rejected }

class BusinessApplication {
  const BusinessApplication({
    required this.id,
    required this.userId,
    required this.businessName,
    required this.category,
    required this.status,
    required this.createdAt,
    this.description,
    this.applicantWhatsapp,
    this.reviewedAt,
    this.reviewerNote,
  });

  final String id;
  final String userId;
  final String businessName;
  final String category;
  final String? description;
  final String? applicantWhatsapp;
  final BusinessApplicationStatus status;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? reviewerNote;

  bool get isPending => status == BusinessApplicationStatus.pending;
  bool get isApproved => status == BusinessApplicationStatus.approved;
  bool get isRejected => status == BusinessApplicationStatus.rejected;

  factory BusinessApplication.fromJson(Map<String, dynamic> json) {
    final statusStr = (json['status'] ?? 'pending').toString();
    final status = switch (statusStr) {
      'approved' => BusinessApplicationStatus.approved,
      'rejected' => BusinessApplicationStatus.rejected,
      _ => BusinessApplicationStatus.pending,
    };
    return BusinessApplication(
      id: json['id'].toString(),
      userId: (json['user_id'] ?? '').toString(),
      businessName: (json['business_name'] ?? '') as String,
      category: (json['category'] ?? '') as String,
      description: json['description'] as String?,
      applicantWhatsapp: json['applicant_whatsapp'] as String?,
      status: status,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.tryParse(json['reviewed_at'].toString())
          : null,
      reviewerNote: json['reviewer_note'] as String?,
    );
  }
}
