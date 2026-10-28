import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/org_page_model.dart';
import '../../services/page_service.dart';
import '../../services/storage_service.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/country_picker_sheet.dart';
import '../../widgets/screen_shell.dart';

/// Create or edit an organization Page (brief §9, "Page creation").
///
/// Verification is never a field here: the guard trigger ignores it from
/// anyone but the super admin. Churches are not a category — they use the
/// church directory and its appointment-letter approval, and the form says
/// so rather than letting someone set up an unofficial church Page.
class PageEditScreen extends StatefulWidget {
  const PageEditScreen({super.key, this.existing});

  final OrgPage? existing;

  @override
  State<PageEditScreen> createState() => _PageEditScreenState();
}

/// The edit route opened without the Page in hand (a deep link or a
/// restored route): load it first, so it can never fall through to a
/// blank "Create a Page" form.
class PageEditLoader extends StatelessWidget {
  const PageEditLoader({super.key, required this.pageId});
  final String pageId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OrgPage?>(
      future: PageService.fetch(pageId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final page = snap.data;
        if (page == null) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Column(
              children: const [
                ScreenHero(title: 'Edit Page', fallbackRoute: 'pages'),
                Padding(
                  padding: EdgeInsets.all(24),
                  child: EmptyStateCard(
                    icon: Icons.apartment_rounded,
                    title: 'Page unavailable',
                    message: 'This Page could not be loaded.',
                  ),
                ),
              ],
            ),
          );
        }
        return PageEditScreen(existing: page);
      },
    );
  }
}

