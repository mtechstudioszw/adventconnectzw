import 'package:advent_connect_zw/models/product_model.dart';
import 'package:advent_connect_zw/services/account_mode_service.dart';
import 'package:advent_connect_zw/services/biometric_service.dart';
import 'package:advent_connect_zw/services/cart_service.dart';
import 'package:advent_connect_zw/services/messaging_service.dart';
import 'package:advent_connect_zw/services/secure_storage_service.dart';
import 'package:advent_connect_zw/services/session_reset.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the two sign-out leaks reported on 3 Aug 2026:
/// a new account briefly showing the PREVIOUS account's data (#20), and
/// biometric unlock carrying across accounts on one phone (#21).
///
/// Both have the same root cause: signing out does not restart the Dart
/// isolate, so every `static` field outlives the session. Wiping storage
/// was never enough on its own.
///
/// Secure storage is backed by an in-memory map here so the real
/// key-scoping and the real `clearAll()` preservation rules run — those
/// rules ARE the fix for #21, so faking them out would test nothing.
/// CacheService's Hive box is never opened under the test binding, so its
/// helpers no-op and the basket stays purely in-memory.
const _storageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

Product _product(String id) => Product(
  id: id,
  sellerId: 'seller-a',
  sellerName: 'Test Store',
  title: 'Product $id',
  price: 10,
  currency: 'USD',
  imageUrls: const [],
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> storage;

  setUp(() {
    storage = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, (call) async {
          final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
          switch (call.method) {
            case 'write':
              storage[args['key'] as String] = args['value'] as String;
              return null;
            case 'read':
              return storage[args['key'] as String];
            case 'readAll':
              return Map<String, String>.from(storage);
            case 'delete':
              storage.remove(args['key'] as String);
              return null;
            case 'deleteAll':
              storage.clear();
              return null;
            case 'containsKey':
              return storage.containsKey(args['key'] as String);
            default:
              return null;
          }
        });
    CartService.resetForTest();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, null);
  });

  group('SessionReset.onSignOut (#20)', () {
    test('empties the basket the previous account left behind', () async {
      await CartService.add(_product('1'), qty: 2);
      expect(CartService.count, 2, reason: 'guard: basket should be primed');

      await SessionReset.onSignOut();

      expect(CartService.count, 0);
      expect(CartService.items, isEmpty);
    });

    test('zeroes the unread badge', () async {
      // The bottom-nav badge paints this on EVERY tab, so it was the
      // previous account's unread count staring at the new one until
      // their own inbox fetch landed.
      MessagingService.unreadTotal.value = 7;

      await SessionReset.onSignOut();

      expect(MessagingService.unreadTotal.value, 0);
    });

    test('drops business mode back to personal', () async {
      await AccountModeService.setMode(AppViewMode.business);
      expect(AccountModeService.inBusinessMode, isTrue, reason: 'guard');

      await SessionReset.onSignOut();

      expect(AccountModeService.inBusinessMode, isFalse);
      expect(AccountModeService.current, AppViewMode.personal);
    });

    test('is idempotent and safe to call twice', () async {
      await CartService.add(_product('1'));

      await SessionReset.onSignOut();
      await SessionReset.onSignOut();

      expect(CartService.count, 0);
      expect(MessagingService.unreadTotal.value, 0);
    });

    test('never throws, even when a service has no plugin behind it', () async {
      // Sign-out must not be blockable by a failing service. Under the
      // test binding the audio players have no platform side at all,
      // which is the cheapest available stand-in for "a service threw".
      await expectLater(SessionReset.onSignOut(), completes);
    });
  });

  group('biometric unlock is per account, not per phone (#21)', () {
    test('a second account on the same phone does NOT inherit unlock', () async {
      // The bug verbatim. Account A opts in...
      await SecureStorageService.saveUserId('user-a');
      await SecureStorageService.write('biometric_enabled:user-a', 'true');
      expect(await BiometricService.isEnabled(), isTrue, reason: 'guard');

      // ...then signs out and account B signs in on the same handset.
      await SecureStorageService.clearAll();
      BiometricService.clearSessionOnSignOut();
      await SecureStorageService.saveUserId('user-b');

      expect(
        await BiometricService.isEnabled(),
        isFalse,
        reason: 'a brand-new account must start with biometrics OFF',
      );
    });

    test('the original account keeps its choice when it comes back', () async {
      await SecureStorageService.saveUserId('user-a');
      await SecureStorageService.write('biometric_enabled:user-a', 'true');

      await SecureStorageService.clearAll();
      BiometricService.clearSessionOnSignOut();
      await SecureStorageService.saveUserId('user-a');

      expect(await BiometricService.isEnabled(), isTrue);
    });

    test('signed out reads as disabled rather than inheriting', () async {
      await SecureStorageService.write('biometric_enabled:user-a', 'true');
      // No user_id persisted — nobody is signed in.

      expect(await BiometricService.isEnabled(), isFalse);
    });

    test('migrates an existing opt-in off the old device-wide key', () async {
      // Users upgrading into this fix already have the shared flag set.
      // Whoever is signed in on the phone is the one who switched it on,
      // so it becomes theirs — and the shared key is destroyed so it can
      // never be inherited again.
      await SecureStorageService.saveUserId('user-a');
      await SecureStorageService.write('biometric_enabled', 'true');

      expect(await BiometricService.isEnabled(), isTrue);
      expect(storage['biometric_enabled:user-a'], 'true');
      expect(storage.containsKey('biometric_enabled'), isFalse);
    });

    test('the migrated flag does not then leak to the next account', () async {
      await SecureStorageService.saveUserId('user-a');
      await SecureStorageService.write('biometric_enabled', 'true');
      await BiometricService.isEnabled(); // triggers the migration

      await SecureStorageService.clearAll();
      BiometricService.clearSessionOnSignOut();
      await SecureStorageService.saveUserId('user-b');

      expect(await BiometricService.isEnabled(), isFalse);
    });

    test('clearAll keeps device memory but drops the session', () async {
      await SecureStorageService.write('has_seen_onboarding', 'true');
      await SecureStorageService.write('biometric_enabled:user-a', 'true');
      await SecureStorageService.saveAuthToken('secret-token');
      await SecureStorageService.saveRefreshToken('secret-refresh');
      await SecureStorageService.saveUserId('user-a');
      await SecureStorageService.write('account_banned', '1');

      await SecureStorageService.clearAll();

      // Device memory survives — emptying this set is how a returning
      // user gets shown the first-launch intro all over again.
      expect(storage['has_seen_onboarding'], 'true');
      // Namespaced, so it cannot leak, and the owner keeps it.
      expect(storage['biometric_enabled:user-a'], 'true');
      // Nothing session-bearing outlives the sign-out.
      expect(storage.containsKey('auth_token'), isFalse);
      expect(storage.containsKey('refresh_token'), isFalse);
      expect(storage.containsKey('user_id'), isFalse);
      expect(storage.containsKey('account_banned'), isFalse);
    });

    test('the bare device-wide key is no longer in the preserved set', () {
      expect(
        SecureStorageService.debugIsPreserved('biometric_enabled'),
        isFalse,
      );
      expect(
        SecureStorageService.debugIsPreserved('biometric_enabled:user-a'),
        isTrue,
      );
    });
  });
}
