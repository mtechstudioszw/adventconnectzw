import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/church_model.dart';
import '../../services/auth_service.dart';
import '../../services/church_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Single-screen post-signup onboarding. PageView drives 6 steps:
///
///   0. Welcome
///   1. Profile (photo, display name, username, bio)
///   2. Home church (default congregation the user follows by default)
///   3. Personalization (interests, content prefs, topics, notif prefs)
///   4. Permissions (notifications, photos, camera)
///   5. Success (Enter App)
///
/// State lives in the controller — each step is a stateless page that
/// reads/writes through callbacks. The user can skip optional steps
/// (everything except the Continue gates on step 1).
class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen>
    with TickerProviderStateMixin {
  static const _stepCount = 6;

  final PageController _page = PageController();
  int _index = 0;

  // ---------------- profile step ----------------
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  String? _profilePhotoUrl;
  String? _coverPhotoUrl;
  bool _uploadingPhoto = false;
  bool _uploadingCover = false;

  // ---------------- church step -----------------
  String? _homeChurchId;
  List<Church> _allChurches = const [];
  bool _churchesLoading = true;

  // -------------- personalization ---------------
  final Set<String> _interests = <String>{};
  bool _notifPrayers = true;
  bool _notifEvents = true;
  bool _notifMarketplace = false;
  bool _notifChat = true;

  // ---------------- permissions -----------------
  bool _permNotif = false;
  bool _permPhotos = false;
  bool _permCamera = false;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Prefill from whatever metadata signUp already attached so the
    // user never re-types what we already know.
    final meta = AuthService.currentUser?.userMetadata ?? const {};
    _nameController.text = (meta['full_name'] as String?) ?? '';
    _usernameController.text = (meta['username'] as String?) ?? '';
    _bioController.text = (meta['bio'] as String?) ?? '';
    _profilePhotoUrl = meta['profile_photo_url'] as String?;
    _coverPhotoUrl = meta['cover_photo_url'] as String?;
    _homeChurchId = meta['church_id'] as String?;
    _loadChurches();
  }

  @override
  void dispose() {
    _page.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadChurches() async {
    try {
      final list = await ChurchService.fetchChurches();
      if (!mounted) return;
      setState(() {
        _allChurches = list;
        _churchesLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _churchesLoading = false);
    }
  }

  void _go(int next) {
    if (next < 0 || next >= _stepCount) return;
    HapticFeedback.selectionClick();
    setState(() => _index = next);
    _page.animateToPage(
      next,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _saveAndNext() async {
    setState(() => _error = null);
    if (_index == 1) {
      final name = _nameController.text.trim();
      if (name.length < 2) {
        setState(() => _error = 'Please add your display name.');
        return;
      }
      final username = _usernameController.text.trim();
      if (username.isNotEmpty &&
          !RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(username)) {
        setState(() => _error =
            'Username must be 3–20 letters, numbers or underscores.');
        return;
      }
      setState(() => _saving = true);
      // Persist photo + name + bio. Username + church_id go through
      // updateUser as user-metadata since they're not on the profiles
      // table by default — the metadata write is best-effort and
      // won't block onboarding if it fails.
      final result = await AuthService.updateProfile(
        fullName: name,
        bio: _bioController.text.trim(),
        // Persist username to the profiles table (not just metadata) so
        // hasCompletedProfileSetup() sees it — otherwise Google users
        // get re-onboarded on every sign-in.
        username: username.isNotEmpty ? username : null,
        profilePhotoUrl: _profilePhotoUrl ?? '',
        coverPhotoUrl: _coverPhotoUrl ?? '',
      );
      if (username.isNotEmpty) {
        await _writeMetadata({'username': username});
      }
      if (!mounted) return;
      setState(() => _saving = false);
      if (!result.isSuccess) {
        setState(() => _error = result.errorMessage);
        return;
      }
    } else if (_index == 2) {
      if (_homeChurchId != null) {
        setState(() => _saving = true);
        final result = await AuthService.updateProfile(
          churchId: _homeChurchId,
        );
        if (!mounted) return;
        if (!result.isSuccess) {
          setState(() {
            _saving = false;
            _error = result.errorMessage;
          });
          return;
        }
        // Mirror the home-church pick into church_followers so the
        // home greeting card actually reflects it. Without this, the
        // user lands on Home and sees "No church set yet" even though
        // they picked one moments ago. Best-effort — a follow failure
        // shouldn't dead-end onboarding.
        try {
          await ChurchService.follow(_homeChurchId!);
        } catch (_) {
          // ignore — already-following or transient errors
        }
        if (!mounted) return;
        setState(() => _saving = false);
      }
    } else if (_index == 3) {
      setState(() => _saving = true);
      await _writeMetadata({
        'interests': _interests.toList(),
        'notif_prefs': {
          'prayers': _notifPrayers,
          'events': _notifEvents,
          'marketplace': _notifMarketplace,
          'chat': _notifChat,
        },
      });
      if (!mounted) return;
      setState(() => _saving = false);
    }
    if (_index < _stepCount - 1) _go(_index + 1);
  }

  Future<void> _writeMetadata(Map<String, dynamic> patch) =>
      AuthService.updateMetadataDirect(patch);

  void _removeProfilePhoto() {
    setState(() => _profilePhotoUrl = null);
  }

  void _removeCoverPhoto() {
    setState(() => _coverPhotoUrl = null);
  }

  Future<void> _pickCover() async {
    if (_uploadingCover) return;
    setState(() {
      _uploadingCover = true;
      _error = null;
    });
    try {
      final url = await StorageService.pickAndUploadCoverPhoto();
      if (!mounted) return;
      if (url != null) setState(() => _coverPhotoUrl = url);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not upload cover. Try again.');
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _pickPhoto() async {
    if (_uploadingPhoto) return;
    setState(() {
      _uploadingPhoto = true;
      _error = null;
    });
    try {
      final url = await StorageService.pickAndUploadProfilePhoto();
      if (!mounted) return;
      if (url != null) setState(() => _profilePhotoUrl = url);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not upload photo. Try again.');
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _requestPermission(Permission permission) async {
    final status = await permission.request();
    if (!mounted) return;
    setState(() {
      if (permission == Permission.notification) {
        _permNotif = status.isGranted;
      } else if (permission == Permission.photos ||
          permission == Permission.storage) {
        _permPhotos = status.isGranted;
      } else if (permission == Permission.camera) {
        _permCamera = status.isGranted;
      }
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    // Explicit "I'm done" marker so the splash routing knows not to
    // bounce the user back here on next launch. The old check relied
    // on profiles.username — but username is OPTIONAL on step 1, so
    // users who skipped it got asked to set up again every cold
    // start. The flag is the authoritative signal.
    await AuthService.updateMetadataDirect({'onboarding_completed': true});
    if (!mounted) return;
    context.goNamed('home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            _ProgressBar(active: _index, total: _stepCount),
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  _WelcomePage(onContinue: () => _go(1)),
                  _ProfilePage(
                    nameController: _nameController,
                    usernameController: _usernameController,
                    bioController: _bioController,
                    photoUrl: _profilePhotoUrl,
                    coverUrl: _coverPhotoUrl,
                    uploadingPhoto: _uploadingPhoto,
                    uploadingCover: _uploadingCover,
                    onPickPhoto: _pickPhoto,
                    onPickCover: _pickCover,
                    onRemovePhoto: _removeProfilePhoto,
                    onRemoveCover: _removeCoverPhoto,
                  ),
                  _ChurchPage(
                    churches: _allChurches,
                    selectedId: _homeChurchId,
                    loading: _churchesLoading,
                    onChanged: (id) => setState(() => _homeChurchId = id),
                  ),
                  _PersonalizationPage(
                    interests: _interests,
                    notifPrayers: _notifPrayers,
                    notifEvents: _notifEvents,
                    notifMarketplace: _notifMarketplace,
                    notifChat: _notifChat,
                    onInterestToggle: (k) => setState(() {
                      if (!_interests.add(k)) _interests.remove(k);
                    }),
                    onNotifChanged: (key, v) => setState(() {
                      switch (key) {
                        case 'prayers':
                          _notifPrayers = v;
                          break;
                        case 'events':
                          _notifEvents = v;
                          break;
                        case 'marketplace':
                          _notifMarketplace = v;
                          break;
                        case 'chat':
                          _notifChat = v;
                          break;
                      }
                    }),
                  ),
                  _PermissionsPage(
                    notif: _permNotif,
                    photos: _permPhotos,
                    camera: _permCamera,
                    onRequest: _requestPermission,
                  ),
                  _SuccessPage(onEnter: _finish),
                ],
              ),
            ),
            if (_index != 0 && _index != _stepCount - 1)
              _NavBar(
                index: _index,
                saving: _saving,
                error: _error,
                onBack: () => _go(_index - 1),
                onNext: _saveAndNext,
                onSkip: _index == 0 || _index == 1
                    ? null
                    : () => _go(_index + 1),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Step indicator
// =============================================================================

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.active, required this.total});
  final int active;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          for (int i = 0; i < total; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                height: 6,
                decoration: BoxDecoration(
                  color: i <= active
                      ? AppColors.primaryBlue
                      : const Color.fromRGBO(26, 26, 46, 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            if (i < total - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Nav bar (Back / Next / Skip)
// =============================================================================

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.index,
    required this.saving,
    required this.error,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
  });

  final int index;
  final bool saving;
  final String? error;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: context.palette.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            _MiniErrorBanner(message: error!),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              _BackButton(onTap: saving ? null : onBack),
              const SizedBox(width: 10),
              Expanded(
                child: _PrimaryButton(
                  label: index == 4 ? 'Continue' : 'Continue',
                  busy: saving,
                  onTap: saving ? null : onNext,
                ),
              ),
            ],
          ),
          if (onSkip != null) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: saving ? null : onSkip,
                child: Text(
                  'Skip for now',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.55),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: context.palette.chipBg,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 60,
            padding: const EdgeInsets.symmetric(vertical: 18),
            alignment: Alignment.center,
            child: const Icon(
              Icons.arrow_back_ios_new,
              size: 16,
              color: AppColors.darkNavy,
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null && !busy ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: AppColors.white,
                        strokeWidth: 2.4,
                      ),
                    )
                  : Text(
                      label,
                      style: AppTextStyles.buttonText.copyWith(
                        fontSize: 15.5,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniErrorBanner extends StatelessWidget {
  const _MiniErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Step 0 — Welcome
// =============================================================================

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onContinue});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(36),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.40),
                    blurRadius: 32,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: const Icon(
                Icons.church,
                color: AppColors.goldAccent,
                size: 64,
              ),
            ),
          ),
          const SizedBox(height: 36),
          Text(
            'Welcome to\nAdvent Connect ZW',
            textAlign: TextAlign.center,
            style: AppTextStyles.displayLarge.copyWith(
              color: AppColors.darkNavy,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.18,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Let\'s set you up — a few quick steps to make the app feel '
            'like home.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.65),
              height: 1.5,
              fontSize: 14.5,
            ),
          ),
          const Spacer(),
          _PrimaryButton(
            label: 'Continue',
            busy: false,
            onTap: onContinue,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// =============================================================================
// Step 1 — Profile
// =============================================================================

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({
    required this.nameController,
    required this.usernameController,
    required this.bioController,
    required this.photoUrl,
    required this.coverUrl,
    required this.uploadingPhoto,
    required this.uploadingCover,
    required this.onPickPhoto,
    required this.onPickCover,
    required this.onRemovePhoto,
    required this.onRemoveCover,
  });

  final TextEditingController nameController;
  final TextEditingController usernameController;
  final TextEditingController bioController;
  final String? photoUrl;
  final String? coverUrl;
  final bool uploadingPhoto;
  final bool uploadingCover;
  final VoidCallback onPickPhoto;
  final VoidCallback onPickCover;
  final VoidCallback onRemovePhoto;
  final VoidCallback onRemoveCover;

  bool get _hasPhoto => (photoUrl ?? '').isNotEmpty;
  bool get _hasCover => (coverUrl ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepHeader(
            tagline: 'Step 1',
            title: 'Set up your profile',
            subtitle:
                'A photo, cover, and a name help others recognise you in the community.',
          ),
          const SizedBox(height: 24),
          // Cover strip on top — uploads to the same profile_photos
          // storage bucket as the avatar. Tappable to pick / replace;
          // the trailing icon removes it when present.
          _CoverStrip(
            coverUrl: coverUrl,
            uploading: uploadingCover,
            onTap: onPickCover,
            onRemove: _hasCover ? onRemoveCover : null,
          ),
          const SizedBox(height: 12),
          Center(
            child: _PhotoAvatar(
              photoUrl: photoUrl,
              uploading: uploadingPhoto,
              onTap: onPickPhoto,
            ),
          ),
          if (_hasPhoto) ...[
            const SizedBox(height: 6),
            Center(
              child: TextButton.icon(
                onPressed: onRemovePhoto,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.red,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove photo'),
              ),
            ),
          ],
          const SizedBox(height: 22),
          _GlowField(
            controller: nameController,
            icon: Icons.person_outline,
            hint: 'Display name',
          ),
          const SizedBox(height: 14),
          _GlowField(
            controller: usernameController,
            icon: Icons.alternate_email,
            hint: 'Username (optional)',
          ),
          const SizedBox(height: 14),
          _GlowField(
            controller: bioController,
            icon: Icons.short_text,
            hint: 'A short bio (optional)',
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}

class _CoverStrip extends StatelessWidget {
  const _CoverStrip({
    required this.coverUrl,
    required this.uploading,
    required this.onTap,
    this.onRemove,
  });

  final String? coverUrl;
  final bool uploading;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final hasCover = (coverUrl ?? '').isNotEmpty;
    return Stack(
      children: [
        InkWell(
          onTap: uploading ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 132,
            decoration: BoxDecoration(
              color: context.palette.cardMuted,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.15),
              ),
              image: hasCover
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(coverUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: uploading
                ? const CircularProgressIndicator(
                    color: AppColors.primaryBlue,
                    strokeWidth: 2.5,
                  )
                : hasCover
                    ? null
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 30,
                            color: AppColors.primaryBlue.withValues(alpha: 0.7),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add a cover photo',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
          ),
        ),
        if (hasCover && onRemove != null && !uploading)
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PhotoAvatar extends StatelessWidget {
  const _PhotoAvatar({
    required this.photoUrl,
    required this.uploading,
    required this.onTap,
  });

  final String? photoUrl;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          width: 128,
          height: 128,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: hasPhoto ? null : AppColors.primaryGradient,
            color: hasPhoto ? context.palette.cardMuted : null,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
            image: hasPhoto
                ? DecorationImage(
                    image: CachedNetworkImageProvider(photoUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          alignment: Alignment.center,
          child: hasPhoto
              ? null
              : const Icon(
                  Icons.person,
                  size: 56,
                  color: AppColors.white,
                ),
        ),
        Material(
          color: AppColors.primaryBlue,
          shape: const CircleBorder(),
          elevation: 4,
          child: InkWell(
            onTap: uploading ? null : onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.white, width: 2.5),
              ),
              child: uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.0,
                        color: AppColors.white,
                      ),
                    )
                  : const Icon(
                      Icons.camera_alt_outlined,
                      size: 18,
                      color: AppColors.white,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Step 2 — Home church
// =============================================================================

class _ChurchPage extends StatefulWidget {
  const _ChurchPage({
    required this.churches,
    required this.selectedId,
    required this.loading,
    required this.onChanged,
  });

  final List<Church> churches;
  final String? selectedId;
  final bool loading;
  final ValueChanged<String?> onChanged;

  @override
  State<_ChurchPage> createState() => _ChurchPageState();
}

class _ChurchPageState extends State<_ChurchPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Church> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.churches;
    return widget.churches.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.city.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepHeader(
            tagline: 'Step 2',
            title: 'Pick your home church',
            subtitle:
                'This is the one you\'ll follow by default. You can still '
                'follow other churches anytime.',
          ),
          const SizedBox(height: 16),
          _GlowField(
            controller: _searchController,
            icon: Icons.search,
            hint: 'Search by name or city',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryBlue,
                    ),
                  )
                : filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _query.isEmpty
                                ? 'No churches available right now.'
                                : 'No matches for "$_query".',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color:
                                  const Color.fromRGBO(26, 26, 46, 0.6),
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final c = filtered[i];
                          final selected = c.id == widget.selectedId;
                          return _ChurchPickRow(
                            church: c,
                            selected: selected,
                            onTap: () => widget.onChanged(
                              selected ? null : c.id,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ChurchPickRow extends StatelessWidget {
  const _ChurchPickRow({
    required this.church,
    required this.selected,
    required this.onTap,
  });

  final Church church;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryBlue.withValues(alpha: 0.08)
                : context.palette.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppColors.primaryBlue
                  : const Color.fromRGBO(26, 26, 46, 0.06),
              width: selected ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient:
                      selected ? AppColors.primaryGradient : null,
                  color: selected ? null : context.palette.cardMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.church,
                  color: selected
                      ? AppColors.white
                      : AppColors.primaryBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      church.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (church.city.isNotEmpty)
                      Text(
                        church.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color:
                              const Color.fromRGBO(26, 26, 46, 0.6),
                        ),
                      ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryBlue
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? AppColors.primaryBlue
                        : const Color.fromRGBO(26, 26, 46, 0.25),
                    width: 1.6,
                  ),
                ),
                alignment: Alignment.center,
                child: selected
                    ? const Icon(
                        Icons.check,
                        size: 14,
                        color: AppColors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Step 3 — Personalization
// =============================================================================

class _PersonalizationPage extends StatelessWidget {
  const _PersonalizationPage({
    required this.interests,
    required this.notifPrayers,
    required this.notifEvents,
    required this.notifMarketplace,
    required this.notifChat,
    required this.onInterestToggle,
    required this.onNotifChanged,
  });

  final Set<String> interests;
  final bool notifPrayers;
  final bool notifEvents;
  final bool notifMarketplace;
  final bool notifChat;
  final ValueChanged<String> onInterestToggle;
  final void Function(String key, bool value) onNotifChanged;

  /// Aligned to actual app features so the picks can be used as
  /// real weighting signals for the home feed (e.g. boost events
  /// for users who picked "Events", surface marketplace cards for
  /// users who picked "Marketplace"). Replaces the previous
  /// abstract "Interests" + "Content" split which couldn't be
  /// mapped back to any concrete feed signal.
  static const _interestOptions = <_TileOption>[
    _TileOption('Events', Icons.event_outlined),
    _TileOption('Prayer requests', Icons.front_hand_outlined),
    _TileOption('Advent News', Icons.newspaper_outlined),
    _TileOption('Marketplace', Icons.shopping_bag_outlined),
    _TileOption('Jobs', Icons.work_outline),
    _TileOption('Church announcements', Icons.campaign_outlined),
    _TileOption('Youth content', Icons.groups_2_outlined),
    _TileOption('Music', Icons.music_note_outlined),
    _TileOption('Evangelism', Icons.volunteer_activism_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepHeader(
            tagline: 'Step 3',
            title: 'What interests you?',
            subtitle:
                'Pick a few — we\'ll prioritise these in your feed.',
          ),
          const SizedBox(height: 22),
          _SectionLabel('Show me more of'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final opt in _interestOptions)
                _ChipTile(
                  option: opt,
                  selected: interests.contains(opt.label),
                  onTap: () => onInterestToggle(opt.label),
                ),
            ],
          ),
          const SizedBox(height: 22),
          _SectionLabel('Notify me about'),
          const SizedBox(height: 6),
          _NotifSwitch(
            label: 'Prayer requests',
            value: notifPrayers,
            onChanged: (v) => onNotifChanged('prayers', v),
          ),
          _NotifSwitch(
            label: 'Events & gatherings',
            value: notifEvents,
            onChanged: (v) => onNotifChanged('events', v),
          ),
          _NotifSwitch(
            label: 'Marketplace deals',
            value: notifMarketplace,
            onChanged: (v) => onNotifChanged('marketplace', v),
          ),
          _NotifSwitch(
            label: 'Messages & chat',
            value: notifChat,
            onChanged: (v) => onNotifChanged('chat', v),
          ),
        ],
      ),
    );
  }
}

class _TileOption {
  const _TileOption(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _ChipTile extends StatelessWidget {
  const _ChipTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _TileOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryBlue.withValues(alpha: 0.10)
                : context.palette.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? AppColors.primaryBlue
                  : const Color.fromRGBO(26, 26, 46, 0.10),
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color:
                          AppColors.primaryBlue.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                option.icon,
                size: 18,
                color: selected
                    ? AppColors.primaryBlue
                    : const Color.fromRGBO(26, 26, 46, 0.55),
              ),
              const SizedBox(width: 8),
              Text(
                option.label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: selected
                      ? AppColors.primaryBlue
                      : AppColors.darkNavy,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotifSwitch extends StatelessWidget {
  const _NotifSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color.fromRGBO(26, 26, 46, 0.08),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.darkNavy,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: value,
                  activeThumbColor: AppColors.primaryBlue,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Step 4 — Permissions
// =============================================================================

class _PermissionsPage extends StatelessWidget {
  const _PermissionsPage({
    required this.notif,
    required this.photos,
    required this.camera,
    required this.onRequest,
  });

  final bool notif;
  final bool photos;
  final bool camera;
  final Future<void> Function(Permission permission) onRequest;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepHeader(
            tagline: 'Step 4',
            title: 'A couple of permissions',
            subtitle:
                'Each one is optional — you can change these anytime in '
                'your phone\'s settings.',
          ),
          const SizedBox(height: 22),
          _PermissionCard(
            icon: Icons.notifications_active_outlined,
            title: 'Notifications',
            description:
                'Stay in the loop on prayers, events and messages from '
                'your community.',
            granted: notif,
            onRequest: () => onRequest(Permission.notification),
          ),
          const SizedBox(height: 12),
          _PermissionCard(
            icon: Icons.image_outlined,
            title: 'Photos & media',
            description:
                'Lets you set a profile picture, post photos and share '
                'items in the marketplace.',
            granted: photos,
            onRequest: () => onRequest(Permission.photos),
          ),
          const SizedBox(height: 12),
          _PermissionCard(
            icon: Icons.camera_alt_outlined,
            title: 'Camera (optional)',
            description:
                'Snap a photo from inside the app instead of switching to '
                'your camera roll.',
            granted: camera,
            onRequest: () => onRequest(Permission.camera),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    required this.onRequest,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: granted
              ? AppColors.successGreen.withValues(alpha: 0.4)
              : const Color.fromRGBO(26, 26, 46, 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: granted
                  ? AppColors.successGreen.withValues(alpha: 0.12)
                  : AppColors.primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              granted ? Icons.check : icon,
              color: granted
                  ? AppColors.successGreen
                  : AppColors.primaryBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.6),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: granted
                        ? AppColors.successGreen.withValues(alpha: 0.10)
                        : AppColors.primaryBlue,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: granted ? null : onRequest,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Text(
                          granted ? 'Granted' : 'Allow',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: granted
                                ? AppColors.successGreen
                                : AppColors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
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

// =============================================================================
// Step 5 — Success
// =============================================================================

class _SuccessPage extends StatefulWidget {
  const _SuccessPage({required this.onEnter});
  final VoidCallback onEnter;

  @override
  State<_SuccessPage> createState() => _SuccessPageState();
}

class _SuccessPageState extends State<_SuccessPage>
    with TickerProviderStateMixin {
  late final AnimationController _bounce;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _scale = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _bounce, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(
            child: AnimatedBuilder(
              animation: _scale,
              builder: (context, _) {
                return Transform.scale(
                  scale: _scale.value.clamp(0.0, 1.0),
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryBlue
                              .withValues(alpha: 0.40),
                          blurRadius: 32,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: AppColors.white,
                      size: 72,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 36),
          Text(
            'Your account is ready',
            textAlign: TextAlign.center,
            style: AppTextStyles.displayLarge.copyWith(
              color: AppColors.darkNavy,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.18,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Welcome to the community. Let\'s get you home.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.65),
              height: 1.5,
              fontSize: 14.5,
            ),
          ),
          const Spacer(),
          _PrimaryButton(
            label: 'Enter App',
            busy: false,
            onTap: widget.onEnter,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// =============================================================================
// Shared building blocks
// =============================================================================

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.tagline,
    required this.title,
    required this.subtitle,
  });

  final String tagline;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tagline.toUpperCase(),
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.primaryBlue,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: AppTextStyles.displayMedium.copyWith(
            color: AppColors.darkNavy,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: AppTextStyles.bodyMedium.copyWith(
            color: const Color.fromRGBO(26, 26, 46, 0.65),
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.labelSmall.copyWith(
        color: const Color.fromRGBO(26, 26, 46, 0.55),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}

class _GlowField extends StatefulWidget {
  const _GlowField({
    required this.controller,
    required this.icon,
    required this.hint,
    this.maxLines = 1,
    this.onChanged,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  State<_GlowField> createState() => _GlowFieldState();
}

class _GlowFieldState extends State<_GlowField> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : [],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        maxLines: widget.maxLines,
        onChanged: widget.onChanged,
        style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: const Color.fromRGBO(26, 26, 46, 0.5),
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 18, right: 12),
            child: Icon(
              widget.icon,
              color: _focused
                  ? AppColors.primaryBlue
                  : const Color.fromRGBO(26, 26, 46, 0.5),
              size: 20,
            ),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 48, minHeight: 48),
          filled: true,
          fillColor: context.palette.inputFill,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(
              color: Color.fromRGBO(26, 26, 46, 0.10),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(
              color: Color.fromRGBO(26, 26, 46, 0.10),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(
              color: AppColors.primaryBlue,
              width: 1.6,
            ),
          ),
        ),
      ),
    );
  }
}
