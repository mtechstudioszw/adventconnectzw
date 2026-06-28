import 'package:flutter/material.dart';

import '../../models/library_item_model.dart';
import '../../services/library_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import 'bible_tab.dart';
import 'hymnal_tab.dart';
import 'music_tab.dart';
import 'pdf_viewer_screen.dart';

/// The in-app Library: Bible (offline KJV), Hymnal (searchable structured
/// hymns), EGW Books (uploaded PDFs) and Music (background audio player).
/// Reached from the "Bible · Hymnal · EGW · Music" launcher under the
/// devotion card on Home.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.initialTab = 0});

  /// 0=Bible, 1=Hymnal, 2=EGW Books, 3=Music.
  final int initialTab;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 4),
    );
  }

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
      // No ads anywhere in the Library. It's devotional content — Bible,
      // hymns, EGW writings and worship music — so it stays ad-free like the
      // prayer screens (the tester reported the bottom banner was covering the
      // catalog). Revenue stays on the home feed, stories and detail pages.
      appBar: AppBar(
        title: Text('Library',
            style: AppTextStyles.appBarTitle.copyWith(fontSize: 19)),
        foregroundColor: AppColors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.goldAccent,
          indicatorWeight: 3,
          labelColor: AppColors.white,
          unselectedLabelColor: AppColors.white.withValues(alpha: 0.6),
          labelStyle:
              AppTextStyles.labelMedium.copyWith(fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Bible'),
            Tab(text: 'Audio Bible'),
            Tab(text: 'Hymnal'),
            Tab(text: 'EGW Books'),
            Tab(text: 'Music'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabs,
          children: const [
            BibleTab(),
            // Audio Bible — uploaded audio, played through the shared player
            // (background playback + lock-screen controls), like Music.
            MusicTab(
              kind: 'audio_bible',
              emptyText: 'Audio Bible will appear here once it\'s added.',
            ),
            // Hymnal = structured, searchable hymns (number/title/lyrics),
            // entered by the admin one at a time. NOT PDFs.
            HymnalTab(),
            _PdfLibraryTab(
              kind: 'egw_book',
              emptyIcon: Icons.menu_book_outlined,
              emptyText: 'Ellen G. White books will appear here once added.',
            ),
            MusicTab(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  PDF list tab (EGW Books) — also reusable for any uploaded-PDF kind.
// ---------------------------------------------------------------------------

class _PdfLibraryTab extends StatefulWidget {
  const _PdfLibraryTab({
    required this.kind,
    required this.emptyIcon,
    required this.emptyText,
  });

  final String kind;
  final IconData emptyIcon;
  final String emptyText;

  @override
  State<_PdfLibraryTab> createState() => _PdfLibraryTabState();
}

class _PdfLibraryTabState extends State<_PdfLibraryTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<LibraryItem>> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = LibraryService.fetchItems(widget.kind);
  }

  Future<void> _refresh() async {
    final items = LibraryService.fetchItems(widget.kind);
    setState(() => _future = items);
    await items;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: _refresh,
      child: FutureBuilder<List<LibraryItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primaryBlue));
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return _EmptyState(icon: widget.emptyIcon, text: widget.emptyText);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final item = items[i];
              return _LibraryCard(
                item: item,
                leadingIcon: Icons.picture_as_pdf_outlined,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PdfViewerScreen(title: item.title, url: item.fileUrl),
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

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.item,
    required this.leadingIcon,
    required this.onTap,
  });

  final LibraryItem item;
  final IconData leadingIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.divider),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: (item.coverUrl != null && item.coverUrl!.isNotEmpty)
                      ? CachedImage(item.coverUrl!, fit: BoxFit.cover)
                      : DecoratedBox(
                          decoration: const BoxDecoration(
                              gradient: AppColors.primaryGradient),
                          child: Icon(leadingIcon,
                              color: AppColors.white, size: 26),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [item.author, item.language]
                          .where((s) => s != null && s.isNotEmpty)
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: palette.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Icon(icon, size: 60, color: palette.textMuted),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
          ),
        ),
      ],
    );
  }
}
