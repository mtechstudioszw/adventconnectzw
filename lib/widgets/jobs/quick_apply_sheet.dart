import 'package:flutter/material.dart';

import '../../models/job_model.dart';
import '../../services/cache_service.dart';
import '../../services/job_application_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Another way to reach the poster, offered under Quick apply.
class ApplyRoute {
  const ApplyRoute(this.code, this.icon, this.title, this.subtitle);
  final String code;
  final IconData icon;
  final String title;
  final String subtitle;
}

/// Quick apply (patch_278): a short message and a number to reach you, sent
/// to the poster inside the app — they're notified, see it in Applicants
/// and can shortlist you. Under it, the poster's own routes (link, email,
/// WhatsApp, call) for anyone who'd rather apply directly.
///
/// Returns 'sent' after a successful application, a route code when the
/// member picked another way, or null.
Future<String?> showQuickApplySheet(
  BuildContext context, {
  required Job job,
  required List<ApplyRoute> routes,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.palette.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _QuickApplySheet(job: job, routes: routes),
  );
}

class _QuickApplySheet extends StatefulWidget {
  const _QuickApplySheet({required this.job, required this.routes});
  final Job job;
  final List<ApplyRoute> routes;

  @override
  State<_QuickApplySheet> createState() => _QuickApplySheetState();
}

class _QuickApplySheetState extends State<_QuickApplySheet> {
  /// User-scoped (no `pref:`): sign-out clears the number.
  static const _phoneKey = 'job_apply_phone';

  late final _message = TextEditingController(
    text: "Hello, I'd like to apply for the ${widget.job.title} position. ",
  );
  late final _phone = TextEditingController(
    text: CacheService.readStringStale(_phoneKey) ?? '',
  );
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await JobApplicationService.apply(
        jobId: widget.job.id,
        message: _message.text,
        phone: _phone.text,
      );
      try {
        await CacheService.writeString(_phoneKey, _phone.text.trim());
      } catch (_) {}
      if (mounted) Navigator.pop(context, 'sent');
    } catch (e) {
      final s = e.toString();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = s.contains('23505') || s.contains('duplicate')
            ? 'You have already applied for this job.'
            : s.contains('30 applications')
            ? 'You have sent 30 applications today. Try again tomorrow.'
            : s.contains('row-level security') || s.contains('42501')
            ? 'This job is no longer taking applications.'
            : "Couldn't send your application. Check your connection.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    InputDecoration dec(String hint, IconData icon) => InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.primaryBlue, size: 20),
      filled: true,
      fillColor: palette.cardMuted,
      counterText: '',
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Quick apply',
                style: AppTextStyles.titleLarge.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.job.title}'
                '${widget.job.company.trim().isEmpty ? '' : ' · ${widget.job.company.trim()}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.textMuted,
                ),
              ),
              if ((widget.job.applyInstructions ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.job.applyInstructions!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.text,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _message,
                minLines: 3,
                maxLines: 6,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
                decoration: dec(
                  'Say why you are a good fit',
                  Icons.edit_note_rounded,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                maxLength: 30,
                keyboardType: TextInputType.phone,
                style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
                decoration: dec(
                  'Phone or WhatsApp (optional)',
                  Icons.phone_outlined,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The employer sees your name, profile photo, this message and '
                'the number you give.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.textMuted,
                  fontSize: 11.5,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.red),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(_sending ? 'Sending…' : 'Send application'),
                ),
              ),
              if (widget.routes.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Or apply directly',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                for (final r in widget.routes)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(r.icon, color: AppColors.primaryBlue),
                    title: Text(
                      r.title,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      r.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: palette.textMuted,
                    ),
                    onTap: () => Navigator.pop(context, r.code),
                  ),
              ],
              const SizedBox(height: 8),
              Text(
                'Never pay to apply for a job. Report listings that ask for '
                'money.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
