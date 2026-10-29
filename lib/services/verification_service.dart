import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

/// What the gold tick says about someone. Mirrors the CHECK on
/// `verification_requests.category` (patch 289).
enum VerifyCategory {
  member('member', 'Church member'),
  pastor('pastor', 'Pastor or elder'),
  ministry('ministry', 'Ministry or church leader'),
  musician('musician', 'Musician or choir'),
  business('business', 'Business owner'),
  publicFigure('public_figure', 'Public figure');

  const VerifyCategory(this.id, this.label);
  final String id;
  final String label;

  static VerifyCategory parse(Object? raw) => VerifyCategory.values.firstWhere(
    (c) => c.id == raw,
    orElse: () => VerifyCategory.member,
  );
}

enum VerifyStatus {
  pending,
  approved,
  rejected,
  revoked;

  static VerifyStatus parse(Object? raw) => VerifyStatus.values.firstWhere(
    (s) => s.name == raw,
    orElse: () => VerifyStatus.pending,
  );
}

/// One application for the gold tick.
class VerificationRequest {
  const VerificationRequest({
    required this.id,
    required this.userId,
    required this.kind,
    required this.legalName,
    required this.category,
    required this.status,
    required this.createdAt,
    this.pageId,
    this.pageName,
    this.reason,
    this.reviewedAt,
    this.idDocPath,
    this.selfiePath,
    this.memberName,
    this.memberPhotoUrl,
  });

  final String id;
  final String userId;

  /// 'person' or 'page'.
  final String kind;
  final String? pageId;
  final String? pageName;
  final String legalName;
  final VerifyCategory category;
  final VerifyStatus status;
  final String? reason;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  /// Paths in the private bucket. Null once a decision has been made —
  /// the files are deleted then.
  final String? idDocPath;
  final String? selfiePath;

  /// For the admin queue.
  final String? memberName;
  final String? memberPhotoUrl;

  bool get isPage => kind == 'page';

  /// When a rejected applicant may try again (patch 289's 7-day wait).
  DateTime? get canReapplyAt => status == VerifyStatus.rejected
      ? (reviewedAt ?? createdAt).add(const Duration(days: 7))
      : null;

  factory VerificationRequest.fromJson(Map<String, dynamic> j) {
    final profile = j['profiles'];
    final page = j['pages'];
    return VerificationRequest(
      id: j['id'].toString(),
      userId: (j['user_id'] ?? '').toString(),
      kind: (j['kind'] ?? 'person').toString(),
      pageId: j['page_id']?.toString(),
      pageName: page is Map ? page['name'] as String? : null,
      legalName: (j['legal_name'] ?? '').toString(),
      category: VerifyCategory.parse(j['category']),
      status: VerifyStatus.parse(j['status']),
      reason: j['reason'] as String?,
      createdAt:
          DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
      reviewedAt: DateTime.tryParse('${j['reviewed_at']}')?.toLocal(),
      idDocPath: j['id_doc_path'] as String?,
      selfiePath: j['selfie_path'] as String?,
      memberName: profile is Map ? profile['full_name'] as String? : null,
      memberPhotoUrl: profile is Map
          ? profile['profile_photo_url'] as String?
          : null,
    );
  }
}

/// A plain-English reason something didn't work.
class VerificationException implements Exception {
  const VerificationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The gold tick (patch 289): apply with an ID photo and a selfie, a super
/// admin approves or rejects, and the tick shows while the member holds
/// any paid level. The server decides every part of that; this class only
/// asks and uploads.
///
/// ID photos are personal data. They go to a PRIVATE bucket only the
/// member and super admins can read, and are deleted as soon as a decision
/// is made.
class VerificationService {
  VerificationService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static const bucket = 'verification_docs';

  static const _cols =
      'id, user_id, kind, page_id, legal_name, category, status, reason, '
      'created_at, reviewed_at, id_doc_path, selfie_path';

