import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/share_config.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import 'support_sheet.dart';

/// What the moderators hid.
enum ModeratedKind { listing, post }

/// The prefilled appeal, so the founder can find the item from the message
/// alone: what it is, its link, the reason given, and a line for the
/// member's side.
String appealMessage({
  required ModeratedKind kind,
  required String itemId,
  String? title,
  String? reason,
}) {
  final what = kind == ModeratedKind.listing ? 'listing' : 'post';
  final link = kind == ModeratedKind.listing
      ? productShareUrl(itemId)
      : postShareUrl(itemId);
  final b = StringBuffer(
    'Hello, I would like to appeal: my $what was hidden '
    'on Adventist Super App and I believe this is a mistake.\n\n',
  );
  if (title != null && title.trim().isNotEmpty) {
    b.write('${what[0].toUpperCase()}${what.substring(1)}: ${title.trim()}\n');
  }
  b.write('Link: $link\n');
  if (reason != null && reason.trim().isNotEmpty) {
    b.write('Reason given: ${reason.trim()}\n');
  }
  b.write('\nWhy I think it should be restored: ');
  return b.toString();
}

/// Pulls the item title and the moderator's reason back out of a moderation
/// notification's body, as written by patch_272:
///   `"<title>" was hidden by the moderators. <reason> If you believe…`
///   `Your post "<snippet>" was hidden by the moderators. <reason> If you…`
/// Either part is null when the text doesn't follow that shape.
({String? title, String? reason}) parseModerationNotice(String body) {
  final title = RegExp(r'"([^"]+)"').firstMatch(body)?.group(1);
  final m = RegExp(
    r'moderators\.\s*(.*?)\s*(If you believe.*)?$',
    dotAll: true,
  ).firstMatch(body);
  final reason = m?.group(1)?.trim();
  return (
    title: title,
    reason: (reason == null || reason.isEmpty) ? null : reason,
  );
}

/// "Hidden by the moderators — appeal by email or WhatsApp."
///
/// Founder, 28 Oct 2026: a member whose listing or post is hidden must be
/// told why and given a way to say it was wrongly done. Opened from the
/// moderation notification and from the banner on the hidden item.
Future<void> showModerationAppealSheet(
  BuildContext context, {
  required ModeratedKind kind,
  required String itemId,
  String? title,
  String? reason,
}) {
  return showModalBottomSheet<void>(
      useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _AppealSheet(kind: kind, itemId: itemId, title: title, reason: reason),
  );
}

class _AppealSheet extends StatelessWidget {
  const _AppealSheet({
    required this.kind,
    required this.itemId,
    this.title,
    this.reason,
  });

  final ModeratedKind kind;
  final String itemId;
  final String? title;
  final String? reason;

  String get _message =>
      appealMessage(kind: kind, itemId: itemId, title: title, reason: reason);

  Future<void> _whatsApp() => launchUrl(
    Uri.parse(
      'https://wa.me/$kSupportWhatsApp'
      '?text=${Uri.encodeComponent(_message)}',
    ),
    mode: LaunchMode.externalApplication,
  );

  Future<void> _email() {
    final what = kind == ModeratedKind.listing ? 'listing' : 'post';
    return launchUrl(
      Uri.parse(
        'mailto:$kSupportEmail'
        '?subject=${Uri.encodeComponent('Appeal: hidden $what $itemId')}'
        '&body=${Uri.encodeComponent(_message)}',
      ),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final what = kind == ModeratedKind.listing ? 'listing' : 'post';
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
            const SizedBox(height: 18),
            Text(
              'Your $what was hidden',
              style: AppTextStyles.headlineSmall.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            if (title != null && title!.trim().isNotEmpty)
              Text(
                '"${title!.trim()}"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (reason != null && reason!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.divider),
                ),
                child: Text(
                  'Reason: ${reason!.trim()}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.textMuted,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'If you believe this was a mistake, tell us. Your message is '
              'filled in with the details — just add why it should be '
              'restored. You can also edit it first and then appeal.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            SupportContactTile(
              icon: Icons.chat_rounded,
              iconColor: AppColors.successGreen,
              title: 'Appeal on WhatsApp',
              subtitle: '+$kSupportWhatsApp',
              onTap: () {
                Navigator.pop(context);
                _whatsApp();
              },
            ),
            const SizedBox(height: 10),
            SupportContactTile(
              icon: Icons.email_outlined,
              iconColor: AppColors.primaryBlue,
              title: 'Appeal by email',
              subtitle: kSupportEmail,
              onTap: () {
                Navigator.pop(context);
                _email();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// The strip shown on a hidden item to its owner: what happened, and the
/// way to appeal. Red is right here — it is an action the member must know
/// about, not decoration.
class ModeratedBanner extends StatelessWidget {
  const ModeratedBanner({
    super.key,
    required this.kind,
    required this.itemId,
    this.title,
    this.reason,
    this.ownerView = true,
  });

  final ModeratedKind kind;
  final String itemId;
  final String? title;
  final String? reason;

  /// False when a moderator is looking: no Appeal, and the text says who
  /// can't see it rather than "only you".
  final bool ownerView;

  @override
  Widget build(BuildContext context) {
    final what = kind == ModeratedKind.listing ? 'listing' : 'post';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.visibility_off_outlined,
            color: AppColors.red,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ownerView
                  ? 'Hidden by the moderators. Only you can see this $what.'
                  : 'Hidden by the moderators. Members cannot see this $what.',
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (ownerView)
            TextButton(
              onPressed: () => showModerationAppealSheet(
                context,
                kind: kind,
                itemId: itemId,
                title: title,
                reason: reason,
              ),
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
              child: const Text('Appeal'),
            ),
        ],
      ),
    );
  }
}

/// Asks a moderator why, with [defaultReason] pre-filled. The reason is sent
/// to the member, so it should read as an explanation, not a verdict.
/// Returns null when cancelled.
Future<String?> showModerationReasonDialog(
  BuildContext context, {
  required String what,
  required String defaultReason,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(what: what, defaultReason: defaultReason),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.what, required this.defaultReason});

  final String what;
  final String defaultReason;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late final _controller = TextEditingController(text: widget.defaultReason);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Hide this ${widget.what}?'),
      content: TextField(
        controller: _controller,
        maxLines: 4,
        decoration: const InputDecoration(labelText: 'Reason sent to them'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          style: TextButton.styleFrom(foregroundColor: AppColors.red),
          child: const Text('Hide'),
        ),
      ],
    );
  }
}
