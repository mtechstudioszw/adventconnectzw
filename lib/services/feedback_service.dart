import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_version.dart';

class FeedbackService {
  FeedbackService._();

  static final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'feedback';

  // Read from the ONE version constant, not a copy.
  //
  // This said '1.0.0+1' — a value that stopped being true before 1.1
  // shipped. Every feedback report since has been stamped with it, so the
  // one field that answers "which build was this reported against?" has
  // been wrong on every row in the table. That is worse than absent: it
  // sends you looking for a bug in a version nobody is running.
  static const String _appVersion = '$kAppVersionName+$kAppBuildNumber';

  static Future<void> submit({
    required String category,
    required String subject,
    required String body,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to send feedback.');
    }

    await _client.from(_table).insert({
      'user_id': user.id,
      'category': category,
      'subject': subject.trim(),
      'body': body.trim(),
      'app_version': _appVersion,
      'platform': _platformLabel(),
    });
  }

  static String _platformLabel() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}
