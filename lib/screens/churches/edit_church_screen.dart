import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/church_service.dart';
import '../../services/location_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/screen_shell.dart';

/// Church-admin "Manage church info" editor. An approved admin can update
/// the public church profile — logo, cover, about, address/location and
/// contact details. Writes go straight to the `churches` row; RLS
/// (churches_update_admin, patch_121) restricts this to approved admins
/// and a column guard keeps trust/rollup fields read-only.
class EditChurchScreen extends StatefulWidget {
  const EditChurchScreen({super.key, required this.role});

  final ChurchAdminRole role;

  @override
  State<EditChurchScreen> createState() => _EditChurchScreenState();
}

class _EditChurchScreenState extends State<EditChurchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _address = TextEditingController();
  final _suburb = TextEditingController();
  final _city = TextEditingController();
  final _pastor = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _foundedYear = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();

  String? _coverUrl;
  String? _logoUrl;

  bool _loading = true;
  bool _saving = false;
  bool _uploadingCover = false;
  bool _uploadingLogo = false;
  String? _loadError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    _address.dispose();
    _suburb.dispose();
    _city.dispose();
    _pastor.dispose();
    _phone.dispose();
    _email.dispose();
    _foundedYear.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final church = await ChurchService.fetchChurchById(widget.role.churchId);
      if (!mounted) return;
      if (church == null) {
        setState(() {
          _loadError = 'Could not load this church.';
          _loading = false;
        });
        return;
      }
      _description.text = church.description ?? '';
      _address.text = church.address ?? '';
      _suburb.text = church.suburb ?? '';
      _city.text = church.city;
      _pastor.text = church.pastorName ?? '';
      _phone.text = church.contactPhone ?? '';
      _email.text = church.contactEmail ?? '';
      _foundedYear.text = church.foundedYear?.toString() ?? '';
      _latitude.text = church.latitude?.toString() ?? '';
      _longitude.text = church.longitude?.toString() ?? '';
      _coverUrl = church.coverPhotoUrl;
      _logoUrl = church.profilePhotoUrl;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load this church. Pull to retry.';
        _loading = false;
      });
    }
  }

  Future<void> _pickCover() async {
    setState(() => _uploadingCover = true);
    try {
      final url = await StorageService.pickAndUploadChurchCover();
      if (!mounted) return;
      if (url != null) setState(() => _coverUrl = url);
    } catch (e) {
      _toast(_msg(e), AppColors.red);
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _pickLogo() async {
    setState(() => _uploadingLogo = true);
    try {
      final url = await StorageService.pickAndUploadChurchLogo();
      if (!mounted) return;
      if (url != null) setState(() => _logoUrl = url);
    } catch (e) {
      _toast(_msg(e), AppColors.red);
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saveError = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      var lat = double.tryParse(_latitude.text.trim());
      var lng = double.tryParse(_longitude.text.trim());
      // If there's an address but no manual coordinates, geocode the address so
      // this church can be found by real distance in "Near me". Best-effort —
      // a failed geocode just saves without coordinates.
      if ((lat == null || lng == null) && _address.text.trim().isNotEmpty) {
        final geo = await LocationService.geocodeAddress(
          [_address.text, _suburb.text, _city.text, 'Zimbabwe']
              .where((s) => s.trim().isNotEmpty)
              .join(', '),
        );
        if (geo != null) {
          lat = geo.lat;
          lng = geo.lng;
        }
      }
      await ChurchService.updateChurch(
        churchId: widget.role.churchId,
        description: _description.text,
        address: _address.text,
        suburb: _suburb.text,
        city: _city.text,
        pastorName: _pastor.text,
        phone: _phone.text,
        email: _email.text,
        foundedYear: int.tryParse(_foundedYear.text.trim()),
        latitude: lat,
        longitude: lng,
        coverPhotoUrl: _coverUrl,
        profilePhotoUrl: _logoUrl,
      );
      if (!mounted) return;
      _toast('Church profile updated.', AppColors.successGreen);
      if (context.canPop()) context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saveError = _msg(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  void _toast(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: bg,
      content: Text(msg,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: _loading
          ? Column(
              children: [
                ScreenHero(
                  title: 'Church info',
                  tagline: widget.role.churchName,
                  subtitle: 'Loading…',
                  fallbackRoute: 'churches',
                ),
                const Expanded(
                  child: Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primaryBlue),
                  ),
                ),
              ],
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ScreenHero(
                    title: 'Church info',
                    tagline: widget.role.churchName,
                    subtitle: 'Update what members see on your church page.',
                    fallbackRoute: 'churches',
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
                    child: _loadError != null
                        ? ErrorBanner(message: _loadError!)
                        : _buildForm(context),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhotoLabel('Cover photo'),
          _CoverPicker(
            url: _coverUrl,
            busy: _uploadingCover,
            onTap: _uploadingCover ? null : _pickCover,
          ),
          const SizedBox(height: 18),
          _PhotoLabel('Church logo'),
          _LogoPicker(
            url: _logoUrl,
            busy: _uploadingLogo,
            onTap: _uploadingLogo ? null : _pickLogo,
          ),
          const SizedBox(height: 20),
          _Label('About this church'),
          TextFormField(
            controller: _description,
            minLines: 3,
            maxLines: 6,
            maxLength: 600,
            textCapitalization: TextCapitalization.sentences,
            decoration: _dec(context,
                hint: 'Tell members about your church, services, vision…'),
          ),
          const SizedBox(height: 12),
          _Label('Street address'),
          TextFormField(
            controller: _address,
            textCapitalization: TextCapitalization.words,
            decoration: _dec(context, hint: 'e.g. 12 Samora Machel Ave'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('Suburb'),
                    TextFormField(
                      controller: _suburb,
                      textCapitalization: TextCapitalization.words,
                      decoration: _dec(context, hint: 'Suburb'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('City'),
                    TextFormField(
                      controller: _city,
                      textCapitalization: TextCapitalization.words,
                      decoration: _dec(context, hint: 'City'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter a city'
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Label('Map location (optional)'),
          Text(
            'Paste coordinates so members get a map + directions. Tip: long-'
            'press your church in Google Maps to copy its latitude, longitude.',
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _latitude,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                  ],
                  decoration: _dec(context, hint: 'Latitude'),
                  validator: _coordValidator,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _longitude,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                  ],
                  decoration: _dec(context, hint: 'Longitude'),
                  validator: _coordValidator,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Label('Pastor'),
          TextFormField(
            controller: _pastor,
            textCapitalization: TextCapitalization.words,
            decoration: _dec(context, hint: 'Pastor\'s name'),
          ),
          const SizedBox(height: 16),
          _Label('Contact phone'),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            ],
            decoration: _dec(context, hint: 'e.g. +263 77 123 4567'),
          ),
          const SizedBox(height: 16),
          _Label('Contact email'),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: _dec(context, hint: 'church@example.com'),
          ),
          const SizedBox(height: 16),
          _Label('Founded year'),
          TextFormField(
            controller: _foundedYear,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration:
                _dec(context, hint: 'e.g. 1985').copyWith(counterText: ''),
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) return null;
              final y = int.tryParse(t);
              if (y == null || y < 1800 || y > DateTime.now().year) {
                return 'Enter a valid year';
              }
              return null;
            },
          ),
          if (_saveError != null) ...[
            const SizedBox(height: 14),
            ErrorBanner(message: _saveError!),
          ],
          const SizedBox(height: 22),
          PrimaryGradientButton(
            label: _saving ? 'Saving…' : 'Save changes',
            busy: _saving,
            onTap: _saving ? null : _save,
          ),
        ],
      ),
    );
  }

  String? _coordValidator(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null; // optional
    if (double.tryParse(t) == null) return 'Invalid number';
    return null;
  }

  InputDecoration _dec(BuildContext context, {required String hint}) {
    final p = context.palette;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.bodyMedium.copyWith(color: p.textMuted),
      filled: true,
      fillColor: p.cardMuted,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(p.divider),
      enabledBorder: border(p.divider),
      focusedBorder: border(AppColors.primaryBlue, 1.5),
      errorBorder: border(AppColors.red),
      focusedErrorBorder: border(AppColors.red, 1.5),
    );
  }
}

class _CoverPicker extends StatelessWidget {
  const _CoverPicker({required this.url, required this.busy, this.onTap});

  final String? url;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              color: p.cardMuted,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url != null && url!.isNotEmpty)
                  CachedImage(url!, fit: BoxFit.cover)
                else
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            color: p.textMuted, size: 30),
                        const SizedBox(height: 6),
                        Text('Add a cover photo',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: p.textMuted)),
                      ],
                    ),
                  ),
                if (busy)
                  Container(
                    color: const Color.fromRGBO(0, 0, 0, 0.35),
                    child: const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.white),
                    ),
                  ),
                if (!busy && url != null && url!.isNotEmpty)
                  const Positioned(
                    right: 10,
                    bottom: 10,
                    child: _EditChip(label: 'Change'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoPicker extends StatelessWidget {
  const _LogoPicker({required this.url, required this.busy, this.onTap});

  final String? url;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.cardMuted,
            border: Border.all(color: p.divider, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: busy
              ? const Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: AppColors.primaryBlue))
              : (url != null && url!.isNotEmpty)
                  ? CachedImage(url!, fit: BoxFit.cover)
                  : Icon(Icons.church, color: p.textMuted, size: 32),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Shown as your church\'s avatar across the app.',
                style: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: Text(
                    url != null && url!.isNotEmpty ? 'Change logo' : 'Upload',
                    style: AppTextStyles.labelMedium),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryBlue,
                  side: const BorderSide(color: AppColors.primaryBlue),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditChip extends StatelessWidget {
  const _EditChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(0, 0, 0, 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.edit, size: 14, color: AppColors.white),
          const SizedBox(width: 5),
          Text(label,
              style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        text,
        style: AppTextStyles.labelMedium.copyWith(
          fontWeight: FontWeight.w700,
          color: context.palette.text,
        ),
      ),
    );
  }
}

class _PhotoLabel extends StatelessWidget {
  const _PhotoLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Text(
        text.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: context.palette.textMuted,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          fontSize: 11,
        ),
      ),
    );
  }
}
