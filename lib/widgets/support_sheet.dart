import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// App-wide support contacts. Reach the founder for help with any problem.
const String kSupportWhatsApp = '263778092494';
const String kSupportEmail = 'adventconnectzw@gmail.com';

/// Show the "Contact support" bottom sheet — WhatsApp or email. [topic] seeds
/// the message/subject so you can tell where the user came from
/// (e.g. 'Sign-in problem', 'Password reset').
Future<void> showSupportSheet(BuildContext context, {String topic = ''}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _SupportSheet(topic: topic),
  );
}

class _SupportSheet extends StatelessWidget {
  const _SupportSheet({required this.topic});
  final String topic;

  Future<void> _whatsApp() async {
    final msg = topic.isEmpty
        ? 'Hi, I need help with Adventist Super App.'
        : 'Hi, I need help with Adventist Super App — $topic.';
    final uri = Uri.parse(
        'https://wa.me/$kSupportWhatsApp?text=${Uri.encodeComponent(msg)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _email() async {
    final subject =
        topic.isEmpty ? 'Adventist Super App — help' : 'Adventist Super App — $topic';
    final uri = Uri.parse(
        'mailto:$kSupportEmail?subject=${Uri.encodeComponent(subject)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
            Text('Contact support',
                style: AppTextStyles.headlineSmall
                    .copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Hit a problem? Reach us and we\'ll help you out.',
              style:
                  AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 18),
            _ContactTile(
              icon: Icons.chat_rounded,
              iconColor: AppColors.successGreen,
              title: 'WhatsApp us',
              subtitle: '+$kSupportWhatsApp',
              onTap: () {
                Navigator.pop(context);
                _whatsApp();
              },
            ),
            const SizedBox(height: 10),
            _ContactTile(
              icon: Icons.email_outlined,
              iconColor: AppColors.primaryBlue,
              title: 'Email us',
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

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppTextStyles.titleSmall
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: palette.textMuted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