  /// Bumped after an apply, withdraw or decision so screens refresh.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// The member's latest request for their own tick (or for [pageId]).
  /// Null when they have never applied, or before patch 289 runs.
  static Future<VerificationRequest?> mine({String? pageId}) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;
      var q = _client
          .from('verification_requests')
          .select(_cols)
          .eq('user_id', uid);
      q = pageId == null
          ? q.eq('kind', 'person')
          : q.eq('kind', 'page').eq('page_id', pageId);
      final rows = await q.order('created_at', ascending: false).limit(1);
      final list = rows as List;
      if (list.isEmpty) return null;
      return VerificationRequest.fromJson(list.first as Map<String, dynamic>);
    } catch (e) {
      debugPrint('VerificationService.mine failed: $e');
      return null;
    }
  }

  /// Upload both photos, then file the request. If filing fails the
  /// photos are removed again, so nothing is left behind in storage.
  static Future<VerificationRequest> apply({
    required String legalName,
    required VerifyCategory category,
    required Uint8List idPhoto,
    required Uint8List selfie,
    String? pageId,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw const VerificationException('Please sign in again.');
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final idPath = '$uid/${stamp}_id.jpg';
    final selfiePath = '$uid/${stamp}_selfie.jpg';
    final storage = _client.storage.from(bucket);
    const options = FileOptions(contentType: 'image/jpeg', upsert: false);

    try {
      await storage.uploadBinary(idPath, idPhoto, fileOptions: options);
      await storage.uploadBinary(selfiePath, selfie, fileOptions: options);
    } catch (e) {
      debugPrint('Verification upload failed: $e');
      await _removeQuietly([idPath, selfiePath]);
      throw const VerificationException(
        "Your photos didn't upload. Check your connection and try again.",
      );
    }

    try {
      final row = await _client
          .from('verification_requests')
          .insert({
            'user_id': uid,
            'kind': pageId == null ? 'person' : 'page',
            'page_id': pageId,
            'legal_name': legalName.trim(),
            'category': category.id,
            'id_doc_path': idPath,
            'selfie_path': selfiePath,
          })
          .select(_cols)
          .single();
      revision.value++;
      return VerificationRequest.fromJson(row);
    } on PostgrestException catch (e) {
      await _removeQuietly([idPath, selfiePath]);
      throw VerificationException(_friendly(e));
    } catch (e) {
      await _removeQuietly([idPath, selfiePath]);
      throw const VerificationException(
        "We couldn't send your request. Please try again.",
      );
    }
  }

  /// Take back a request that hasn't been decided yet.
  static Future<void> withdraw(VerificationRequest r) async {
    await _client.from('verification_requests').delete().eq('id', r.id);
    await _removeQuietly([?r.idDocPath, ?r.selfiePath]);
    revision.value++;
  }

  // ------------------------------------------------------------------
  //  Super admin
  // ------------------------------------------------------------------

  /// Requests waiting for a decision, oldest first.
  static Future<List<VerificationRequest>> pending() async {
    final rows = await _client
        .from('verification_requests')
        .select('$_cols, profiles!verification_requests_user_id_fkey'
            '(full_name, profile_photo_url), pages(name)')
        .eq('status', 'pending')
        .order('created_at');
    return (rows as List)
        .map((r) => VerificationRequest.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Approved ticks, newest first — so one can be revoked.
  static Future<List<VerificationRequest>> approved({int limit = 50}) async {
    final rows = await _client
        .from('verification_requests')
        .select('$_cols, profiles!verification_requests_user_id_fkey'
            '(full_name, profile_photo_url), pages(name)')
        .eq('status', 'approved')
        .order('reviewed_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => VerificationRequest.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// A 10-minute link to view one document. Never stored.
  static Future<String?> viewUrl(String? path) async {
    if (path == null) return null;
    try {
      return await _client.storage.from(bucket).createSignedUrl(path, 600);
    } catch (e) {
      debugPrint('Verification signed URL failed: $e');
      return null;
    }
  }

  /// 'approve', 'reject' or 'revoke'. A reason is required for the last
  /// two — the member is told it. The documents are deleted afterwards.
  static Future<void> review(
    VerificationRequest r,
    String action, {
    String? reason,
  }) async {
    try {
      await _client.rpc('review_verification', params: {
        'p_id': r.id,
        'p_action': action,
        'p_reason': reason,
      });
    } on PostgrestException catch (e) {
      throw VerificationException(e.message);
    }
    await _removeQuietly([?r.idDocPath, ?r.selfiePath]);
    revision.value++;
  }

  static Future<void> _removeQuietly(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _client.storage.from(bucket).remove(paths);
    } catch (e) {
      debugPrint('Verification cleanup failed (${paths.length} files): $e');
    }
  }

  static String _friendly(PostgrestException e) {
    final text = '${e.message} ${e.hint ?? ''} ${e.details ?? ''}';
    if (text.contains('VERIFY_COOLDOWN')) {
      return 'You can apply again 7 days after the last decision.';
    }
    if (text.contains('VERIFY_DOCS')) {
      return 'Add a photo of your ID and a selfie.';
    }
    if (e.code == '23505') {
      return 'You already have a request waiting or approved.';
    }
    if (e.code == '42501') {
      return e.message;
    }
    return "We couldn't send your request. Please try again.";
  }
}
