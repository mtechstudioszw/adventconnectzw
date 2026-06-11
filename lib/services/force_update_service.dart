import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_version.dart';

/// Reads the remote minimum-build requirement (app_config, patch_091) and
/// decides whether the running build must be force-updated. Bump the
/// `min_build_android` value in Supabase to lock out older installs that
/// contain this gate (i.e. this build forward).
class ForceUpdateService {
  ForceUpdateService._();
  static final SupabaseClient _client = Supabase.instance.client;

  /// True when the installed build is below the required minimum. Fails
  /// open (false) on any error so a flaky network never locks users out.
  static Future<bool> updateRequired() async {
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'min_build_android')
          .maybeSingle();
      final min = int.tryParse((row?['value'] ?? '1').toString()) ?? 1;
      return kAppBuildNumber < min;
    } catch (_) {
      return false;
    }
  }
}
