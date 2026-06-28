import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Downloads a Library file (PDF / audio) to a local file and hands it to the
/// OS share sheet so the user can "Save to Files" / Downloads / send it on.
///
/// We deliberately route through the share sheet rather than writing straight
/// to the public Downloads folder: that needs no storage permission on any
/// Android/iOS version and still gives the user a real "save / download"
/// choice. The file is cached by URL hash so a second download is instant.
class DownloadService {
  DownloadService._();

  /// Returns true once the share sheet was shown, false on failure (the caller
  /// surfaces a message).
  static Future<bool> downloadAndShare({
    required String url,
    required String suggestedName,
    String? mimeType,
  }) async {
    try {
      final dir = await getApplicationCacheDirectory();
      final hash = sha1.convert(url.codeUnits).toString();
      final ext = _extOf(url);
      final safeName = _sanitize(suggestedName);
      final cached = File('${dir.path}/dl_$hash.$ext');

      if (!await cached.exists() || (await cached.length()) == 0) {
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse(url));
        final resp = await req.close();
        if (resp.statusCode != 200) {
          throw HttpException('HTTP ${resp.statusCode}');
        }
        await resp.pipe(cached.openWrite());
      }

      // Copy to a nicely-named temp file so the share sheet shows the title
      // (e.g. "Hymnal.pdf") instead of the opaque cache hash.
      final tmpDir = await getTemporaryDirectory();
      final named = File('${tmpDir.path}/$safeName.$ext');
      await cached.copy(named.path);

      await Share.shareXFiles(
        [XFile(named.path, mimeType: mimeType, name: '$safeName.$ext')],
        subject: suggestedName,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _extOf(String url) {
    final clean = url.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot == -1) return 'bin';
    final e = clean.substring(dot + 1).toLowerCase();
    return e.length > 5 ? 'bin' : e;
  }

  static String _sanitize(String name) {
    final cleaned =
        name.replaceAll(RegExp(r'[^A-Za-z0-9 _\-]'), '').trim();
    return cleaned.isEmpty ? 'download' : cleaned;
  }

  /// Convenience for SnackBar feedback after a download attempt.
  static void toast(BuildContext context, bool ok) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Ready — choose where to save it.'
            : 'Download failed. Check your connection and try again.'),
      ),
    );
  }
}
