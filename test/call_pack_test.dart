import 'package:advent_connect_zw/models/call_model.dart';
import 'package:advent_connect_zw/services/billing/boost_catalog.dart';
import 'package:advent_connect_zw/services/billing/call_pack_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pack SKUs match the server (verify-boost PACKS / patch 305)', () {
    expect(CallPack.small.sku, 'call_minutes_300');
    expect(CallPack.small.minutes, 300);
    expect(CallPack.large.sku, 'call_minutes_1200');
    expect(CallPack.large.minutes, 1200);
    expect(CallPack.validDays, 30);
  });

  test('packs and boosts never claim each other\'s purchases', () {
    for (final p in CallPack.values) {
      expect(BoostKind.isBoostSku(p.sku), isFalse);
    }
    for (final b in BoostKind.values) {
      expect(CallPack.isPackSku(b.sku), isFalse);
    }
    expect(CallPack.isPackSku('premium_subscription'), isFalse);
  });

  test('usage reads the pack balance, and stays valid without it', () {
    final withPack = CallUsage.fromJson({
      'today_seconds': 7200,
      'month_seconds': 7200,
      'daily_limit_seconds': 25200, // 120 free + 300 pack
      'monthly_limit_seconds': 108000,
      'premium': false,
      'pack_seconds': 18000,
      'pack_expires_at': '2026-12-03T10:00:00Z',
    });
    expect(withPack.packSeconds ~/ 60, 300);
    expect(withPack.packExpiresAt, isNotNull);
    expect(withPack.dailyExhausted, isFalse); // the pack keeps them talking

    final old = CallUsage.fromJson({
      'today_seconds': 7200,
      'daily_limit_seconds': 7200,
    });
    expect(old.packSeconds, 0);
    expect(old.packExpiresAt, isNull);
    expect(old.dailyExhausted, isTrue);
  });
}
