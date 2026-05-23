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

  /// Download [imageUrl] into the user's gallery under an album named
  /// "Advent Connect". The album folder makes it easy to find later
  /// and keeps saved posts grouped together.
  ///
  /// Uses dart:io HttpClient directly to avoid pulling in the `http`
  /// package — Supabase Storage URLs are plain HTTPS with no fancy
  /// auth, so a barebones client is enough.
  static Future<bool> saveImageFromUrl(String imageUrl) async {
    if (imageUrl.trim().isEmpty) return false;
    HttpClient? client;
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) return false;
      }
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
        album: 'Advent Connect',
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
