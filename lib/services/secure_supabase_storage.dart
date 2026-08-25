import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// supabase_flutter's session-persistence adapter, backed by
/// [FlutterSecureStorage] instead of SharedPreferences.
///
/// CLAUDE.md mandates secure storage for auth tokens (never
/// SharedPreferences). The default [SharedPreferencesLocalStorage]
/// would have:
///   - left tokens in unencrypted SharedPreferences on Android
///   - failed silently on some OEMs / fresh installs, which is the
///     root cause of "the app asks me to log in every time I reopen
///     it" — the SP write succeeds but the read returns null on the
///     next cold start.
///
/// Storing the session under a single key (`supabase_session`) on the
/// Android EncryptedSharedPreferences / iOS Keychain is both compliant
/// and reliable across restarts.
///
/// # Why this file has retries and a memory cache in it
///
/// Founder report, 25 Aug 2026: **"when you answer the call the app logs
/// you out."**
///
/// Nothing in the calling code signs anybody out — it never touches auth
/// at all. The sign-out is here, and answering a call is simply the one
/// everyday action that reliably provokes it:
///
///   1. a call arrives on a phone that is asleep and LOCKED;
///   2. the member taps Accept on the lock screen, and the CallKit
///      plugin launches the app — so `main()` runs, and Supabase asks
///      this class to restore the session;
///   3. on Android, `EncryptedSharedPreferences` is backed by the
///      Android Keystore, and a keystore read **can throw while the
///      device is still locked**. On iOS, a `first_unlock` keychain item
///      is genuinely unavailable before the first unlock after a reboot;
///   4. the old code called `_storage.read(...)` bare. A throw here
///      breaks session recovery, and a null here means something worse
///      than an error — it means *there is no session*;
///   5. the app comes up on the login screen, while the member's
///      session is alive and healthy on the server.
///
/// The signature is the same as the background-isolate bug this project
/// already fixed once (see `AppBootstrap`): the server shows a valid
/// session and there is no logout in the audit log, because nobody
/// logged out. The cause is different — that one revoked the token, this
/// one merely fails to read it — but the member cannot tell them apart.
///
/// So reads are defended three ways, in order of how often each saves it:
///
///   * **An in-memory copy.** Once the session has been read or written
///     in this process, later reads never touch the keystore at all.
///     This alone covers every read after the first.
///   * **Retries.** A keystore that is unavailable because the device is
///     locked becomes available moments later, so a failed read waits
///     and asks again rather than reporting "no session" instantly.
///   * **Rethrowing rather than returning null** when every attempt
///     fails. They are NOT the same answer: null is a positive claim
///     that the member is signed out and takes them to the login screen,
///     while an error leaves the session unrestored and recoverable.
///     Given the choice, fail loudly over lying quietly.
///
/// Writes are cached first and persisted after, for the same reason — a
/// token refresh that cannot reach the keystore must not lose the new
/// token it was handed.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage();

  static const _sessionKey = 'supabase_session';

  /// How hard to try before giving up on a locked or busy keystore.
  /// Three attempts over ~700ms — long enough to cover the gap between
  /// an app launching on the lock screen and the keystore coming back,
  /// short enough that a genuinely broken read does not stall startup.
  static const int _readAttempts = 3;
  static const Duration _retryDelay = Duration(milliseconds: 220);

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// The last session string this process has seen, from either a read
  /// or a write.
  ///
  /// Not a performance cache — a correctness one. It is what makes a
  /// keystore that goes unavailable mid-session (device locks, OEM
  /// power-saving kills the keystore service) harmless rather than a
  /// sign-out.
  static String? _cached;

  /// True once [_cached] reflects storage, including the case where
  /// storage genuinely holds nothing. Without this a null cache is
  /// ambiguous between "never read" and "read, and there is no
  /// session".
  static bool _cacheValid = false;

  @override
  Future<void> initialize() async {
    // Nothing to do — secure storage is lazy.
  }

  @override
  Future<String?> accessToken() => _read();

  @override
  Future<bool> hasAccessToken() async {
    final value = await _read();
    return value != null && value.isNotEmpty;
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    // Cache FIRST. If the write below throws, this process still holds
    // the newest session, and the next refresh will try to persist
    // again — losing the disk copy costs a re-login after a restart,
    // losing the memory copy costs one immediately.
    _cached = persistSessionString;
    _cacheValid = true;
    try {
      await _storage.write(key: _sessionKey, value: persistSessionString);
    } catch (e) {
      debugPrint(
        'SecureLocalStorage: could not persist the session ($e). '
        'The session is live in memory; it may not survive a restart.',
      );
    }
  }

  @override
  Future<void> removePersistedSession() async {
    // This one IS a deliberate sign-out, so the cache must go with it —
    // otherwise the next read hands back the session we were told to
    // forget. Cleared even if the delete throws, for the same reason.
    _cached = null;
    _cacheValid = true;
    try {
      await _storage.delete(key: _sessionKey);
    } catch (e) {
      debugPrint('SecureLocalStorage: could not delete the session: $e');
    }
  }

  /// Read, with the three defences described on the class.
  static Future<String?> _read() async {
    if (_cacheValid) return _cached;

    Object? lastError;
    for (var attempt = 1; attempt <= _readAttempts; attempt++) {
      try {
        final value = await _storage.read(key: _sessionKey);
        _cached = value;
        _cacheValid = true;
        return value;
      } catch (e) {
        lastError = e;
        debugPrint(
          'SecureLocalStorage: session read failed '
          '(attempt $attempt/$_readAttempts): $e',
        );
        if (attempt < _readAttempts) await Future.delayed(_retryDelay);
      }
    }

    // Every attempt failed. Do NOT cache this and do NOT return null:
    // the next call gets to try again on a keystore that may since have
    // unlocked, and the caller learns that we could not read rather than
    // being told the member is signed out.
    throw StateError(
      'Could not read the stored session from secure storage after '
      '$_readAttempts attempts. Last error: $lastError',
    );
  }

  /// Forget the in-memory copy without touching storage.
  ///
  /// For tests, and for any future code that needs the next read to go
  /// back to the keystore.
  @visibleForTesting
  static void debugInvalidateCache() {
    _cached = null;
    _cacheValid = false;
  }
}
