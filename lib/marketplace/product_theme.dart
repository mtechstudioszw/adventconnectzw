import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show Brightness;

import '../models/product_model.dart';
import '../theme/app_colors.dart';
import 'product_image_source.dart';

/// The presentation families a product can fall into. Each is a starting
/// point — the photo itself refines it (see [ProductTheme.resolve]).
enum ProductLook { botanical, editorial, fashion, tech, home, food, general }

/// A category's designed defaults: the surface the photo sits on (light
/// and dark), and an accent for the primary action when the photo doesn't
/// supply a usable one.
class LookPreset {
  const LookPreset({
    required this.stageLight,
    required this.stageDark,
    required this.accentLight,
    required this.accentDark,
  });
  final Color stageLight;
  final Color stageDark;
  final Color accentLight;
  final Color accentDark;
}

const _presets = <ProductLook, LookPreset>{
  // Warm cream and deep botanical green — fresh, natural, calm.
  ProductLook.botanical: LookPreset(
    stageLight: Color(0xFFF3F1EA),
    stageDark: Color(0xFF1A1E1A),
    accentLight: Color(0xFF2F6B45),
    accentDark: Color(0xFF8CC19A),
  ),
  // Paper and ink — books and Bibles read like an editorial page.
  ProductLook.editorial: LookPreset(
    stageLight: Color(0xFFF4EFE6),
    stageDark: Color(0xFF1E1C19),
    accentLight: AppColors.darkNavy,
    accentDark: Color(0xFFE9E1D2),
  ),
  // Neutral, so the garment's own colours lead; near-black action.
  ProductLook.fashion: LookPreset(
    stageLight: Color(0xFFF1F1F1),
    stageDark: Color(0xFF171717),
    accentLight: Color(0xFF151515),
    accentDark: Color(0xFFF2F2F2),
  ),
  // Cool grey and graphite — precise, technical.
  ProductLook.tech: LookPreset(
    stageLight: Color(0xFFEDEFF2),
    stageDark: Color(0xFF14161A),
    accentLight: Color(0xFF23272E),
    accentDark: Color(0xFFE3E6EA),
  ),
  // Warm stone and walnut — homeware and furniture.
  ProductLook.home: LookPreset(
    stageLight: Color(0xFFF1ECE5),
    stageDark: Color(0xFF1D1A16),
    accentLight: Color(0xFF6B4F3A),
    accentDark: Color(0xFFD9C3AE),
  ),
  // Cream and a warm spice tone — appetising, clean.
  ProductLook.food: LookPreset(
    stageLight: Color(0xFFF6F0E4),
    stageDark: Color(0xFF1E1A14),
    accentLight: Color(0xFF9A4A22),
    accentDark: Color(0xFFE7B48F),
  ),
  // The app's own look when nothing more specific fits.
  ProductLook.general: LookPreset(
    stageLight: Color(0xFFEFF2F6),
    stageDark: Color(0xFF141A23),
    accentLight: AppColors.primaryBlue,
    accentDark: Color(0xFF7FB0F0),
  ),
};

/// How a product is presented: the surface its photo sits on, the accent
/// for its primary action, and whether the photo blends into the surface
/// (a plain studio background) or sits framed on it (a busy photo).
///
/// Built from the product's own photo first, then its category, then the
/// app default — never random, and always legible: the accent is darkened
/// (or lightened, in dark mode) until its label passes WCAG 4.5:1.
class ProductTheme {
  const ProductTheme({
    required this.look,
    required this.stageLight,
    required this.stageDark,
    required this.accentLight,
    required this.accentDark,
    required this.seamless,
    this.fromPhoto = false,
  });

  final ProductLook look;
  final Color stageLight;
  final Color stageDark;
  final Color accentLight;
  final Color accentDark;

  /// The photo has a plain background, so the stage takes that exact
  /// colour and the product floats on one continuous surface. When false
  /// the photo is shown framed, with its own background, on the stage.
  final bool seamless;

  /// The photo informed this theme (otherwise it's the category preset).
  final bool fromPhoto;

  Color stage(Brightness b) => seamless
      ? stageLight // a white-background photo stays white, even in dark mode
      : (b == Brightness.dark ? stageDark : stageLight);

  Color accent(Brightness b) => b == Brightness.dark ? accentDark : accentLight;

  /// Text/icons on [accent]: whichever of white / near-black reads better.
  Color onAccent(Brightness b) {
    final a = accent(b);
    return contrast(a, AppColors.white) >= contrast(a, const Color(0xFF111111))
        ? AppColors.white
        : const Color(0xFF111111);
  }

