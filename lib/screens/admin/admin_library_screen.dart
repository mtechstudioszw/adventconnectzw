import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/hymn_model.dart';
import '../../models/library_item_model.dart';
import '../../services/library_admin_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Super-admin "Manage Library" console. Curate the structured Hymnal and
/// upload Music + EGW-book PDFs that surface in the in-app Library. Gated by
/// the `is_super_admin()` RLS policies (patch_133); the entry only shows for
/// super admins in Settings.
class AdminLibraryScreen extends StatefulWidget {
  const AdminLibraryScreen({super.key});

  @override
  State<AdminLibraryScreen> createState() => _AdminLibraryScreenState();
}

class _AdminLibraryScreenState extends State<AdminLibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        title: Text('Manage Library',
            style: AppTextStyles.appBarTitle.copyWith(fontSize: 19)),
        foregroundColor: AppColors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.goldAccent,
          indicatorWeight: 3,
          labelColor: AppColors.white,
          unselectedLabelColor: AppColors.white.withValues(alpha: 0.6),
          labelStyle:
              AppTextStyles.labelMedium.copyWith(fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Hymns'),
            Tab(text: 'Audio Bible'),
            Tab(text: 'Music'),
            Tab(text: 'EGW Books'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabs,
          children: const [
            _HymnsAdminTab(),
            _UploadAdminTab(
              kind: 'audio_bible',
              extensions: ['mp3', 'm4a', 'aac', 'wav', 'ogg'],
              addLabel: 'Add audio',
              pickLabel: 'Pick audio file',
              authorLabel: 'Book / reader (optional)',
              emptyText:
                  'No audio Bible yet. Tap “Add audio” to upload a chapter.',
              leadingIcon: Icons.headset,
            ),
            _UploadAdminTab(
              kind: 'music',
              extensions: ['mp3', 'm4a', 'aac', 'wav', 'ogg'],
              addLabel: 'Add music',
              pickLabel: 'Pick audio file',
              authorLabel: 'Artist (optional)',
              emptyText: 'No music yet. Tap “Add music” to upload a track.',
              leadingIcon: Icons.music_note,
            ),
            _UploadAdminTab(
              kind: 'egw_book',
              extensions: ['pdf'],
              addLabel: 'Add book',
              pickLabel: 'Pick PDF file',
              authorLabel: 'Author (optional)',
              emptyText: 'No books yet. Tap “Add book” to upload a PDF.',
              leadingIcon: Icons.menu_book,
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
//  Hymns
// ===========================================================================

class _HymnsAdminTab extends StatefulWidget {
  const _HymnsAdminTab();

  @override
  State<_HymnsAdminTab> createState() => _HymnsAdminTabState();
}

class _HymnsAdminTabState extends State<_HymnsAdminTab> {
  late Future<List<Hymn>> _future;

  @override
  void initState() {
    super.initState();
    _future = LibraryAdminService.fetchAllHymns();
  }

  void _reload() =>
      setState(() => _future = LibraryAdminService.fetchAllHymns());

  Future<void> _openEditor([Hymn? hymn]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _HymnEditorScreen(hymn: hymn)),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(Hymn hymn) async {
    final ok = await _confirmDelete(context, hymn.displayTitle);
    if (ok != true) return;
    try {
      await LibraryAdminService.deleteHymn(hymn.id);
      _reload();
    } catch (e) {
      if (mounted) _toast(context, 'Could not delete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: AppColors.white,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add hymn'),
      ),
      body: FutureBuilder<List<Hymn>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primaryBlue));
          }
          if (snap.hasError) {
            return _ErrorState(message: '${snap.error}', onRetry: _reload);
          }
          final hymns = snap.data ?? const [];
          if (hymns.isEmpty) {
            return const _EmptyState(
              icon: Icons.library_music_outlined,
              text: 'No hymns yet. Tap “Add hymn” to create one.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: hymns.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final h = hymns[i];
              return Material(
                color: palette.card,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _openEditor(h),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: palette.divider),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(h.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.titleSmall
                                      .copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(h.lyrics.replaceAll('\n', ' '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodySmall
                                      .copyWith(color: palette.textMuted)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: AppColors.red),
                          onPressed: () => _delete(h),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _HymnEditorScreen extends StatefulWidget {
  const _HymnEditorScreen({this.hymn});
  final Hymn? hymn;

  @override
  State<_HymnEditorScreen> createState() => _HymnEditorScreenState();
}

class _HymnEditorScreenState extends State<_HymnEditorScreen> {
  late final _number = TextEditingController(
      text: widget.hymn?.number?.toString() ?? '');
  late final _title = TextEditingController(text: widget.hymn?.title ?? '');
  late final _lyrics = TextEditingController(text: widget.hymn?.lyrics ?? '');
  late final _language =
      TextEditingController(text: widget.hymn?.language ?? 'Shona');
  bool _saving = false;

  @override
  void dispose() {
    _number.dispose();
    _title.dispose();
    _lyrics.dispose();
    _language.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _lyrics.text.trim().isEmpty) {
      _toast(context, 'Title and lyrics are required.');
      return;
    }
    setState(() => _saving = true);
    try {
      await LibraryAdminService.saveHymn(
        id: widget.hymn?.id,
        number: int.tryParse(_number.text.trim()),
        title: _title.text,
        lyrics: _lyrics.text,
        language: _language.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context, 'Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        title: Text(widget.hymn == null ? 'New hymn' : 'Edit hymn',
            style: AppTextStyles.appBarTitle.copyWith(fontSize: 18)),
        foregroundColor: AppColors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.appBarGradient),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: _field(context,
                      controller: _number,
                      label: 'Number',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(context,
                      controller: _language, label: 'Language'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _field(context, controller: _title, label: 'Title'),
            const SizedBox(height: 12),
            _field(context,
                controller: _lyrics,
                label: 'Lyrics',
                minLines: 8,
                maxLines: 30),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: AppColors.white))
                    : const Icon(Icons.check),
                label: Text(_saving ? 'Saving…' : 'Save hymn',
                    style: AppTextStyles.buttonText
                        .copyWith(color: AppColors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
//  Music + EGW (file uploads)
// ===========================================================================

class _UploadAdminTab extends StatefulWidget {
  const _UploadAdminTab({
    required this.kind,
    required this.extensions,
    required this.addLabel,
    required this.pickLabel,
    required this.authorLabel,
    required this.emptyText,
    required this.leadingIcon,
  });

  final String kind;
  final List<String> extensions;
  final String addLabel;
  final String pickLabel;
  final String authorLabel;
  final String emptyText;
  final IconData leadingIcon;

  @override
  State<_UploadAdminTab> createState() => _UploadAdminTabState();
}

class _UploadAdminTabState extends State<_UploadAdminTab> {
  late Future<List<LibraryItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = LibraryAdminService.fetchAllItems(widget.kind);
  }

  void _reload() =>
      setState(() => _future = LibraryAdminService.fetchAllItems(widget.kind));

  Future<void> _add() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UploadSheet(
        kind: widget.kind,
        extensions: widget.extensions,
        pickLabel: widget.pickLabel,
        authorLabel: widget.authorLabel,
      ),
    );
    if (added == true) _reload();
  }

  Future<void> _delete(LibraryItem item) async {
    final ok = await _confirmDelete(context, item.title);
    if (ok != true) return;
    try {
      await LibraryAdminService.deleteItem(item.id);
      _reload();
    } catch (e) {
      if (mounted) _toast(context, 'Could not delete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: AppColors.white,
        onPressed: _add,
        icon: const Icon(Icons.upload_file),
        label: Text(widget.addLabel),
      ),
      body: FutureBuilder<List<LibraryItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primaryBlue));
          }
          if (snap.hasError) {
            return _ErrorState(message: '${snap.error}', onRetry: _reload);
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return _EmptyState(icon: widget.leadingIcon, text: widget.emptyText);
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final item = items[i];
              return Material(
                color: palette.card,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.divider),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          shape: BoxShape.circle,
                        ),
                        child:
                            Icon(widget.leadingIcon, color: AppColors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.titleSmall
                                    .copyWith(fontWeight: FontWeight.w700)),
                            if (item.author != null &&
                                item.author!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(item.author!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodySmall
                                      .copyWith(color: palette.textMuted)),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.red),
                        onPressed: () => _delete(item),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _UploadSheet extends StatefulWidget {
  const _UploadSheet({
    required this.kind,
    required this.extensions,
    required this.pickLabel,
    required this.authorLabel,
  });

  final String kind;
  final List<String> extensions;
  final String pickLabel;
  final String authorLabel;

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  final _title = TextEditingController();
  final _author = TextEditingController();
  String? _path;
  String? _fileName;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final res =
          await LibraryAdminService.pickFile(extensions: widget.extensions);
      if (res == null || !mounted) return;
      setState(() {
        _path = res.path;
        _fileName = res.name;
        if (_title.text.trim().isEmpty) {
          // Pre-fill the title from the filename (minus extension).
          final dot = res.name.lastIndexOf('.');
          _title.text = dot > 0 ? res.name.substring(0, dot) : res.name;
        }
      });
    } catch (e) {
      _toast(context, 'Could not pick file: $e');
    }
  }

  Future<void> _save() async {
    if (_path == null) {
      _toast(context, 'Pick a file first.');
      return;
    }
    if (_title.text.trim().isEmpty) {
      _toast(context, 'Enter a title.');
      return;
    }
    setState(() => _saving = true);
    try {
      await LibraryAdminService.uploadAndAddItem(
        kind: widget.kind,
        title: _title.text,
        filePath: _path!,
        fileName: _fileName!,
        author: _author.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context, 'Upload failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryBlue,
                side: const BorderSide(color: AppColors.primaryBlue),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _saving ? null : _pick,
              icon: const Icon(Icons.attach_file),
              label: Text(_fileName ?? widget.pickLabel,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 14),
            _field(context, controller: _title, label: 'Title'),
            const SizedBox(height: 12),
            _field(context, controller: _author, label: widget.authorLabel),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: AppColors.white))
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(_saving ? 'Uploading…' : 'Upload',
                    style: AppTextStyles.buttonText
                        .copyWith(color: AppColors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
//  Shared bits
// ===========================================================================

Widget _field(
  BuildContext context, {
  required TextEditingController controller,
  required String label,
  int minLines = 1,
  int maxLines = 1,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
}) {
  final palette = context.palette;
  return TextField(
    controller: controller,
    minLines: minLines,
    maxLines: maxLines,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    textCapitalization: TextCapitalization.sentences,
    style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
      filled: true,
      fillColor: palette.inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryBlue),
      ),
    ),
  );
}

Future<bool?> _confirmDelete(BuildContext context, String what) {
  final palette = context.palette;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.card,
      title: Text('Delete?',
          style:
              AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w700)),
      content: Text('Remove “$what” from the Library? This can’t be undone.',
          style: AppTextStyles.bodyMedium.copyWith(color: palette.text)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: TextStyle(color: palette.textMuted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

void _toast(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white)),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 60, color: palette.textMuted),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style:
                    AppTextStyles.bodyMedium.copyWith(color: palette.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.red),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style:
                    AppTextStyles.bodySmall.copyWith(color: palette.textMuted)),
            const SizedBox(height: 16),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
