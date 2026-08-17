// Founder rule, restated 18 Aug 2026: **the chat tab gets no ads, and
// neither does anything else to do with messaging.**
//
// This has always been the intent — Advent Chat uses a plain Scaffold with
// MainBottomNav rather than MainScaffold, so it never picked up the banner
// that MainScaffold adds by default. But that is an accident of how the
// screen was written, not something the code says out loud: MainScaffold's
// `showAd` defaults to TRUE, so anyone converting the inbox to MainScaffold
// for consistency would put ads in Advent Chat without noticing.
//
// A widget test can't cover this (the messaging screens need Supabase), and
// the analyzer has no opinion about it. Reading the source is the check
// that actually matches the rule: no messaging screen may import an ad
// widget, and /messages must stay on the full-screen blocklist.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/ads/resume_ad_manager.dart';

/// Everything under here is Advent Chat: the inbox, conversations, groups,
/// message requests, starred messages, chat privacy and the image preview.
const _messagingDir = 'lib/screens/messaging';

/// Any of these appearing in a messaging screen means an ad got in.
const _adMarkers = <String>[
  'widgets/ads/',
  'services/ads/',
  'AdBanner',
  'FeedAdCard',
  'InterstitialAdManager',
  'RewardedAdManager',
  'AdsService',
];

void main() {
  test('no messaging screen imports or renders an ad', () {
    final dir = Directory(_messagingDir);
    expect(dir.existsSync(), isTrue,
        reason: 'test must be run from the package root');

    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty, reason: 'the messaging screens went missing');

    final offenders = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final marker in _adMarkers) {
        if (source.contains(marker)) {
          offenders.add('${file.path}: $marker');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'Advent Chat must carry no ads of any kind — founder rule');
  });

  test('the messaging routes stay on the full-screen ad blocklist', () {
    // A full-screen ad on resume is the most intrusive placement there is,
    // and landing on it over a conversation is the worst version of that.
    expect(ResumeAdManager.blockedPrefixes, contains('/messages'));
    expect(ResumeAdManager.allowedOn('/messages'), isFalse);
    expect(ResumeAdManager.allowedOn('/messages/42'), isFalse);
    // Prayer is the same class of rule.
    expect(ResumeAdManager.allowedOn('/prayer'), isFalse);
    // The home feed is where the revenue is supposed to be, so it must
    // still be allowed — a blocklist that blocks everything is just "off".
    expect(ResumeAdManager.allowedOn('/home'), isTrue);
  });
}