class _PageEditScreenState extends State<PageEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _description = TextEditingController(
    text: widget.existing?.description,
  );
  late final _city = TextEditingController(text: widget.existing?.city);
  late final _area = TextEditingController(text: widget.existing?.serviceArea);
  late final _email = TextEditingController(
    text: widget.existing?.contactEmail,
  );
  late final _phone = TextEditingController(
    text: widget.existing?.contactPhone,
  );
  late final _website = TextEditingController(text: widget.existing?.website);
  late PageCategory? _category = widget.existing?.category;
  late String? _country = widget.existing?.country;
  late String? _logo = widget.existing?.logoUrl;
  late String? _cover = widget.existing?.coverUrl;
  bool _saving = false;
  bool _uploading = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _city,
      _area,
      _email,
      _phone,
      _website,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _clean(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _upload(bool logo) async {
    setState(() => _uploading = true);
    try {
      final url = logo
          ? await StorageService.pickAndUploadPageLogo()
          : await StorageService.pickAndUploadPageCover();
      if (url != null && mounted) {
        setState(() => logo ? _logo = url : _cover = url);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not upload that photo.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final draft = OrgPage(
      id: widget.existing?.id ?? '',
      name: _name.text.trim(),
      category: _category!,
      description: _clean(_description),
      logoUrl: _logo,
      coverUrl: _cover,
      city: _clean(_city),
      country: _country,
      serviceArea: _clean(_area),
      contactEmail: _clean(_email),
      contactPhone: _clean(_phone),
      website: UserProfileService.normalizeWebsite(_website.text),
    );
    setState(() => _saving = true);
    try {
      final saved = _isEdit
          ? await PageService.update(draft)
          : await PageService.create(draft);
      if (!mounted) return;
      if (_isEdit) {
        context.pop(saved);
      } else {
        context.pushReplacementNamed(
          'page_details',
          pathParameters: {'id': saved.id},
          extra: saved,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            PageService.messageFor(e) ??
            'Could not save the Page. Please try again.';
      });
    }
  }

  Future<void> _delete() async {
    final page = widget.existing!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${page.name}?'),
        content: const Text(
          'The Page, its updates and its followers are removed for good.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await PageService.delete(page.id);
      if (!mounted) return;
      context.goNamed('pages');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Only a Page owner can delete it.');
      }
    }
  }

  InputDecoration _dec(String hint, IconData icon) {
    final palette = context.palette;
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.primaryBlue, size: 20),
      filled: true,
      fillColor: palette.cardMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: BorderSide(color: palette.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: BorderSide(color: palette.divider),
      ),
    );
  }

  Widget _label(String text, {String? helper}) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 14),
    child: Row(
      children: [
        Text(
          text,
          style: AppTextStyles.labelLarge.copyWith(
            color: context.palette.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (helper != null) ...[
          const SizedBox(width: 6),
          Text(
            helper,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _card(List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
    decoration: BoxDecoration(
      color: context.palette.card,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      boxShadow: AppShadows.card(context),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Form(
        key: _form,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            ScreenHero(
              title: _isEdit ? 'Edit Page' : 'Create a Page',
              tagline: 'PAGES',
              fallbackRoute: 'pages',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _card([
                    _label('Photos'),
                    Row(
                      children: [
                        _PhotoSlot(
                          url: _logo,
                          size: 84,
                          label: 'Logo',
                          onTap: _uploading ? null : () => _upload(true),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PhotoSlot(
                            url: _cover,
                            size: 84,
                            label: 'Cover photo',
                            wide: true,
                            onTap: _uploading ? null : () => _upload(false),
                          ),
                        ),
                      ],
                    ),
                    if (_uploading)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(),
                      ),
                  ]),
                  _card([
                    _label('Page name'),
                    TextFormField(
                      controller: _name,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.words,
                      decoration: _dec(
                        'e.g. Harare Pathfinder Club',
                        Icons.apartment_rounded,
                      ),
                      validator: (v) => (v ?? '').trim().length < 2
                          ? 'Enter the organization\'s name'
                          : null,
                    ),
                    _label('Category'),
                    DropdownButtonFormField<PageCategory>(
                      initialValue: _category,
                      decoration: _dec('Choose one', Icons.category_outlined),
                      items: [
                        for (final c in PageCategory.values)
                          DropdownMenuItem(value: c, child: Text(c.label)),
                      ],
                      onChanged: (c) => setState(() => _category = c),
                      validator: (c) => c == null ? 'Choose a category' : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Running a church? Churches have their own directory '
                        'with verified admins — find yours under Churches.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                    _label('About', helper: 'optional'),
                    TextFormField(
                      controller: _description,
                      maxLength: 1500,
                      maxLines: 5,
                      minLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _dec(
                        'What the organization does and who it serves',
                        Icons.notes_rounded,
                      ),
                    ),
                  ]),
                  _card([
                    _label('Where', helper: 'optional'),
                    TextFormField(
                      controller: _city,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.words,
                      decoration: _dec('Town or city', Icons.location_city),
                    ),
                    CountryField(
                      code: _country,
                      onChanged: (c) => setState(() => _country = c.code),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _area,
                      maxLength: 120,
                      decoration: _dec(
                        'Area served, e.g. All of Mashonaland',
                        Icons.map_outlined,
                      ),
                    ),
                  ]),
                  _card([
                    _label('Public contact', helper: 'optional'),
                    Text(
                      'Shown to everyone on the Page. Use the organization\'s '
                      'details, not your personal ones.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: _dec('Email', Icons.mail_outline),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return null;
                        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)
                            ? null
                            : 'That email address does not look right';
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: _dec(
                        'Phone / WhatsApp, e.g. +263 77 123 4567',
                        Icons.call_outlined,
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return null;
                        return RegExp(r'^\+?[0-9 ()-]{6,20}$').hasMatch(t)
                            ? null
                            : 'That phone number does not look right';
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _website,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: _dec('Website', Icons.language_rounded),
                      validator: (v) {
                        try {
                          UserProfileService.normalizeWebsite(v ?? '');
                          return null;
                        } on FormatException catch (e) {
                          return e.message;
                        }
                      },
                    ),
                  ]),
                  if (!_isEdit)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'You will be the Page\'s owner and can add other '
                        'admins. Verification is a separate review by the app '
                        'team — it can\'t be bought.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.textMuted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.red,
                        ),
                      ),
                    ),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _saving || _uploading ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.white,
                              ),
                            )
                          : Text(_isEdit ? 'Save changes' : 'Create Page'),
                    ),
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _saving ? null : _delete,
                      child: const Text(
                        'Delete Page',
                        style: TextStyle(color: AppColors.red),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.url,
    required this.size,
    required this.label,
    required this.onTap,
    this.wide = false,
  });
  final String? url;
  final double size;
  final String label;
  final VoidCallback? onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: Container(
          width: wide ? null : size,
          height: size,
          color: palette.cardMuted,
          child: url == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_a_photo_outlined,
                      color: AppColors.primaryBlue,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                )
              : CachedImage(url!, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
