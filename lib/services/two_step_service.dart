import 'package:supabase_flutter/supabase_flutter.dart';

/// Two-step login with an authenticator app (Google Authenticator,
/// Microsoft Authenticator, Authy, 1Password…), on Supabase Auth's own MFA.
///
/// Owner, 3 Nov 2026: "I need maximum security … email and password is not
/// enough." A password can be phished, guessed or reused from another
/// site's leak; a code that changes every 30 seconds on the member's own
/// phone cannot be.
///
/// ## How it holds
///
/// * Signing in with a password (or Google / Apple) gives a session at
///   assurance level **aal1**. A member with a verified factor must reach
///   **aal2** before the app will show anything — the router sends every
///   location to the code screen while [challengePending] is true
///   (router_config.dart), so no entry path (password, Google, Apple,
///   splash restore, biometric unlock) can skip it.
/// * The database enforces the same thing for the most private data
///   (patch 311, `mfa_ok()`), so a stolen aal1 token used outside the app
///   still cannot read messages.
///
/// ## Opt-in
///
/// It is not forced on everyone: a member who loses the phone with the
/// authenticator on it is locked out until support resets it
/// (`admin_reset_two_step`, patch 311). That is the trade every bank app
/// makes, and members choose it for themselves.
class TwoStepService {
  TwoStepService._();

  static const issuer = 'Adventist Super App';

  static GoTrueMFAApi get _mfa => Supabase.instance.client.auth.mfa;

  /// Signed in with a password but the account needs the authenticator
  /// code too. Synchronous (reads the local token), so the router can ask
  /// on every navigation. Any failure — Supabase not initialised, no
  /// session — reads as "nothing pending": the sign-in screens handle a
  /// missing session already.
  static bool get challengePending {
    try {
      final r = _mfa.getAuthenticatorAssuranceLevel();
      return r.currentLevel == AuthenticatorAssuranceLevels.aal1 &&
          r.nextLevel == AuthenticatorAssuranceLevels.aal2;
    } catch (_) {
      return false;
    }
  }

  /// Verified authenticator factors on this account (normally 0 or 1).
  static Future<List<Factor>> verifiedFactors() async {
    final r = await _mfa.listFactors();
    return r.totp;
  }

  static bool get isOn {
    try {
      final factors = Supabase.instance.client.auth.currentUser?.factors;
      return factors?.any((f) =>
              f.factorType == FactorType.totp &&
              f.status == FactorStatus.verified) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Starts setting up. Clears any half-finished attempt first — Supabase
  /// refuses a second factor with the same name, so a member who backed
  /// out of the QR screen once could otherwise never try again.
  static Future<TOTPEnrollment?> startSetup() async {
    final all = (await _mfa.listFactors()).all;
    for (final f in all) {
      if (f.factorType == FactorType.totp &&
          f.status == FactorStatus.unverified) {
        try {
          await _mfa.unenroll(f.id);
        } catch (_) {}
      }
    }
    final r = await _mfa.enroll(
      factorType: FactorType.totp,
      issuer: issuer,
      friendlyName: 'Authenticator ${DateTime.now().millisecondsSinceEpoch}',
    );
    _pendingFactorId = r.id;
    return r.totp;
  }

  static String? _pendingFactorId;

  /// Confirms the first code from the app. Null on success, else a message
  /// a member can act on.
  static Future<String?> finishSetup(String code) async {
    final id = _pendingFactorId;
    if (id == null) return 'Start again — the setup expired.';
    final err = await _verify(id, code);
    if (err == null) _pendingFactorId = null;
    return err;
  }

  /// The sign-in step: checks [code] against the account's factor and
  /// lifts the session to aal2.
  static Future<String?> verifyLogin(String code) async {
    try {
      final factors = Supabase.instance.client.auth.currentUser?.factors
              ?.where((f) =>
                  f.factorType == FactorType.totp &&
                  f.status == FactorStatus.verified)
              .toList() ??
          const <Factor>[];
      if (factors.isEmpty) return null; // nothing to check
      return await _verify(factors.first.id, code);
    } catch (e) {
      return friendlyError(e);
    }
  }

  /// Turns it off. Supabase only allows this from an aal2 session, which a
  /// member with two-step on always has once past the code screen.
  static Future<String?> turnOff() async {
    try {
      for (final f in await verifiedFactors()) {
        await _mfa.unenroll(f.id);
      }
      await Supabase.instance.client.auth.refreshSession();
      return null;
    } catch (e) {
      return friendlyError(e);
    }
  }

  static Future<String?> _verify(String factorId, String code) async {
    final clean = code.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6}$').hasMatch(clean)) {
      return 'Enter the 6-digit code from your authenticator app.';
    }
    try {
      await _mfa.challengeAndVerify(factorId: factorId, code: clean);
      return null;
    } catch (e) {
      return friendlyError(e);
    }
  }

  static String friendlyError(Object e) {
    final msg = (e is AuthException ? e.message : e.toString()).toLowerCase();
    final status = e is AuthException ? e.statusCode : null;
    if (status == '429' || msg.contains('rate limit') || msg.contains('too many')) {
      return 'Too many tries. Wait a few minutes, then try again.';
    }
    if (msg.contains('invalid') || msg.contains('code')) {
      return 'That code is wrong or has expired. Codes change every 30 '
          'seconds — check your phone\'s clock is set automatically.';
    }
    if (msg.contains('aal2')) {
      return 'Sign out and back in with your code, then try again.';
    }
    if (msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('failed host lookup')) {
      return 'No connection. Check your internet and try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}
