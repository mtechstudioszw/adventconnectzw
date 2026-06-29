import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/youtube_video.dart';
import '../../services/youtube_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/youtube/youtube_video_card.dart';

/// Search the Watch library (titles, descriptions, channels) — fast,
/// quota-free, faith-safe (only your approved channels, never all of YouTube).
class WatchSearchScreen extends StatefulWidget {
  const WatchSearchScreen({super.key});

  @override
  State<WatchSearchScreen> createState() => _WatchSearchScreenState();
}

class _WatchSearchScreenState extends State<WatchSearchScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<YoutubeVideo> _results = [];
  String _query = '';
  bool _loading = false;
  bool _hasMore = true;
  int _offset = 0;
  static const _page = 30;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
        _search(more: true);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = v.trim();
      _offset = 0;
      _hasMore = true;
      _results.clear();
      _search();
    });
  }

  Future<void> _search({bool more = false}) async {
    if (_query.isEmpty) {
      setState(() => _results.clear());
      return;
    }
    if (more && (!_hasMore || _loading)) return;
    setState(() => _loading = true);
    final rows =
        await YoutubeService.search(_query, limit: _page, offset: _offset);
    if (!mounted) return;
    setState(() {
      _results.addAll(rows);
      _offset += rows.length;
      _hasMore = rows.length == _page;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        foregroundColor: AppColors.white,
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: _onChanged,
          style: const TextStyle(color: AppColors.white),
          cursorColor: AppColors.white,
          decoration: const InputDecoration(
            hintText: 'Search sermons, studies…',
            hintStyle: TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _ctrl.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _query.isEmpty
            ? _hint(palette)
            : (_results.isEmpty && !_loading)
                ? _empty(palette)
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    children: [
                      ..._results.map((v) => YoutubeVideoCard(
                            video: v,
                            onTap: () => context.pushNamed('watch_video',
                                pathParameters: {'id': v.videoId}, extra: v),
                          )),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(18),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primaryBlue)),
                        ),
                    ],
                  ),
      ),
    );
  }

  Widget _hint(AppPalette palette) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Search across all sermons, Bible studies and programs.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
          ),
        ),
      );

  Widget _empty(AppPalette palette) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('No matches for “$_query”.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: palette.textMuted)),
        ),
      );
}
