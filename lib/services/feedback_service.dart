import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

class FeedbackService {
  FeedbackService._();

  static final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'feedback';

  // Keep in sync with pubspec.yaml `version:`. Hardcoded because
  // package_info_plus isn't installed and pub get is off-limits on
  // the user's connection. Bump on each release.
  static const String _appVersion = '1.0.0+1';

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