  /// Whether foreground placed directly on the stage should be light.
  bool stageIsDark(Brightness b) => luminance(stage(b)) < 0.25;

  // ---------------------------------------------------------------------

  static ProductLook lookFor(Product p) => lookForText(
    [p.category, p.subcategory, p.title].whereType<String>().join(' '),
  );

  /// A look from free text — product category/title, or a shop's
  /// category and name.
  static ProductLook lookForText(String raw) {
    final text = raw.toLowerCase();
    bool has(List<String> words) => words.any(text.contains);
    if (has([
      'book',
      'bible',
      'hymnal',
      'devotional',
      'theology',
      'sabbath school',
    ])) {
      return ProductLook.editorial;
    }
    if (has([
      'health',
      'wellness',
      'herbal',
      'capsule',
      'tea',
      'natural',
      'remed',
      'supplement',
      'oil',
    ])) {
      return ProductLook.botanical;
    }
    if (has([
      'cloth',
      'suit',
      'dress',
      'shoe',
      'uniform',
      'shirt',
      'fashion',
      'bag',
      'jewel',
      'watch',
    ])) {
      return ProductLook.fashion;
    }
    if (has([
      'electronic',
      'phone',
      'laptop',
      'computer',
      'speaker',
      'tv',
      'camera',
      'tablet',
      'charger',
    ])) {
      return ProductLook.tech;
    }
    if (has([
      'furniture',
      'sofa',
      'chair',
      'table',
      'bed',
      'home',
      'kitchen',
      'decor',
    ])) {
      return ProductLook.home;
    }
    if (has([
      'food',
      'catering',
      'bake',
      'bread',
      'cake',
      'grocer',
      'fruit',
      'veg',
      'honey',
    ])) {
      return ProductLook.food;
    }
    return ProductLook.general;
  }

  /// The category's designed defaults — what shows on first paint, before
  /// (or instead of) the photo analysis.
  static ProductTheme preset(ProductLook look) {
    final p = _presets[look]!;
    return ProductTheme(
      look: look,
      stageLight: p.stageLight,
      stageDark: p.stageDark,
      accentLight: p.accentLight,
      accentDark: p.accentDark,
      seamless: false,
    );
  }

