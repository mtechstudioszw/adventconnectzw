// Storefront redesign: same action language as the product page (Chat +
// one accent pill), the contact sheet offers every real route, the owner
// gets a preview without buyer actions, and "Other" isn't shown as if it
// were a category.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/seller/seller_profile_screen.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

import 'helpers/fake_supabase.dart';

Map<String, Object?> _seller({String? whatsapp, String phone = ''}) => {
  'id': 11,
  'auth_user_id': 'shop-owner',
  'business_name': 'Dorcas Sewing',
  'category': 'other',
  'city': 'Harare',
  'status': 'approved',
  'is_active': true,
  'phone': phone,
  'whatsapp': whatsapp,
  'offers_delivery': false,
  'payment_methods': 'EcoCash',
  'observes_sabbath': true,
};

Future<void> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(390, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: const SellerProfileScreen(authUserId: 'shop-owner'),
    ),
  );
  await _settle(t);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() => initFakeSupabase());

  testWidgets('buyer: accent pill + Chat sheet with every route', (t) async {
    await signInFake('buyer');
    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/sellers')) {
        return [_seller(whatsapp: '+263771234567', phone: '+263771234567')];
      }
      return null;
    });
    await _pump(t);
    expect(find.text('WhatsApp the shop'), findsOneWidget);
    expect(find.text('Collection only'), findsOneWidget);
    expect(find.text('Keeps the Sabbath'), findsOneWidget);
    // "Other" is not presented as a category.
    expect(find.textContaining('Other'), findsNothing);
    await t.tap(find.text('Chat'));
    await _settle(t);
    expect(find.text('Message in the app'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('no number: the pill messages in the app', (t) async {
    await signInFake('buyer');
    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/sellers')) return [_seller()];
      return null;
    });
    await _pump(t);
    expect(find.text('Message the shop'), findsOneWidget);
    expect(find.text('WhatsApp the shop'), findsNothing);
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('owner: preview, no buyer action bar', (t) async {
    await signInFake('shop-owner');
    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/sellers')) {
        return [_seller(whatsapp: '+263771234567')];
      }
      return null;
    });
    await _pump(t);
    expect(find.text('WhatsApp the shop'), findsNothing);
    expect(find.text('Chat'), findsNothing);
    expect(find.text('Report this shop'), findsNothing);
    await t.pump(const Duration(seconds: 30));
  });
}
