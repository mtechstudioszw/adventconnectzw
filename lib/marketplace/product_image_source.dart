import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';

import '../widgets/cached_image.dart';

/// Where marketplace product photos come from — one place, so the hero and
/// the theme engine read the exact same image (and the render harness can
/// point both at local fixtures).
class ProductImageSource {
  ProductImageSource._();

  /// Render-harness hook: map a URL to a local provider. Never set in app
  /// code.
  @visibleForTesting
  static ImageProvider Function(String url)? debugOverride;

  static ImageProvider provider(String url) =>
      debugOverride?.call(url) ??
      CachedNetworkImageProvider(url, cacheManager: adventImageCacheManager);

  /// The photo decoded at [size]×[size] as raw RGBA — cheap to decode and
  /// plenty to read colours from. Null if it can't load in time.
  static Future<Uint8List?> samplePixels(String url, {int size = 48}) async {
    final completer = Completer<ui.Image>();
    final stream = ResizeImage(
      provider(url),
      width: size,
      height: size,
    ).resolve(ImageConfiguration.empty);
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
    try {
      final image = await completer.future.timeout(const Duration(seconds: 8));
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}
