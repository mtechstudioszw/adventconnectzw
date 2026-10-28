// Soft profile glow (owner-approved 28 Oct 2026): the colour comes from
// the photo, but never a banned hue and never from a grey photo.

import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/utils/photo_tint.dart';

Uint8List _fill(Color c, {int n = 64, Color? other, int otherCount = 0}) {
  final b = Uint8List(n * 4);
  for (var i = 0; i < n; i++) {
    final px = i < otherCount ? other! : c;
    b[i * 4] = (px.r * 255).round();
    b[i * 4 + 1] = (px.g * 255).round();
    b[i * 4 + 2] = (px.b * 255).round();
    b[i * 4 + 3] = 255;
  }
  return b;
}

void main() {
  test('a blue photo gives a calm blue', () {
    final c = PhotoTint.fromPixels(_fill(const Color(0xFF1E5AA8)))!;
    final hsl = HSLColor.fromColor(c);
    expect(hsl.hue, inInclusiveRange(200, 225));
    expect(hsl.saturation, closeTo(0.55, 0.02));
    expect(hsl.lightness, closeTo(0.52, 0.02));
  });

  test('green and pink photos give no glow (palette bans them)', () {
    expect(PhotoTint.fromPixels(_fill(const Color(0xFF2E9D3A))), isNull);
    expect(PhotoTint.fromPixels(_fill(const Color(0xFFE85AA8))), isNull);
  });

  test('grey, black and white photos give no glow', () {
    expect(PhotoTint.fromPixels(_fill(const Color(0xFF808080))), isNull);
    expect(PhotoTint.fromPixels(_fill(const Color(0xFF050505))), isNull);
    expect(PhotoTint.fromPixels(_fill(const Color(0xFFFAFAFA))), isNull);
  });

  test('the dominant colour wins over a smaller one', () {
    final c = PhotoTint.fromPixels(
      _fill(
        const Color(0xFFD9822B), // warm orange, 48 px
        other: const Color(0xFF1E5AA8), // blue, 16 px
        otherCount: 16,
      ),
    )!;
    expect(HSLColor.fromColor(c).hue, inInclusiveRange(20, 40));
  });
}