  /// Reads RGBA [pixels] (a small square sample of the photo).
  ///
  /// 1. The outer ring decides the stage: a plain ring (low spread) is a
  ///    studio background — use its colour so the photo blends. Otherwise
  ///    keep the category surface, tinted a touch toward the photo.
  /// 2. The centre decides the accent: the strongest saturated hue, by
  ///    saturation-weighted vote, ignoring the ring so a coloured backdrop
  ///    can't masquerade as the product.
  /// 3. Any hue may become the accent — green and pink included (owner,
  ///    28 Oct 2026: adaptive colour follows the product). Legibility is
  ///    still enforced.
  static ProductTheme fromPixels(
    Uint8List pixels,
    ProductLook look, {
    int size = 48,
  }) {
    final base = preset(look);
    if (pixels.length < size * size * 4) return base;

    Color px(int x, int y) {
      final i = (y * size + x) * 4;
      return Color.fromARGB(255, pixels[i], pixels[i + 1], pixels[i + 2]);
    }

    // --- 1. ring ---
    const ring = 3;
    final edge = <Color>[];
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (x < ring || y < ring || x >= size - ring || y >= size - ring) {
          edge.add(px(x, y));
        }
      }
    }
    double ch(Color c, int k) =>
        (k == 0
            ? c.r
            : k == 1
            ? c.g
            : c.b) *
        255;
    final mean = [
      for (var k = 0; k < 3; k++)
        edge.map((c) => ch(c, k)).reduce((a, b) => a + b) / edge.length,
    ];
    var spread = 0.0;
    for (final c in edge) {
      for (var k = 0; k < 3; k++) {
        spread += (ch(c, k) - mean[k]).abs();
      }
    }
    spread /= edge.length * 3;
    final edgeColor = Color.fromARGB(
      255,
      mean[0].round(),
      mean[1].round(),
      mean[2].round(),
    );
    final seamless = spread < 9;

    // --- 2. centre accent ---
    final weights = List<double>.filled(12, 0);
    final hueSum = List<double>.filled(12, 0);
    final satSum = List<double>.filled(12, 0);
    var counted = 0;
    var colourful = 0.0;
    for (var y = ring; y < size - ring; y++) {
      for (var x = ring; x < size - ring; x++) {
        final c = px(x, y);
        // Skip pixels that are just the background showing through.
        if (seamless && _distance(c, edgeColor) < 18) continue;
        counted++;
        final hsl = HSLColor.fromColor(c);
        if (hsl.lightness < 0.10 ||
            hsl.lightness > 0.94 ||
            hsl.saturation < 0.22) {
          continue;
        }
        final w = hsl.saturation * (1 - (hsl.lightness - 0.5).abs());
        final b = (hsl.hue / 30).floor() % 12;
        weights[b] += w;
        hueSum[b] += hsl.hue * w;
        satSum[b] += hsl.saturation * w;
        colourful += w;
      }
    }

    Color? accentLight;
    Color? accentDark;
    if (counted > 0 && colourful / counted > 0.05) {
      var best = 0;
      for (var b = 1; b < 12; b++) {
        if (weights[b] > weights[best]) best = b;
      }
      final hue = hueSum[best] / weights[best];
      final sat = (satSum[best] / weights[best]).clamp(0.40, 0.70);
      {
        accentLight = _readableOn(
          HSLColor.fromAHSL(1, hue, sat, 0.42),
          dark: false,
        );
        accentDark = _readableOn(
          HSLColor.fromAHSL(1, hue, sat * 0.85, 0.70),
          dark: true,
        );
      }
    }

    // --- stage ---
    Color stageLight;
    Color stageDark;
    if (seamless) {
      stageLight = edgeColor;
      stageDark = edgeColor;
    } else {
      // Category surface leaning 10% toward the photo's hue.
      final hint = accentLight ?? base.accentLight;
      stageLight = Color.lerp(base.stageLight, hint, 0.06)!;
      stageDark = Color.lerp(base.stageDark, hint, 0.10)!;
    }

    return ProductTheme(
      look: look,
      stageLight: stageLight,
      stageDark: stageDark,
      accentLight: accentLight ?? base.accentLight,
      accentDark: accentDark ?? base.accentDark,
      seamless: seamless,
      fromPhoto: true,
    );
  }

  // ----- cache + async resolve -------------------------------------------

  static final Map<String, ProductTheme> _cache = {};

  /// The theme for [p], analysed from its first photo once and cached.
  /// Callers paint [preset] first and animate to this, so analysis never
  /// blocks the first frame.
  static Future<ProductTheme> resolve(Product p) async {
    final look = lookFor(p);
    final url = p.firstImage;
    if (url.isEmpty) return preset(look);
    final key = '$url|${look.name}';
    final hit = _cache[key];
    if (hit != null) return hit;
    final pixels = await ProductImageSource.samplePixels(url);
    final theme = pixels == null ? preset(look) : fromPixels(pixels, look);
    _cache[key] = theme;
    return theme;
  }

  static ProductTheme? cached(Product p) =>
      _cache['${p.firstImage}|${lookFor(p).name}'];

  /// The same analysis for any image — a shop's logo or cover.
  static Future<ProductTheme> resolveImage(
    String? url,
    ProductLook look,
  ) async {
    final u = (url ?? '').trim();
    if (u.isEmpty) return preset(look);
    final key = '$u|${look.name}';
    final hit = _cache[key];
    if (hit != null) return hit;
    final pixels = await ProductImageSource.samplePixels(u);
    final theme = pixels == null ? preset(look) : fromPixels(pixels, look);
    _cache[key] = theme;
    return theme;
  }

  static ProductTheme? cachedImage(String? url, ProductLook look) =>
      _cache['${(url ?? '').trim()}|${look.name}'];

  // ----- colour maths ----------------------------------------------------

  static double luminance(Color c) => c.computeLuminance();

  /// WCAG contrast ratio.
  static double contrast(Color a, Color b) {
    final la = luminance(a), lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  static double _distance(Color a, Color b) =>
      ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) * 255 / 3;

  /// Darken (light mode, white label) or lighten (dark mode, dark label)
  /// until the label passes 4.5:1.
  static Color _readableOn(HSLColor c, {required bool dark}) {
    var hsl = c;
    final label = dark ? const Color(0xFF111111) : AppColors.white;
    for (var i = 0; i < 40; i++) {
      if (contrast(hsl.toColor(), label) >= 4.5) break;
      hsl = hsl.withLightness(
        (hsl.lightness + (dark ? 0.02 : -0.02)).clamp(0.05, 0.95),
      );
    }
    return hsl.toColor();
  }
}
