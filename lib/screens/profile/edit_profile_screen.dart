import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/church_model.dart';
import '../../services/auth_service.dart';
import '../../services/church_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import 'package:cached_network_image/cached_network_image.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  List<Church> _churches = [];
  String? _selectedChurchId;
  String? _profilePhotoUrl;
  String? _coverPhotoUrl;
  bool _saving = false;
  bool _uploadingPhoto = false;
  bool _uploadingCover = false;
  bool _loadingChurches = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
    );

    final meta = AuthService.currentUser?.userMetadata ?? const {};
    _nameController.text = (meta['full_name'] as String?) ?? '';
    _bioController.text = (meta['bio'] as String?) ?? '';
    _selectedChurchId = (meta['church_id'] as String?);
    _profilePhotoUrl = (meta['profile_photo_url'] as String?);
    _coverPhotoUrl = (meta['cover_photo_url'] as String?);
    _loadChurches();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadChurches() async {
    try {
      final list = await ChurchService.fetchChurches();
      if (!mounted) return;
      setState(() {
        _churches = list;
        _loadingChurches = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingChurches = false);
    }
  }

  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Name is required';
    if (v.trim().length < 2) return 'Enter your full name';
    return null;
  }

  String? _validateBio(String? v) {
    if (v != null && v.length > 280) return 'Bio must be 280 characters or fewer';
    return null;
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final previousChurchId =
        AuthService.currentUser?.userMetadata?['church_id'] as String?;
    final result = await AuthService.updateProfile(
      fullName: _nameController.text.trim(),
      bio: _bioController.text.trim(),
      churchId: _selectedChurchId,
      profilePhotoUrl: _profilePhotoUrl,
      coverPhotoUrl: _coverPhotoUrl,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.isSuccess) {
      // Mirror the home-church choice into church_followers so the home
      // screen actually reflects the user's pick. Unfollow the previous
      // church only if it changed — best-effort, network failures here
      // don't block the save.
      if (_selectedChurchId != previousChurchId) {
        if (previousChurchId != null && previousChurchId.isNotEmpty) {
          try {
            await ChurchService.unfollow(previousChurchId);
          } catch (_) {}
        }
        if (_selectedChurchId != null && _selectedChurchId!.isNotEmpty) {
          try {
            await ChurchService.follow(_selectedChurchId!);
          } catch (_) {}
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profile updated.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      context.pop();
    } else {
      setState(() => _error = result.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHero(),
            AnimatedBuilder(
              animation: _entrance,
              builder: (context, child) => Opacity(
                opacity: _fade.value,
                child: Transform.translate(
                  offset: Offset(0, _slide.value),
                  child: child,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildPhotoUploader(),
                      const SizedBox(height: 16),
                      _buildCoverUploader(),
                      const SizedBox(height: 16),
                      _buildFieldsCard(),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        _ErrorBanner(message: _error!),
                      ],
                      const SizedBox(height: 24),
                      _SaveButton(
                        busy: _saving,
                        onTap: _saving ? null : _save,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    return ClipPath(
      clipper: _HeroClipper(),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => context.canPop()
                            ? context.pop()
                            : context.goNamed('profile'),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new,
                            size: 14,
                            color: AppColors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EDIT PROFILE',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tell us about you',
                        style: AppTextStyles.displayMedium.copyWith(
                          color: AppColors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your details help others connect with you.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickProfilePhoto() async {
    if (_uploadingPhoto) return;
    setState(() {
      _uploadingPhoto = true;
      _error = null;
    });
    try {
      final url = await StorageService.pickAndUploadProfilePhoto();
      if (!mounted) return;
      if (url != null) {
        setState(() => _profilePhotoUrl = url);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not upload photo. Try again.');
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _pickCoverPhoto() async {
    if (_uploadingCover) return;
    setState(() {
      _uploadingCover = true;
      _error = null;
    });
    try {
      final url = await StorageService.pickAndUploadCoverPhoto();
      if (!mounted) return;
      if (url != null) {
        setState(() => _coverPhotoUrl = url);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not upload background. Try again.');
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Widget _buildPhotoUploader() {
    final hasPhoto =
        _profilePhotoUrl != null && _profilePhotoUrl!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: hasPhoto ? null : AppColors.primaryGradient,
              color: hasPhoto ? AppColors.lightGrey : null,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.30),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
              image: hasPhoto
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(_profilePhotoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasPhoto
                ? null
                : const Icon(Icons.person, color: AppColors.white, size: 36),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile photo',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasPhoto
                      ? 'Looking good. Tap change to swap it.'
                      : 'Add a clear photo of yourself.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              _UploadButton(
                label: hasPhoto ? 'Change' : 'Upload',
                busy: _uploadingPhoto,
                onTap: _pickProfilePhoto,
              ),
              if (hasPhoto)
                TextButton(
                  onPressed: () => setState(() => _profilePhotoUrl = ''),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Remove'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCoverUploader() {
    final hasCover =
        _coverPhotoUrl != null && _coverPhotoUrl!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: hasCover
                ? CachedImage(
                    _coverPhotoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: context.palette.cardMuted,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  )
                : Container(
                    decoration: const BoxDecoration(
                      gradient: AppColors.appBarGradient,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.image_outlined,
                      color: AppColors.white.withValues(alpha: 0.7),
                      size: 36,
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Background photo',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasCover
                            ? 'Looking good. Tap change to swap it.'
                            : 'Add a cover photo for the top of your profile.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: context.palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  children: [
                    _UploadButton(
                      label: hasCover ? 'Change' : 'Upload',
                      busy: _uploadingCover,
                      onTap: _pickCoverPhoto,
                    ),
                    if (hasCover)
                      TextButton(
                        onPressed: () =>
                            setState(() => _coverPhotoUrl = ''),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Remove'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _LabeledField(
            label: 'Full name',
            child: TextFormField(
              controller: _nameController,
              validator: _validateName,
              textInputAction: TextInputAction.next,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              decoration: _filledDecoration(
                icon: Icons.person_outline,
                hint: 'Tendai Moyo',
              ),
            ),
          ),
          const SizedBox(height: 18),
          _LabeledField(
            label: 'Bio',
            helper: '${_bioController.text.length}/280',
            child: TextFormField(
              controller: _bioController,
              validator: _validateBio,
              maxLength: 280,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              onChanged: (_) => setState(() {}),
              decoration: _filledDecoration(
                icon: Icons.notes_outlined,
                hint: 'A short line about you',
              ).copyWith(counterText: ''),
            ),
          ),
          const SizedBox(height: 18),
          _LabeledField(
            label: 'Home church',
            child: _ChurchDropdown(
              churches: _churches,
              selectedId: _selectedChurchId,
              loading: _loadingChurches,
              onChanged: (id) => setState(() => _selectedChurchId = id),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _filledDecoration({
    required IconData icon,
    required String hint,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 14, right: 10),
        child: Icon(icon, color: AppColors.primaryBlue, size: 20),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      filled: true,
      fillColor: context.palette.cardMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: context.palette.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: context.palette.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5),
      ),
    );
  }
}

class _HeroClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 28);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 28,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
    this.helper,
  });

  final String label;
  final Widget child;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label.toUpperCase(),
              style: AppTextStyles.labelSmall.copyWith(
                color: context.palette.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            if (helper != null)
              Text(
                helper!,
                style: AppTextStyles.labelSmall.copyWith(
                  color: context.palette.textMuted,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ChurchDropdown extends StatelessWidget {
  const _ChurchDropdown({
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
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        decoration: BoxDecoration(
          color: context.palette.cardMuted,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.palette.divider),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'Loading churches...',
              style: AppTextStyles.bodyMedium.copyWith(
                color: context.palette.textMuted,
              ),
            ),
          ],
        ),
      );
    }
    final selected = churches.firstWhere(
      (c) => c.id == selectedId,
      orElse: () => const Church(
        id: '',
        name: '',
        city: '',
        membersCount: 0,
      ),
    );
    final hasSelection = selected.id.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final picked = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (ctx) => _ChurchPickerSheet(
              churches: churches,
              selectedId: selectedId,
            ),
          );
          // null = sheet was dismissed (no change). The sheet returns
          // an empty string when the user picks "No church" so we can
          // distinguish that from a dismiss.
          if (picked == null) return;
          onChanged(picked.isEmpty ? null : picked);
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: context.palette.cardMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: context.palette.divider,
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.church_outlined,
                color: AppColors.primaryBlue,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasSelection
                      ? '${selected.name} • ${selected.city}'
                      : 'Choose your home church',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 15,
                    color: hasSelection
                        ? context.palette.text
                        : context.palette.textMuted,
                  ),
                ),
              ),
              Icon(
                Icons.expand_more,
                color: context.palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChurchPickerSheet extends StatefulWidget {
  const _ChurchPickerSheet({
    required this.churches,
    required this.selectedId,
  });

  final List<Church> churches;
  final String? selectedId;

  @override
  State<_ChurchPickerSheet> createState() => _ChurchPickerSheetState();
}

class _ChurchPickerSheetState extends State<_ChurchPickerSheet> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

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
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final filtered = _filtered;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: context.palette.sheet,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.palette.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Choose your home church',
                    style: AppTextStyles.titleLarge.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    style:
                        AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Search by name or city',
                      hintStyle: AppTextStyles.bodyMedium.copyWith(
                        color: context.palette.textMuted,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.primaryBlue,
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: Icon(
                                Icons.close,
                                color: context.palette.textMuted,
                                size: 18,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                      filled: true,
                      fillColor: context.palette.cardMuted,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _query.isEmpty
                                  ? 'No churches loaded yet.'
                                  : 'No matches for "$_query".',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: context.palette.textMuted,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(
                              8, 4, 8, 24),
                          itemCount: filtered.length + 1,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 2),
                          itemBuilder: (ctx, i) {
                            if (i == 0) {
                              final selected =
                                  widget.selectedId == null ||
                                      widget.selectedId!.isEmpty;
                              return _PickerRow(
                                title: 'No church',
                                subtitle: 'Skip choosing a home church',
                                selected: selected,
                                onTap: () =>
                                    Navigator.of(ctx).pop(''),
                              );
                            }
                            final c = filtered[i - 1];
                            return _PickerRow(
                              title: c.name,
                              subtitle: c.city,
                              selected: c.id == widget.selectedId,
                              onTap: () =>
                                  Navigator.of(ctx).pop(c.id),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryBlue.withValues(alpha: 0.08)
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: selected
                      ? AppColors.primaryGradient
                      : null,
                  color: selected ? null : context.palette.cardMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.church,
                  color: selected
                      ? AppColors.white
                      : AppColors.primaryBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: context.palette.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle,
                  color: AppColors.primaryBlue,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.red, size: 20),
          const SizedBox(width: 10),
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

class _UploadButton extends StatelessWidget {
  const _UploadButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.4),
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryBlue,
                  ),
                )
              : Text(
                  label,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null && !busy ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
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
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.white,
                        ),
                      )
                    : Text(
                        'Save changes',
                        style: AppTextStyles.buttonText.copyWith(
                          fontSize: 15,
                          letterSpacing: 0.4,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
