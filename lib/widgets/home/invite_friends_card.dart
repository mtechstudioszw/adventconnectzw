import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// "Invite friends" prompt that sits on the home feed and helps the app
/// grow when the social graph is still empty. Always visible — the
/// pitch is unchanged whether the user has zero friends or a few.
class InviteFriendsCard extends StatelessWidget {
  const InviteFriendsCard({super.key, this.horizontalMargin = 16});

  /// Outer horizontal margin. Set to 0 when the parent already supplies
  /// edge padding so the card doesn't double-indent.
  final double horizontalMargin;

  // Single canonical landing page — every share button across the app
  // points here so the user lands on a branded site with download links
  // and feature overview.
  static const _inviteMessage =
      'Join me on Advent Connect ZW — the Adventist community app '
      'for Zimbabwe. Connect with members, find churches, share '
      'updates, and chat with friends. Download it here: '
      'https://adventconnectzw.netlify.app/';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.group_add_outlined,
              color: AppColors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Invite friends',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Bring others into the community so you can chat, '
                  'trade, and share together.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _SendButton(onTap: () => _openShareSheet(context)),
        ],
      ),
    );
  }

  Future<void> _openShareSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ShareSheet(message: _inviteMessage),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Invite',
            style: AppTextStyles.buttonText.copyWith(
              color: AppColors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareSheet extends StatelessWidget {
  const _ShareSheet({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: context.palette.sheet,
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
                  color: context.palette.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Share invite',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick how you want to send the invite.',
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            _ChannelTile(
              icon: Icons.chat_bubble,
              label: 'WhatsApp',
              tint: const Color(0xFF25D366),
              onTap: () => _shareViaWhatsApp(context),
            ),
            const SizedBox(height: 10),
            _ChannelTile(
              icon: Icons.sms_outlined,
              label: 'SMS',
              tint: AppColors.primaryBlue,
              onTap: () => _shareViaSms(context),
            ),
            const SizedBox(height: 10),
            _ChannelTile(
              icon: Icons.content_copy,
              label: 'Copy invite text',
              tint: AppColors.darkNavy,
              onTap: () => _copyToClipboard(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareViaWhatsApp(BuildContext context) async {
    final url = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(message)}',
    );
    final ok =
        await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    if (!ok) _snack(context, 'Couldn\'t open WhatsApp.');
  }

  Future<void> _shareViaSms(BuildContext context) async {
    final url = Uri(scheme: 'sms', queryParameters: {'body': message});
    final ok =
        await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    if (!ok) _snack(context, 'Couldn\'t open Messages.');
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message));
    if (!context.mounted) return;
    Navigator.of(context).pop();
    _snack(context, 'Invite text copied to clipboard.');
  }

  void _snack(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.palette.cardMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.palette.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: tint, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.primaryBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
