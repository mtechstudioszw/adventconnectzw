import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_cropper/image_cropper.dart';
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
  static final ImageCropper _cropper = ImageCropper();

  /// Profile-photo bucket. Square crop, 1024 max width, ~500KB target.
  /// Profile photos go through the cropper so the user controls framing
  /// (faces in particular benefit from this on tall portraits).
  static Future<String?> pickAndUploadProfilePhoto() => _pickAndUpload(
        bucket: 'profile_photos',
        maxWidth: 1024,
        imageQuality: 80,
        squareCrop: true,
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
  /// cancelled the picker. `squareCrop: true` runs the source image
  /// through image_cropper with a locked 1:1 ratio.
  static Future<String?> _pickAndUpload({
    required String bucket,
    required double maxWidth,
    required int imageQuality,
    bool squareCrop = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to upload a photo.');
    }

    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxWidth,
        imageQuality: imageQuality,
      );
    } catch (e, st) {
      debugPrint('StorageService.pickImage failed: $e\n$st');
      return null;
    }
    if (picked == null) return null;

    String sourcePath = picked.path;
    if (squareCrop) {
      // The cropper has crashed on some Android builds (native OOM
      // during cropping). Wrap in try/catch and fall back to the
      // uncropped image so the upload still succeeds — the picker
      // already enforces maxWidth/quality so the file isn't huge.
      try {
        final cropped = await _cropper.cropImage(
          sourcePath: picked.path,
          compressQuality: imageQuality,
          maxWidth: maxWidth.toInt(),
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop photo',
              lockAspectRatio: true,
              hideBottomControls: true,
            ),
            IOSUiSettings(
              title: 'Crop photo',
              aspectRatioLockEnabled: true,
              resetAspectRatioEnabled: false,
            ),
          ],
        );
        // null means the user cancelled the cropper — respect that.
        if (cropped == null) return null;
        sourcePath = cropped.path;
      } catch (e, st) {
        debugPrint(
          'StorageService.cropImage failed, using uncropped: $e\n$st',
        );
      }
    }

    Uint8List bytes;
    try {
      final croppedFile = XFile(sourcePath);
      bytes = await croppedFile.readAsBytes();
    } catch (e, st) {
      debugPrint('StorageService.readAsBytes failed: $e\n$st');
      return null;
    }
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

    List<XFile> picked;
    try {
      picked = await _picker.pickMultiImage(
        maxWidth: 1600,
        imageQuality: 80,
        limit: max,
      );
    } catch (e, st) {
      debugPrint('StorageService.pickMultiImage failed: $e\n$st');
      return const [];
    }
    if (picked.isEmpty) return const [];

    final urls = <String>[];
    for (final file in picked.take(max)) {
      try {
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
      } catch (e, st) {
        // Skip a bad file rather than aborting the whole batch — at
        // least the user keeps the photos that did upload.
        debugPrint('StorageService: skipping product photo: $e\n$st');
      }
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
