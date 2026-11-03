import 'package:flutter/material.dart';

import '../../../models/sabbath_school_model.dart';
import '../../../services/sabbath_school_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';

/// "Download all" for a Sabbath School quarter (3 Nov 2026): every day of
/// every week saved for reading with no connection. Lives under the
/// current-quarter card on the shelf and at the top of each quarter's
/// lesson list. The download runs in the service, so it carries on if
/// the member leaves the screen, and either copy of this row shows it.
class SsDownloadAll extends StatefulWidget {
  const SsDownloadAll({
    super.key,
    required this.quarterly,
    required this.lang,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 0),
  });

  final Quarterly quarterly;
  final String lang;
  final EdgeInsetsGeometry padding;

  @override
  State<SsDownloadAll> createState() => _SsDownloadAllState();
}

class _SsDownloadAllState extends State<SsDownloadAll> {
  ({int saved, int total})? _status;
  bool _wasRunning = false;

  String get _id => widget.quarterly.id;

  @override
  void initState() {
    super.initState();
    _wasRunning = SabbathSchoolService.quarterProgress.value.containsKey(_id);
    SabbathSchoolService.quarterProgress.addListener(_onProgress);
    _refresh();
  }

  @override
  void didUpdateWidget(SsDownloadAll old) {
    super.didUpdateWidget(old);
    if (old.quarterly.id != _id || old.lang != widget.lang) _refresh();
  }

  @override
  void dispose() {
    SabbathSchoolService.quarterProgress.removeListener(_onProgress);
    super.dispose();
  }

  void _onProgress() {
    final running = SabbathSchoolService.quarterProgress.value.containsKey(_id);
    if (_wasRunning && !running) _refresh(); // just finished or stopped
    _wasRunning = running;
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    try {
      final s = await SabbathSchoolService.quarterlySaved(
        _id,
        lang: widget.lang,
      );
      if (mounted) setState(() => _status = s);
    } catch (_) {}
  }

  Future<void> _start() async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = await SabbathSchoolService.downloadQuarterly(
      _id,
      lang: widget.lang,
    );
    final text = failed == 0
        ? '${widget.quarterly.title} is saved for offline reading.'
        : failed < 0
        ? "Couldn't load this quarter. Check your connection."
        : "$failed week${failed == 1 ? '' : 's'} didn't save. "
              'Tap Download all again to finish.';
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final run = SabbathSchoolService.quarterProgress.value[_id];
    final s = _status;
    final all = run == null && s != null && s.total > 0 && s.saved == s.total;

    final String title;
    final String subtitle;
    final IconData icon;
    VoidCallback? onTap;
    if (run != null) {
      title =
          'Saving week ${run.done < run.total ? run.done + 1 : run.total} '
          'of ${run.total}…';
      subtitle = 'Tap to stop. Weeks already saved stay saved.';
      icon = Icons.downloading_rounded;
      onTap = () => SabbathSchoolService.cancelQuarterly(_id);
    } else if (all) {
      title = 'All ${s.total} weeks saved';
      subtitle = 'Read this quarter with no connection.';
      icon = Icons.offline_pin_rounded;
    } else {
      final weeks = s?.total ?? 13;
      title = 'Download all $weeks weeks';
      subtitle = (s != null && s.saved > 0)
          ? '${s.saved} of $weeks saved · read the whole quarter offline'
          : 'Read the whole quarter with no connection';
      icon = Icons.download_for_offline_rounded;
      onTap = _start;
    }

    return Padding(
      padding: widget.padding,
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.divider),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        (all ? AppColors.successGreen : AppColors.primaryBlue)
                            .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    icon,
                    size: 21,
                    color: all ? AppColors.successGreen : AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (run != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: LinearProgressIndicator(
                            value: run.total == 0 ? null : run.done / run.total,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                            color: AppColors.primaryBlue,
                            backgroundColor: palette.divider,
                          ),
                        )
                      else
                        const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (run != null)
                  Icon(Icons.close_rounded, size: 20, color: palette.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
