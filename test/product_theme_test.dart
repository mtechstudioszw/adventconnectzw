// The adaptive product theme engine (lib/marketplace/product_theme.dart):
// photos with plain backgrounds blend into the stage, the accent comes from
// the product (never the backdrop), every accent passes WCAG 4.5:1 for its
// label, and reds/pinks fall back to the category accent.

import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/marketplace/product_theme.dart';
import 'package:advent_connect_zw/models/product_model.dart';

const _n = 48;

/// A [_n]×[_n] RGBA image: [bg] everywhere, [fg] in the centre square.
Uint8List _img(Color bg, Color? fg, {bool noisyEdge = false}) {
  final b = Uint8List(_n * _n * 4);
  for (var y = 0; y < _n; y++) {
    for (var x = 0; x < _n; x++) {
      var c = bg;
      if (fg != null && x > 14 && x < 34 && y > 10 && y < 38) c = fg;
      if (noisyEdge && (x + y) % 2 == 0) {
        c = Color.fromARGB(255, (c.r * 255).round() ~/ 2, 40, 20);
      }
      final i = (y * _n + x) * 4;
      b[i] = (c.r * 255).round();
      b[i + 1] = (c.g * 255).round();
      b[i + 2] = (c.b * 255).round();
      b[i + 3] = 255;
    }
  }
  return b;
}

Product _product(String category, {String? sub, String title = 'Item'}) =>
    Product(
      id: '1',
      sellerId: 's',
      sellerName: 'Shop',
      title: title,
      price: 10,
      imageUrls: const [],
      createdAt: DateTime(2026),
      category: category,
      subcategory: sub,
    );

void main() {
  test('white studio photo → seamless white stage, product-green accent', () {
    final t = ProductTheme.fromPixels(
      _img(const Color(0xFFFAFAF8), const Color(0xFF3A7D44)),
      ProductLook.botanical,
    );
    expect(t.seamless, isTrue);
    expect(t.stageLight, const Color(0xFFFAFAF8));
    final hue = HSLColor.fromColor(t.accentLight).hue;
    expect(hue, inInclusiveRange(90, 160));
    expect(
      ProductTheme.contrast(t.accentLight, t.onAccent(Brightness.light)),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('a busy background is framed, not blended', () {
    final t = ProductTheme.fromPixels(
      _img(const Color(0xFF8A6040), const Color(0xFF1C2E5C), noisyEdge: true),
      ProductLook.editorial,
    );
    expect(t.seamless, isFalse);
  });

  test('a coloured backdrop does not become the accent', () {
    // Orange wall, grey product: no product colour → category accent.
    final t = ProductTheme.fromPixels(
      _img(const Color(0xFFE07A1F), const Color(0xFF8A8A8A)),
      ProductLook.tech,
    );
    expect(t.accentLight, ProductTheme.preset(ProductLook.tech).accentLight);
  });

  test('red and pink products fall back to the category accent', () {
    for (final c in [const Color(0xFFD2282D), const Color(0xFFE85AA8)]) {
      final t = ProductTheme.fromPixels(
        _img(const Color(0xFFECECEE), c),
        ProductLook.fashion,
      );
      expect(
        t.accentLight,
        ProductTheme.preset(ProductLook.fashion).accentLight,
      );
    }
  });

  test('every preset accent is legible in both themes', () {
    for (final look in ProductLook.values) {
      final t = ProductTheme.preset(look);
      for (final b in Brightness.values) {
        expect(
          ProductTheme.contrast(t.accent(b), t.onAccent(b)),
          greaterThanOrEqualTo(4.5),
          reason: '$look $b',
        );
      }
    }
  });

  test('photo-derived accents are legible for many hues', () {
    for (var hue = 20.0; hue < 290; hue += 15) {
      final fg = HSLColor.fromAHSL(1, hue, 0.7, 0.5).toColor();
      final t = ProductTheme.fromPixels(
        _img(const Color(0xFFFFFFFF), fg),
        ProductLook.general,
      );
      for (final b in Brightness.values) {
        expect(
          ProductTheme.contrast(t.accent(b), t.onAccent(b)),
          greaterThanOrEqualTo(4.5),
          reason: 'hue $hue $b',
        );
      }
    }
  });

  test('categories map to looks', () {
    expect(ProductTheme.lookFor(_product('books')), ProductLook.editorial);
    expect(
      ProductTheme.lookFor(_product('other', sub: 'Health and Wellness')),
      ProductLook.botanical,
    );
    expect(ProductTheme.lookFor(_product('clothing')), ProductLook.fashion);
    expect(ProductTheme.lookFor(_product('electronics')), ProductLook.tech);
    expect(ProductTheme.lookFor(_product('furniture')), ProductLook.home);
    expect(ProductTheme.lookFor(_product('food')), ProductLook.food);
    expect(ProductTheme.lookFor(_product('other')), ProductLook.general);
  });
}
