import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Online/offline state for the whole app. Backed by `connectivity_plus`
/// — emits true whenever the device has any non-`none` connection.
///
/// Used by `OfflineBanner` for the "📡 You're offline" strip at the top
/// of the app shell, and by services that want to queue a write rather
/// than fail outright.
class ConnectivityService {
  ConnectivityService._();

  static final Connectivity _connectivity = Connectivity();
  static final StreamController<bool> _onlineController =
      StreamController<bool>.broadcast();
  // Kept on the static class so the subscription survives the app
  // lifetime — never read, but its presence prevents Dart from GCing
  // the underlying stream listener.
  // ignore: unused_field
  static StreamSubscription<List<ConnectivityResult>>? _sub;
  static bool _lastOnline = true;
  static bool _lastWifi = false;
  static bool _initialized = false;

  /// Latest cached online value. Defaults to true so the UI doesn't
  /// flash an offline banner during cold start.
  static bool get isOnline => _lastOnline;

  /// Whether the device is on Wi-Fi (vs cellular). Drives the Watch
  /// "Wi-Fi only" auto-preview setting so previews never burn mobile data.
  static bool get isWifi => _lastWifi;

  /// Broadcast stream of online/offline transitions. Late subscribers
  /// see the next transition — call `isOnline` for the current value.
  static Stream<bool> get onChanged => _onlineController.stream;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final initial = await _connectivity.checkConnectivity();
      _lastWifi = initial.contains(ConnectivityResult.wifi);
      _emit(_resultsToOnline(initial));
      _sub = _connectivity.onConnectivityChanged.listen((results) {
        _lastWifi = results.contains(ConnectivityResult.wifi);
        _emit(_resultsToOnline(results));
      });
    } catch (_) {
      // connectivity_plus is unavailable on some desktop targets — stay
      // optimistic.
      _emit(true);
    }
  }

  static bool _resultsToOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  static void _emit(bool online) {
    if (online == _lastOnline) return;
    _lastOnline = online;
    _onlineController.add(online);
  }
}
