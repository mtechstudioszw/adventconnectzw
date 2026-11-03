import 'dart:io';

import 'package:advent_connect_zw/services/billing/small_products.dart';
import 'package:flutter_test/flutter_test.dart';

/// The $1 products (patch 309) are named in three places that must agree
/// letter for letter, or a member pays and receives nothing: the app, the
/// server function that grants them, and the database patch.
void main() {
  final verifyBoost = File(
    'supabase/functions/verify-boost/index.ts',
  ).readAsStringSync();
  final verifyPurchase = File(
    'supabase/functions/verify-purchase/index.ts',
  ).readAsStringSync();
  final patch = File(
    'database/patch_309_verified_plan_and_ai_pack.sql',
  ).readAsStringSync();

  test('AI pack id and size match verify-boost and the grant function', () {
    expect(
      verifyBoost,
      contains(
        '${SmallProducts.aiPackSku}: { units: ${SmallProducts.aiPackQuestions} }',
      ),
    );
    expect(patch, contains("p_product <> '${SmallProducts.aiPackSku}'"));
    expect(patch, contains('p_units <> ${SmallProducts.aiPackQuestions}'));
  });

  test('Verified plan id matches the database and the receipt', () {
    expect(patch, contains("product_id = '${SmallProducts.verifiedSku}'"));
    expect(
      patch,
      contains("<> '${SmallProducts.verifiedSku}'"),
      reason: 'Premium must be computed WITHOUT the Verified plan',
    );
    expect(verifyPurchase, contains('"${SmallProducts.verifiedSku}"'));
  });

  test('routing recognises exactly these ids', () {
    expect(SmallProducts.isVerifiedSku('verified_monthly'), isTrue);
    expect(SmallProducts.isVerifiedSku('premium_monthly'), isFalse);
    expect(SmallProducts.isAiPackSku('ai_questions_50'), isTrue);
    expect(SmallProducts.isAiPackSku('call_minutes_300'), isFalse);
  });
}
