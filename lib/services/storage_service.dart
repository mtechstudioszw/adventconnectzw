import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Helpers for picking, compressing and uploading images to Supabase
/// Storage. Compression happens via the picker's built-in `imageQuality`
/// and `maxWidth` so we don't need a second compression dependency.
///
/// Bucket names match master reference Part 14:
///   profile_photos   public  500 KB
///   product_photos   public  600 KB
///   event_flyers     public  1 MB
///   church_photos    public  800 KB
class StorageService {
  StorageService._();

  static final SupabaseClient _client = Supabase.instance.client;
  static final ImagePicker _picker = ImagePicker();

  /// Profile-photo bucket. Square crop, 1024 max width, ~500KB target.
  static Future<String?> pickAndUploadProfilePhoto() => _pickAndUpload(
        bucket: 'profile_photos',
        maxWidth: 1024,
        imageQuality: 80,
      );

  /// Product-photo bucket. Up to 1600 wide, ~600KB target.
  static Future<String?> pickAndUploadProductPhoto() => _pickAndUpload(
        bucket: 'product_photos',
        maxWidth: 1600,
        imageQuality: 80,
      );

  /// Event-flyer bucket. Up to 2048 wide, ~1MB target.
  static Future<String?> pickAndUploadEventFlyer() => _pickAndUpload(
        bucket: 'event_flyers',
        maxWidth: 2048,
        imageQuality: 85,
      );

  /// Generic flow used by the three convenience methods above.
  /// Returns the public URL of the uploaded file, or null if the user
  /// cancelled the picker.
  static Future<String?> _pickAndUpload({
    required String bucket,
    required double maxWidth,
    required int imageQuality,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to upload a photo.');
    }

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: maxWidth,
      imageQuality: imageQuality,
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    final ext = _extensionOf(picked.name);
    final path = _buildPath(userId: user.id, ext: ext);

    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            contentType: _mimeFor(ext),
            upsert: false,
          ),
        );

    return _client.storage.from(bucket).getPublicUrl(path);
  }

  /// Pick multiple product photos in one go (max 4) and upload each.
  /// Returns the list of public URLs in order; an empty list means the
  /// picker was cancelled.
  static Future<List<String>> pickAndUploadProductPhotos({
    int max = 4,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to upload photos.');
    }

    final picked = await _picker.pickMultiImage(
      maxWidth: 1600,
      imageQuality: 80,
      limit: max,
    );
    if (picked.isEmpty) return const [];

    final urls = <String>[];
    for (final file in picked.take(max)) {
      final bytes = await file.readAsBytes();
      final ext = _extensionOf(file.name);
      final path = _buildPath(userId: user.id, ext: ext);
      await _client.storage.from('product_photos').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              cacheControl: '3600',
              contentType: _mimeFor(ext),
              upsert: false,
            ),
          );
      urls.add(_client.storage.from('product_photos').getPublicUrl(path));
    }
    return urls;
  }

  /// Upload pre-supplied bytes (used by tests or non-picker flows).
  static Future<String> uploadBytes({
    required String bucket,
    required Uint8List bytes,
    required String extension,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to upload a photo.');
    }
    final path = _buildPath(userId: user.id, ext: extension);
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            contentType: _mimeFor(extension),
            upsert: false,
          ),
        );
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  static String _buildPath({required String userId, required String ext}) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '$userId/$ts.$ext';
  }

  static String _extensionOf(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot == -1) return 'jpg';
    final ext = filename.substring(dot + 1).toLowerCase();
    if (ext == 'jpeg') return 'jpg';
    if (ext == 'png' || ext == 'webp' || ext == 'jpg') return ext;
    return 'jpg';
  }

  static String _mimeFor(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      default:
        return 'image/jpeg';
    }
  }
}
