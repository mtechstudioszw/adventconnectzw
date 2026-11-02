import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'cache_service.dart';

/// Reads text aloud with the phone's own voice (2 Nov 2026).
///
/// Used for EGW books, where no narrated recording exists under a licence
/// the app can use. Works offline; quality depends on the phone's voices.
class ReadAloud {
  ReadAloud._();
  static final ReadAloud instance = ReadAloud._();

  FlutterTts? _tts;
  bool _ready = false;

  /// True while something is being read.
  final ValueNotifier<bool> speaking = ValueNotifier(false);

  // Device-level preference: reading speed (0.3 slow … 0.6 fast).
  static const _kRate = 'pref:read_aloud_rate';

  static const rates = <double>[0.35, 0.45, 0.55];

  double get rate =>
      double.tryParse(CacheService.readPref(_kRate) ?? '') ?? 0.45;

  Future<void> setRate(double r) async {
    await CacheService.writePref(_kRate, '$r');
    await _tts?.setSpeechRate(r);
  }

  Future<FlutterTts> _engine() async {
    final tts = _tts ??= FlutterTts();
    if (!_ready) {
      _ready = true;
      try {
        await tts.awaitSpeakCompletion(true);
        await tts.setLanguage('en-US');
        await tts.setSpeechRate(rate);
        await tts.setPitch(1.0);
        await tts.setVolume(1.0);
      } catch (e) {
        debugPrint('ReadAloud setup: $e');
      }
    }
    return tts;
  }

  /// Speaks [text] and completes when it has been read (or stopped).
  /// Returns false when the phone has no voice / the engine failed.
  Future<bool> speak(String text) async {
    final t = text.trim();
    if (t.isEmpty) return true;
    try {
      final tts = await _engine();
      speaking.value = true;
      // Android caps one utterance at ~4,000 characters; a page is far
      // below that, but split defensively at sentence ends.
      for (final part in _chunks(t, 3500)) {
        if (!speaking.value) break;
        final r = await tts.speak(part);
        if (r != 1 && r != true) return false;
      }
      return true;
    } catch (e) {
      debugPrint('ReadAloud.speak: $e');
      return false;
    }
  }

  Future<void> stop() async {
    speaking.value = false;
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  @visibleForTesting
  static List<String> chunksForTest(String t, int max) => _chunks(t, max);

  static List<String> _chunks(String t, int max) {
    if (t.length <= max) return [t];
    final out = <String>[];
    var rest = t;
    while (rest.length > max) {
      var cut = rest.lastIndexOf(RegExp(r'[.!?]\s'), max);
      if (cut < max ~/ 2) cut = rest.lastIndexOf(' ', max);
      if (cut <= 0) cut = max;
      out.add(rest.substring(0, cut + 1).trim());
      rest = rest.substring(cut + 1);
    }
    if (rest.trim().isNotEmpty) out.add(rest.trim());
    return out;
  }
}
