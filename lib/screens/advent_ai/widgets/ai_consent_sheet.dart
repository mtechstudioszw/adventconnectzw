import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/cache_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../../theme/app_tokens.dart';

/// "Your messages go to Google Gemini" — asked once, before the first
/// Advent AI message (Apple Guideline 5.1.2(i), Nov 2025: disclose personal
/// data shared with a third-party AI and get explicit permission first).
///
/// The answer is stored per account, on this device. Deliberately NOT a
/// `pref:` key: CacheService.clearUserData() wipes it at sign-out, so the
/// next person to sign in on a shared phone is asked for themselves.
const String _kConsentKey = 'advent_ai_consent_v1';

bool hasAiConsent() => CacheService.readStringStale(_kConsentKey) == 'yes';

/// Returns true when the member has agreed (now or before). Shows the
/// sheet only the first time.
Future<bool> ensureAiConsent(BuildContext context) async {
  if (hasAiConsent()) return true;
  final agreed = await showModalBottomSheet<bool>(
      useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    backgroundColor: context.palette.sheet,
    shape: RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
    builder: (ctx) => const _AiConsentSheet(),
  );
  if (agreed == true) {
    // Not awaited: Hive updates its in-memory copy at once (so
    // hasAiConsent() is already true), and the member shouldn't wait on a
    // disk write before their first message goes.
    unawaited(CacheService.writeString(_kConsentKey, 'yes'));
    return true;
  }
  return false;
}

class _AiConsentSheet extends StatelessWidget {
  const _AiConsentSheet();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: palette.brandBlue),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.text,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xl,
          AppSpace.xl,
          AppSpace.xl,
          AppSpace.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Before you use Advent AI',
              style: AppTextStyles.titleLarge.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            point(
              Icons.cloud_outlined,
              'Advent AI is powered by Google Gemini. The messages you type '
              'here are sent to Google to generate the answers.',
            ),
            point(
              Icons.privacy_tip_outlined,
              "Don't include personal or sensitive details — like your "
              'address, phone number or health information — in your '
              'messages.',
            ),
            point(
              Icons.fact_check_outlined,
              'AI answers can be wrong. Check important things against the '
              'Bible and trusted sources.',
            ),
            point(
              Icons.policy_outlined,
              'Details are in the Privacy Policy (Settings → Privacy policy).',
            ),
            const SizedBox(height: AppSpace.sm),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
              child: const Text('I agree — continue'),
            ),
            const SizedBox(height: AppSpace.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Not now',
                style: TextStyle(color: palette.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
