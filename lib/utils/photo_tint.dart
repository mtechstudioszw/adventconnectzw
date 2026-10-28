import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';

import '../widgets/cached_image.dart';
import 'photo_url.dart';

/// The soft profile glow's colour, taken from a member's photo
/// (owner-approved exception to the palette, 28 Oct 2026 — see CLAUDE.md).
///
/// Strictly a faint wash behind the profile header. Text, buttons and cards
/// never use it, so readability can't depend on somebody's photo. Colours
/// the palette bans (green, pink) and dull or near-grey photos return
/// null, and the header stays plain.
class PhotoTint {
  PhotoTint._();

  static final Map<String, Color?> _cache = {};

  /// Pixels sampled per side. 24×24 is plenty for one dominant hue and
  /// costs nothing to decode.
  static const int _sample = 24;

  @visibleForTesting
  static void debugSeed(String url, Color? tint) => _cache[url.trim()] = tint;

  static Future<Color?> forPhoto(String? url) async {
    final u = (url ?? '').trim();
    if (u.isEmpty) return null;
    if (_cache.containsKey(u)) return _cache[u];
    Color? tint;
    try {
      final bytes = await _pixels(photoUrlAtSize(u, 96));
      tint = bytes == null ? null : fromPixels(bytes);
    } catch (_) {
      tint = null;
    }
    _cache[u] = tint;
    return tint;
  }

  static Future<Uint8List?> _pixels(String url) async {
    final provider = ResizeImage(
      CachedNetworkImageProvider(url, cacheManager: adventImageCacheManager),
      width: _sample,
      height: _sample,
    );
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (e, _) {
        if (!completer.isCompleted) completer.completeError(e);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    final image = await completer.future.timeout(const Duration(seconds: 8));
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data?.buffer.asUint8List();
  }

  /// The dominant colourful hue in RGBA [bytes], normalised to a calm
  /// mid-tone — or null when the photo has no usable colour.
  ///
  /// Hue is voted in 12 buckets weighted by saturation, so a small vivid
  /// area beats a large grey wall, but skin and backgrounds still count.
  static Color? fromPixels(Uint8List bytes) {
    final weights = List<double>.filled(12, 0);
    final hueSums = List<double>.filled(12, 0);
    var total = 0.0;
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      if (bytes[i + 3] < 128) continue;
      final hsl = HSLColor.fromColor(
        Color.fromARGB(255, bytes[i], bytes[i + 1], bytes[i + 2]),
      );
      // Near-black, near-white and grey pixels say nothing about hue.
      if (hsl.lightness < 0.12 || hsl.lightness > 0.92) continue;
      if (hsl.saturation < 0.18) continue;
      final w = hsl.saturation;
      final b = (hsl.hue / 30).floor() % 12;
      weights[b] += w;
      hueSums[b] += hsl.hue * w;
      total += w;
    }
    // Too little colour overall (a grey or monochrome photo).
    final pixels = bytes.length / 4;
    if (pixels == 0 || total / pixels < 0.08) return null;

    var best = 0;
    for (var b = 1; b < 12; b++) {
      if (weights[b] > weights[best]) best = b;
    }
    final hue = hueSums[best] / weights[best];
    // Any hue (owner, 28 Oct 2026): adaptive colour follows the photo, so
    // the palette's "no green / no pink" rule doesn't apply here.
    return HSLColor.fromAHSL(1, hue, 0.55, 0.52).toColor();
  }
}
