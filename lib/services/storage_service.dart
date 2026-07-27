import 'dart:ui' show Color;

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

  /// Profile-photo bucket. WhatsApp-style: square crop locked at 1:1,
  /// output 640×640 at ~75 quality (~80–120 KB). The picker pre-resizes
  /// to 1600 wide before the cropper opens so the native cropper isn't
  /// handed a 4000×6000 phone capture (that was the OOM source on
  /// earlier builds). The cropper itself caps output at 640 so the
  /// final file is small even if someone disables the picker resize.
  static Future<String?> pickAndUploadProfilePhoto() => _pickAndUpload(
        bucket: 'profile_photos',
        maxWidth: 1600,
        imageQuality: 85,
        crop: const _CropSpec(
          ratioX: 1,
          ratioY: 1,
          outputWidth: 640,
          outputQuality: 75,
          title: 'Crop profile photo',
        ),
      );

  /// Profile background / cover photo. 16:9 locked, output 1280×720 at
  /// ~80 quality (~250 KB). Same pre-resize strategy as the profile
  /// picker to keep the cropper memory-safe.
  static Future<String?> pickAndUploadCoverPhoto() => _pickAndUpload(
        bucket: 'profile_photos',
        maxWidth: 2000,
        imageQuality: 85,
        crop: const _CropSpec(
          ratioX: 16,
          ratioY: 9,
          outputWidth: 1280,
          outputQuality: 80,
          title: 'Crop background photo',
        ),
      );

  /// Church logo / avatar. Square 1:1 like a profile photo, output
  /// 640×640. Lands in the public `church_photos` bucket under the
  /// admin's uid folder (storage RLS keys writes on the uid prefix).
  static Future<String?> pickAndUploadChurchLogo() => _pickAndUpload(
        bucket: 'church_photos',
        maxWidth: 1600,
        imageQuality: 85,
        crop: const _CropSpec(
          ratioX: 1,
          ratioY: 1,
          outputWidth: 640,
          outputQuality: 78,
          title: 'Crop church logo',
        ),
      );

  /// Church cover banner. 16:9 locked, output 1280×720. Same
  /// `church_photos` bucket as the logo.
  static Future<String?> pickAndUploadChurchCover() => _pickAndUpload(
        bucket: 'church_photos',
        maxWidth: 2000,
        imageQuality: 85,
        crop: const _CropSpec(
          ratioX: 16,
          ratioY: 9,
          outputWidth: 1280,
          outputQuality: 80,
          title: 'Crop church cover',
        ),
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

  /// Home-feed post photo. Free aspect, up to 1600 wide, ~600KB target.
  /// Cover art for a Library item — album art for music, a jacket for an EGW
  /// book. Square 1:1 like other artwork, output 800x800 so it still looks
  /// sharp behind the full-screen player, at ~150 KB.
  ///
  /// Lands in the public `library` bucket alongside the media it belongs to.
  static Future<String?> pickAndUploadLibraryCover() => _pickAndUpload(
        bucket: 'library',
        maxWidth: 1600,
        imageQuality: 85,
        crop: const _CropSpec(
          ratioX: 1,
          ratioY: 1,
          outputWidth: 800,
          outputQuality: 82,
          title: 'Crop cover art',
        ),
      );

  static Future<String?> pickAndUploadPostPhoto() => _pickAndUpload(
        bucket: 'post_photos',
        maxWidth: 1600,
        imageQuality: 80,
      );

  /// 24h story photo. Slightly larger ceiling to keep faces crisp on
  /// full-screen viewers, but still capped so uploads stay quick on
  /// patchy networks.
  static Future<String?> pickAndUploadStoryPhoto() => _pickAndUpload(
        bucket: 'story_photos',
        maxWidth: 1600,
        imageQuality: 82,
      );

  /// Generic flow used by the convenience methods above.
  /// Returns the public URL of the uploaded file, or null if the user
  /// cancelled the picker. When `crop` is supplied the source image is
  /// run through image_cropper with the locked aspect ratio and output
  /// dimensions from [_CropSpec]; the user sees a WhatsApp-style crop
  /// frame they can drag before tapping Done.
  static Future<String?> _pickAndUpload({
    required String bucket,
    required double maxWidth,
    required int imageQuality,
    _CropSpec? crop,
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
        maxHeight: maxWidth, // hard cap on both dimensions cuts native OOM risk
        imageQuality: imageQuality,
        requestFullMetadata: false,
      );
    } catch (e, st) {
      debugPrint('StorageService.pickImage failed: $e\n$st');
      return null;
    }
    if (picked == null) return null;

    String sourcePath = picked.path;
    if (crop != null) {
      // Wrap the native cropper in try/catch — older Android builds
      // occasionally OOM here. The pre-resize on the picker keeps the
      // input under the cropper's bitmap budget so this is very
      // unlikely now, but the fallback means a crash on a single
      // device can't break uploads for everyone else.
      try {
        final cropped = await _cropper.cropImage(
          sourcePath: picked.path,
          compressQuality: crop.outputQuality,
          maxWidth: crop.outputWidth,
          maxHeight: (crop.outputWidth * crop.ratioY / crop.ratioX).round(),
          aspectRatio: CropAspectRatio(
            ratioX: crop.ratioX.toDouble(),
            ratioY: crop.ratioY.toDouble(),
          ),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: crop.title,
              toolbarColor: const Color(0xFF0D1B3E),
              toolbarWidgetColor: const Color(0xFFFFFFFF),
              activeControlsWidgetColor: const Color(0xFF1565C0),
              lockAspectRatio: true,
              hideBottomControls: true,
              initAspectRatio: CropAspectRatioPreset.original,
            ),
            IOSUiSettings(
              title: crop.title,
              aspectRatioLockEnabled: true,
              resetAspectRatioEnabled: false,
              doneButtonTitle: 'Done',
              cancelButtonTitle: 'Cancel',
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
      // Do NOT pass `limit` to pickMultiImage. On some Android versions
      // limit=1 freezes the picker entirely instead of opening in
      // single-select mode. We enforce the cap ourselves by slicing below.
      picked = await _picker.pickMultiImage(
        maxWidth: 1600,
        imageQuality: 80,
      );
    } catch (e, st) {
      debugPrint('StorageService.pickMultiImage failed: $e\n$st');
      return const [];
    }
    if (picked.isEmpty) return const [];

    // Silently drop anything over the caller's cap so we never exceed 4.
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

  /// Max chat-image upload size (validated AFTER compression, before
  /// upload). Compression keeps real photos well under this; the guard
  /// catches pathological files.
  static const int maxChatImageBytes = 5 * 1024 * 1024;

  /// Pick + compress a single image for a chat message. Gallery by
  /// default, camera when [fromCamera] is true. Returns the compressed
  /// bytes + normalised extension, or null if cancelled. Throws
  /// [FileTooLargeException] when the result still exceeds 5 MB.
  static Future<({Uint8List bytes, String ext})?> pickChatImage({
    bool fromCamera = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to send photos.');
    }
    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
        requestFullMetadata: false,
      );
    } catch (e, st) {
      debugPrint('StorageService.pickChatImage failed: $e\n$st');
      return null;
    }
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    if (bytes.length > maxChatImageBytes) {
      throw const FileTooLargeException(
        'That image is over 5 MB. Please choose a smaller one.',
      );
    }
    return (bytes: bytes, ext: _extensionOf(picked.name));
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

/// Crop-time config: aspect ratio locked to ratioX/ratioY and the
/// cropper outputs an image capped at `outputWidth` wide (height
/// follows from the ratio). `outputQuality` is the JPEG quality the
/// cropper writes — lower than the picker's pre-resize quality is
/// fine because the cropper is the last compression stage before
/// upload.
class _CropSpec {
  const _CropSpec({
    required this.ratioX,
    required this.ratioY,
    required this.outputWidth,
    required this.outputQuality,
    required this.title,
  });

  final int ratioX;
  final int ratioY;
  final int outputWidth;
  final int outputQuality;
  final String title;
}

/// Thrown when a picked attachment exceeds its size limit. [message] is
/// user-facing — show it directly.
class FileTooLargeException implements Exception {
  const FileTooLargeException(this.message);
  final String message;
  @override
  String toString() => message;
}
