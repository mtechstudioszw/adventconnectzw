import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';

/// Saves remote images (post photos, story photos) into the device's
/// native photo gallery. Wraps the `gal` package so callers don't
/// have to deal with permission edge cases. Returns true on success,
/// false otherwise — the caller is expected to surface a toast either
/// way.
class GalleryService {
  GalleryService._();

  /// Ask once, not once per photo.
  ///
  /// Pulled out of [saveImageFromUrl] for [saveImagesFromUrls]: prompting
  /// inside the loop would put a permission dialog between every pair of
  /// photos in a nine-photo post.
  static Future<bool> _ensureAccess() async {
    if (await Gal.hasAccess(toAlbum: true)) return true;
    return Gal.requestAccess(toAlbum: true);
  }

  /// Save every URL in [imageUrls], returning how many landed.
  ///
  /// Sequential on purpose. These are full-resolution photos off Supabase
  /// Storage and a post can carry nine of them; firing them all at once on
  /// the kind of mobile connection this app is mostly used on makes every
  /// one of them slower and more likely to time out.
  ///
  /// Partial success is a real outcome and is reported as a count rather
  /// than a bool — "3 of 5 saved" is something the member can act on,
  /// where a bare failure after three successful writes is a lie.
  static Future<int> saveImagesFromUrls(List<String> imageUrls) async {
    final urls = imageUrls.where((u) => u.trim().isNotEmpty).toList();
    if (urls.isEmpty) return 0;
    // Checked up front so a denied permission costs one dialog, not N.
    if (!await _ensureAccess()) return 0;

    var saved = 0;
    for (final url in urls) {
      if (await saveImageFromUrl(url)) saved++;
    }
    return saved;
  }

  /// Download [imageUrl] into the user's gallery under an album named
  /// "Adventist Super App". The album folder makes it easy to find later
  /// and keeps saved posts grouped together.
  ///
  /// Uses dart:io HttpClient directly to avoid pulling in the `http`
  /// package — Supabase Storage URLs are plain HTTPS with no fancy
  /// auth, so a barebones client is enough.
  static Future<bool> saveImageFromUrl(String imageUrl) async {
    if (imageUrl.trim().isEmpty) return false;
    if (!await _ensureAccess()) return false;
    HttpClient? client;
    try {
      final uri = Uri.parse(imageUrl);
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
      if (response.statusCode != 200) {
        debugPrint(
          'GalleryService: download failed ${response.statusCode}',
        );
        return false;
      }
      // Consume the response body into bytes.
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      final bytes = builder.toBytes();
      await Gal.putImageBytes(
        Uint8List.fromList(bytes),
        album: 'Adventist Super App',
      );
      return true;
    } catch (e, st) {
      debugPrint('GalleryService.saveImageFromUrl failed: $e\n$st');
      return false;
    } finally {
      client?.close(force: true);
    }
  }
}
