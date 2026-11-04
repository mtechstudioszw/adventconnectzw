import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// "Has this password appeared in a data breach?" — the same check Supabase
/// Pro does on the server ("leaked password protection"), done in the app
/// because the project is on the Free plan (owner, 4 Nov 2026).
///
/// Uses HaveIBeenPwned's k-anonymity range API: only the FIRST 5 characters
/// of the password's SHA-1 hash leave the phone, never the password or the
/// whole hash; the phone compares the rest locally. `Add-Padding` hides even
/// how many results came back.
///
/// FAIL OPEN: no network, a timeout or any error lets the password through.
/// A breach check must never stop someone signing up on a bad connection —
/// it is a guard against reused passwords, not a gate.
///
/// Honest limit: this runs in the app, so someone talking to the server
/// directly can skip it. Supabase Pro's version cannot be skipped.
class PasswordBreachService {
  PasswordBreachService._();

  static const message =
      'This password has appeared in a data leak on another website, so '
      'attackers try it first. Please choose a different one.';

  @visibleForTesting
  static http.Client? clientOverride;

  /// SHA-1 of [password], upper-case hex, split into the 5-char prefix that
  /// is sent and the 35-char suffix that is not.
  @visibleForTesting
  static (String, String) hashParts(String password) {
    final h = sha1.convert(utf8.encode(password)).toString().toUpperCase();
    return (h.substring(0, 5), h.substring(5));
  }

  /// True only when the password is definitely in a known breach.
  static Future<bool> isBreached(String password) async {
    if (password.isEmpty) return false;
    final (prefix, suffix) = hashParts(password);
    final client = clientOverride ?? http.Client();
    try {
      final r = await client
          .get(
            Uri.parse('https://api.pwnedpasswords.com/range/$prefix'),
            headers: const {'Add-Padding': 'true'},
          )
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return false;
      for (final line in const LineSplitter().convert(r.body)) {
        final i = line.indexOf(':');
        if (i <= 0) continue;
        if (line.substring(0, i).trim() == suffix) {
          // Padding rows carry a count of 0 — they are not real matches.
          return (int.tryParse(line.substring(i + 1).trim()) ?? 0) > 0;
        }
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      if (clientOverride == null) client.close();
    }
  }
}
