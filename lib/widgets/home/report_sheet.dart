import 'package:flutter/material.dart';
import '../../services/messaging_service.dart';
import '../../services/report_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Bottom sheet for reporting a piece of content (a post, a user, a
/// message, etc). User picks one of the canned reasons, optionally
/// adds details, and submits. The submission lands in the `reports`
/// table for admin review.
///
/// Returns `true` if the report was sent, `null` if cancelled.
Future<bool?> showReportSheet(
  BuildContext context, {
  required String contentType,
  required String contentId,
  required String contentLabel,
  String? reportedText,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ReportSheet(
      contentType: contentType,
      contentId: contentId,
      contentLabel: contentLabel,
      reportedText: reportedText,
    ),
  );
  // Confirm to the reporter wherever it's opened from (mini-profile,
  // chat, profile) — previously only some callers showed feedback.
  if (sent == true) {
    messenger.showSnackBar(
      const SnackBar(
        backgroundColor: AppColors.successGreen,
        content: Text('Report submitted. Our team will review it.'),
      ),
    );
  }
  return sent;
}

const _reasons = <String>[
  'Spam',
  'Harassment / bullying',
  'Hate speech',
  'Inappropriate content',
  'Misinformation',
  'Scam / fraud',
  'Off-topic',
  'Other',
];

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.contentType,
    required this.contentId,
    required this.contentLabel,
    this.reportedText,
  });

  final String contentType;
  final String contentId;
  final String contentLabel;

  /// The reporter's own copy of the reported body, sent with the report.
  /// See [_ReportSheetState._submit].
  final String? reportedText;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _detailsController = TextEditingController();
  String? _reason;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null) {
      setState(() => _error = 'Pick a reason.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final details = _detailsController.text.trim().isEmpty
        ? null
        : _detailsController.text;
    try {
      if (widget.contentType == 'message') {
        // Messages go through report_message() (patch_165) rather than a
        // plain insert. The RPC stamps WHO sent the reported message
        // server-side — a client can't misattribute a report — and stores
        // the reporter's own copy of the text, which survives the sender
        // editing or deleting it afterwards. That stored copy is also the
        // only thing a moderator could ever read if message bodies are
        // end-to-end encrypted later.
        await MessagingService.reportMessage(
          messageId: widget.contentId,
          reason: _reason!,
          details: details,
          textCopy: widget.reportedText,
        );
      } else {
        await ReportService.submit(
          contentType: widget.contentType,
          contentId: widget.contentId,
          reason: _reason!,
          details: details,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not send the report. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: context.palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.palette.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Report ${widget.contentLabel}',
                style: AppTextStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tell us what\'s wrong. The admin team reviews every '
                'report and may take action.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.palette.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in _reasons)
                    _ReasonChip(
                      label: r,
                      selected: _reason == r,
                      onTap: () => setState(() => _reason = r),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: context.palette.inputFill,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.palette.divider),
                ),
                child: TextField(
                  controller: _detailsController,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 14.5,
                    color: context.palette.text,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Anything else we should know? (optional)',
                    hintStyle: AppTextStyles.bodyMedium.copyWith(
                      color: context.palette.textMuted,
                      fontSize: 14.5,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.red),
                ),
              ],
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _submitting ? null : _submit,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppColors.white,
                            ),
                          )
                        : Text(
                            'Send report',
                            style: AppTextStyles.buttonText.copyWith(
                              color: AppColors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryBlue.withValues(alpha: 0.12)
                : context.palette.chipBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.primaryBlue.withValues(alpha: 0.40)
                  : context.palette.divider,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color:
                  selected ? AppColors.primaryBlue : context.palette.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
