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
  // Get the font family first, then FORCE colour/size/weight on top with
  // copyWith. Passing colour via `textStyle:` into GoogleFonts could get
  // dropped when the resulting style was later merged into a TextField's
  // theme style — which left the status text taking the theme's default
  // colour (dark in light mode → invisible on the colour background). Forcing
  // the colour last guarantees white text in BOTH light and dark.
  final TextStyle f;
  switch (fontKey) {
    case 'archivo':
      f = GoogleFonts.archivoBlack();
    case 'pacifico':
      f = GoogleFonts.pacifico();
    case 'slab':
      f = GoogleFonts.robotoSlab();
    case 'poppins':
    default:
      f = GoogleFonts.poppins();
  }
  return f.copyWith(
    // inherit:false makes this style fully self-contained so the ambient
    // DefaultTextStyle can NEVER merge into it. In dark mode the inherited
    // text colour is already light, so a bleed went unnoticed; in LIGHT mode
    // the inherited colour is dark, which is what turned the status text
    // black ("black spaces" bug). Forcing inherit:false guarantees the white
    // we set below always wins, in both themes, for composer AND viewer.
    inherit: false,
    color: color,
    fontSize: fontSize,
    fontWeight: fontKey == 'pacifico' ? FontWeight.w400 : fontWeight,
    height: 1.25,
    // CRITICAL: GoogleFonts loads the font asynchronously (true even for
    // bundled assets) and sets its OWN fallback to the same not-yet-loaded
    // family — so while it loads there are no glyphs at all and the text
    // renders INVISIBLE (the "blank while typing, fine after posting" bug).
    // Force a guaranteed system fallback so the text is always visible
    // immediately and just upgrades to the chosen font once it's ready.
    fontFamilyFallback: const ['Roboto', 'sans-serif'],
  );
}
