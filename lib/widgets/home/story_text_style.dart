import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Font options for WhatsApp-style text statuses. The key is persisted on the
/// story (`stories.text_font`) so the viewer renders the SAME font the author
/// picked. Index order matches the composer's font cycler.
const List<String> kStoryFontKeys = ['poppins', 'archivo', 'pacifico', 'slab'];
const List<String> kStoryFontLabels = ['Classic', 'Bold', 'Script', 'Serif'];

/// Build the text style for a story's text, applying the chosen font.
TextStyle storyFontStyle(
  String? fontKey, {
  required Color color,
  required double fontSize,
  FontWeight fontWeight = FontWeight.w700,
}) {
  final base = TextStyle(
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: 1.25,
  );
  switch (fontKey) {
    case 'archivo':
      return GoogleFonts.archivoBlack(
          textStyle: base.copyWith(fontWeight: FontWeight.w900));
    case 'pacifico':
      return GoogleFonts.pacifico(
          textStyle: base.copyWith(fontWeight: FontWeight.w400));
    case 'slab':
      return GoogleFonts.robotoSlab(textStyle: base);
    case 'poppins':
    default:
      return GoogleFonts.poppins(textStyle: base);
  }
}
