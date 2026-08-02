import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// Deep link a friend QR encodes. Uses the app's existing scheme and adds
/// a `user` host (see DeepLinkService), so a scan opens the member's
/// profile through the same path as any other shared link.
String friendQrPayload(String userId) =>
    'io.supabase.adventconnect://user/$userId';

/// Adventists meet in person — camp meeting, a rally, a visiting choir.
/// Scanning beats spelling a name into a search box in a noisy hall.
///
/// Deliberately opens the scanned member's PROFILE rather than sending a
/// friend request: scanning is an introduction, and consent to be added
/// should still be a tap the user makes knowingly.
Future<void> showFriendQrSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _FriendQrSheet(),
  );
}

class _FriendQrSheet extends StatefulWidget {
  const _FriendQrSheet();

  @override
  State<_FriendQrSheet> createState() => _FriendQrSheetState();
}

class _FriendQrSheetState extends State<_FriendQrSheet> {
  /// Wraps the QR card so it can be rasterised for sharing.
  final GlobalKey _qrKey = GlobalKey();
  bool _sharing = false;

  /// Share the code as a real PNG, not just a link.
  ///
  /// A friend code is something people hold up across a hall or drop into
  /// a church WhatsApp group — as a bare URL it's unrecognisable and
  /// unscannable. We rasterise the same card that's on screen (white
  /// background baked in, so it survives dark mode and any chat app's
  /// bubble colour) and attach the deep link as text for anyone whose
  /// client strips images.
  Future<void> _share(String userId, String name) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('QR not laid out');
      // 3x so the code stays crisp if the recipient zooms or reshares.
      final ui.Image image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('encode failed');
      final bytes = byteData.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/advent-friend-code.png');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'Scan my Advent Connect ZW friend code to open my profile.\n'
            '$name\n${friendQrPayload(userId)}',
      );
    } catch (_) {
      // Rasterising can fail on odd devices; the link alone is still
      // useful, so fall back rather than telling them it didn't work.
      try {
        await Share.share(
          'Scan my Advent Connect ZW friend code to open my profile.\n'
          '$name\n${friendQrPayload(userId)}',
        );
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not open the share sheet.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final user = AuthService.currentUser;
    final id = user?.id;
    final name =
        (user?.userMetadata?['full_name'] as String?)?.trim() ?? 'Your code';

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: palette.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Your friend code',
              style: AppTextStyles.headlineMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Let someone scan this to open your profile.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            if (id == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Text(
                  'Sign in to get your code.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              )
            else
              // RepaintBoundary so the card can be rasterised for
              // sharing. The name is baked INTO the shared image — a QR
              // with no name attached tells the recipient nothing about
              // whose code they're about to scan.
              RepaintBoundary(
                key: _qrKey,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    // The QR itself must stay dark-on-white in BOTH themes
                    // — scanners read contrast, not brand palettes, and an
                    // inverted code in dark mode is unreliable to scan.
                    // Baked white also means the shared PNG survives
                    // whatever bubble colour a chat app puts behind it.
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      QrImageView(
                        data: friendQrPayload(id),
                        version: QrVersions.auto,
                        size: 210,
                        backgroundColor: AppColors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: AppColors.darkNavy,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: AppColors.darkNavy,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleMedium.copyWith(
                          color: AppColors.darkNavy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Advent Connect ZW',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.textMuted,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (id != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _sharing ? null : () => _share(id, name),
                      icon: _sharing
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: AppColors.primaryBlue,
                              ),
                            )
                          : const Icon(Icons.ios_share_rounded, size: 19),
                      label: Text(
                        _sharing ? 'Preparing…' : 'Share code',
                        style: AppTextStyles.buttonText.copyWith(
                          fontSize: 15,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryBlue,
                        side: const BorderSide(color: AppColors.primaryBlue),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context.pushNamed('scan_friend');
                    },
                    icon: const Icon(Icons.qr_code_scanner, size: 19),
                    label: Text(
                      'Scan',
                      style: AppTextStyles.buttonText.copyWith(fontSize: 15),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Camera scanner. Accepts only this app's `user` links — a QR from any
/// other app is reported as unrecognised rather than silently ignored,
/// so a mis-scan doesn't look like a frozen camera.
class ScanFriendScreen extends StatefulWidget {
  const ScanFriendScreen({super.key});

  @override
  State<ScanFriendScreen> createState() => _ScanFriendScreenState();
}

class _ScanFriendScreenState extends State<ScanFriendScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  /// Guards against the detector firing repeatedly while the navigation
  /// animation runs, which would push several profile screens.
  bool _handled = false;
  String? _message;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final uri = Uri.tryParse(raw);
      if (uri == null ||
          uri.scheme != 'io.supabase.adventconnect' ||
          uri.host != 'user') {
        setState(() => _message = 'That isn\'t an Advent Connect friend code.');
        continue;
      }
      final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
      if (id.isEmpty) continue;
      _handled = true;
      // Replace rather than push: coming back from the profile should
      // return to where the user opened the scanner from, not to a live
      // camera they've finished with.
      context.pushReplacementNamed(
        'user_profile',
        pathParameters: {'userId': id},
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkNavy,
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Framing guide.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.white, width: 2.5),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  _ScanChipButton(
                    icon: Icons.arrow_back,
                    onTap: () => context.canPop()
                        ? context.pop()
                        : context.goNamed('home'),
                  ),
                  const Spacer(),
                  _ScanChipButton(
                    icon: Icons.flash_on,
                    onTap: () => _controller.toggleTorch(),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Column(
              children: [
                Text(
                  _message ?? 'Point the camera at a friend code',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w600,
                    shadows: const [
                      Shadow(blurRadius: 8, color: Colors.black54),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanChipButton extends StatelessWidget {
  const _ScanChipButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: AppColors.white, size: 20),
        ),
      ),
    );
  }
}
