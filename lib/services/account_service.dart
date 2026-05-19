import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/business_application_model.dart';

/// Snapshot of the signed-in user's account / business state. Returned
/// by [AccountService.fetchMyAccount] so the rest of the UI can branch
/// without reaching into Supabase itself.
class AccountState {
  const AccountState({
    required this.userId,
    required this.isBusiness,
    this.latestApplication,
  });

  final String userId;
  final bool isBusiness;
  final BusinessApplication? latestApplication;

  bool get hasPendingApplication =>
      latestApplication != null && latestApplication!.isPending;

  bool get hasRejectedApplication =>
      latestApplication != null && latestApplication!.isRejected;

  bool get canSell => isBusiness;
  bool get canClaimChurch => isBusiness;
}

/// Reads + writes the personal-vs-business account state.
///
/// Approvals are not done from the app — only the external admin
/// panel can flip `profiles.is_business` and update the application
/// row. The app surface here is read-only for status and write-only
/// for submitting / re-submitting an application.
class AccountService {
  AccountService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _profilesTable = 'profiles';
  static const _appsTable = 'business_applications';

  /// Pull the live state from the server. Cheap — one row from
  /// profiles + the newest business_applications row for the user.
  static Future<AccountState?> fetchMyAccount() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final profile = await _client
        .from(_profilesTable)
        .select('id, is_business')
        .eq('id', user.id)
        .maybeSingle();
    if (profile == null) return null;

    final isBusiness = profile['is_business'] == true;

    final apps = await _client
        .from(_appsTable)
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(1);
    final list = apps as List;
    final latest = list.isEmpty
        ? null
        : BusinessApplication.fromJson(list.first as Map<String, dynamic>);

    return AccountState(
      userId: user.id,
      isBusiness: isBusiness,
      latestApplication: latest,
    );
  }

  /// Submit a business-account application. Throws if there's already
  /// a pending application (server-side partial unique index rejects
  /// duplicates). Returns the freshly inserted row.
  static Future<BusinessApplication> applyForBusiness({
    required String businessName,
    required String category,
    String? description,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to apply.');
    }
    final inserted = await _client
        .from(_appsTable)
        .insert({
          'user_id': user.id,
          'business_name': businessName.trim(),
          'category': category.trim(),
          if (description != null && description.trim().isNotEmpty)
            'description': description.trim(),
        })
        .select()
        .single();
    return BusinessApplication.fromJson(inserted);
  }
}
