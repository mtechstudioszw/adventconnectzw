import 'package:flutter/material.dart';

/// A Bible translation the reader can switch to.
///
/// The KJV is BUNDLED (`assets/bible/kjv.json`) and always works offline.
/// Every other translation streams from the Free Use Bible API
/// (bible.helloao.org) and is cached per chapter, so a chapter read once stays
/// readable with no connection.
class BibleTranslation {
  const BibleTranslation({
    required this.id,
    required this.name,
    required this.nativeName,
    required this.languageLabel,
    required this.glyph,
    required this.accent,
    this.isBundled = false,
    this.rtl = false,
    this.coverage = TranslationCoverage.whole,
    this.hasAudio = false,
    this.note,
    this.assetPath,
    this.attribution,
    this.languageEnglish,
  });

  /// The language's English name ("Ndebele", "Swahili"), for search and
  /// grouping in the picker. Null for the curated set, which is pinned.
  final String? languageEnglish;

  /// API translation id, or `kjv` for the bundled asset.
  final String id;

  /// English name shown as the card title.
  final String name;

  /// Name in its own script — the thing that makes the picker feel alive.
  final String nativeName;

  /// e.g. 'English', 'ChiShona', 'Κοινή Ελληνική'.
  final String languageLabel;

  /// A single character in the translation's own script, used as the card's
  /// visual identity (א, Ω, K, S…).
  final String glyph;

  /// Card accent so each translation is distinguishable at a glance.
  final Color accent;

  /// True only for the bundled KJV.
  final bool isBundled;

  /// Right-to-left — Hebrew.
  final bool rtl;

  /// Which testament(s) this translation actually contains. Greek NTs have no
  /// Old Testament; the Hebrew WLC and the Septuagint have no New Testament.
  /// The reader uses this to explain a missing book instead of erroring.
  final TranslationCoverage coverage;

  /// Chapter-level narration is available (BSB only, three narrators).
  final bool hasAudio;

  /// Short line under the name, e.g. licence or provenance.
  final String? note;

  /// A whole translation shipped inside the app (1 Nov 2026: Shona), read
  /// from this asset instead of the network — offline from first launch.
  /// Unlike [isBundled] (the KJV's own path), chapters come back through
  /// BibleTranslationService exactly like a downloaded translation.
  final String? assetPath;

  /// Licence credit shown at the end of every chapter, when required.
  final String? attribution;

  /// Readable with no connection at all.
  bool get isOffline => isBundled || assetPath != null;

  bool get isRemote => !isBundled;

  /// True when [bookIndex] (0-based, Genesis..Revelation) exists here.
  bool hasBook(int bookIndex) {
    // Catalogue translations report their real book list once fetched
    // (BibleCatalog.ensureBooks) — exact for partial Bibles too.
    final known = BibleTranslations._books[id];
    if (known != null) {
      final code = BibleTranslations.codeFor(bookIndex);
      return code != null && known.contains(code);
    }
    return switch (coverage) {
      TranslationCoverage.whole => true,
      TranslationCoverage.oldTestament => bookIndex < 39,
      TranslationCoverage.newTestament => bookIndex >= 39,
    };
  }
}

enum TranslationCoverage { whole, oldTestament, newTestament }

/// The curated set offered in the picker.
///
/// Deliberately NOT the API's full 1,250-translation list — that would be a
/// wall of noise. These are the ones an Adventist in Zimbabwe actually wants:
/// their own language, the classic English, the study languages, and the one
/// with narration.
class BibleTranslations {
  BibleTranslations._();

  static const kjv = BibleTranslation(
    id: 'kjv',
    name: 'King James Version',
    nativeName: 'King James Version',
    languageLabel: 'English',
    glyph: 'K',
    accent: Color(0xFF1565C0),
    isBundled: true,
    note: 'Bundled · always offline',
  );

  static const bsb = BibleTranslation(
    id: 'BSB',
    name: 'Berean Standard Bible',
    nativeName: 'Berean Standard Bible',
    languageLabel: 'English',
    glyph: 'B',
    accent: Color(0xFF2E7D32),
    hasAudio: true,
    note: 'Modern English · narrated audio',
  );

  static const shona = BibleTranslation(
    id: 'sna_bib',
    name: 'Bhaibheri Dzvene',
    nativeName: 'Bhaibheri Dzvene MuChiShona Chanhasi',
    languageLabel: 'ChiShona',
    glyph: 'S',
    accent: Color(0xFFC8A951),
    note: 'In the app · always offline',
    // The whole Shona Bible ships with the app (owner, 2 Nov 2026: "when
    // I switch to Shona it should already be there"). CC BY-SA 4.0 —
    // the credit below is a licence condition, not decoration.
    assetPath: 'assets/bible/sna_bib.json',
    attribution:
        'Bhaibheri Dzvene Rakasununguka MuChiShona Chanhasi 2017 © Biblica, '
        'Inc. Used under the Creative Commons Attribution-ShareAlike 4.0 '
        'licence.',
  );

  static const greekByz = BibleTranslation(
    id: 'grc_byz',
    name: 'Byzantine Greek NT',
    nativeName: 'Ἡ Καινὴ Διαθήκη',
    languageLabel: 'Κοινή Ελληνική',
    glyph: 'Ω',
    accent: Color(0xFF6A1B9A),
    coverage: TranslationCoverage.newTestament,
    note: 'Majority Text · New Testament',
  );

  static const greekSbl = BibleTranslation(
    id: 'grc_sbl',
    name: 'SBL Greek NT',
    nativeName: 'Ἡ Καινὴ Διαθήκη',
    languageLabel: 'Κοινή Ελληνική',
    glyph: 'Σ',
    accent: Color(0xFF4527A0),
    coverage: TranslationCoverage.newTestament,
    note: 'Critical text · New Testament',
  );

  static const greekTr = BibleTranslation(
    id: 'grc_gtr',
    name: 'Textus Receptus',
    nativeName: 'Ἡ Καινὴ Διαθήκη',
    languageLabel: 'Κοινή Ελληνική',
    glyph: 'Τ',
    accent: Color(0xFF283593),
    coverage: TranslationCoverage.newTestament,
    note: 'The text behind the KJV',
  );

  static const septuagint = BibleTranslation(
    id: 'grc_bre',
    name: 'Septuagint (Brenton)',
    nativeName: 'Μετάφρασις τῶν Ἑβδομήκοντα',
    languageLabel: 'Κοινή Ελληνική',
    glyph: 'Λ',
    accent: Color(0xFF00695C),
    coverage: TranslationCoverage.oldTestament,
    note: 'Greek Old Testament',
  );

  static const hebrew = BibleTranslation(
    id: 'heb_wlc',
    name: 'Westminster Leningrad Codex',
    nativeName: 'תַּנַ״ךְ',
    languageLabel: 'עברית',
    glyph: 'א',
    accent: Color(0xFFAD1457),
    rtl: true,
    coverage: TranslationCoverage.oldTestament,
    note: 'Hebrew Old Testament',
  );

  /// Picker order: mother tongue and the familiar English first, study
  /// languages after.
  static const all = <BibleTranslation>[
    kjv,
    shona,
    bsb,
    hebrew,
    greekByz,
    greekSbl,
    greekTr,
    septuagint,
  ];

  /// Every other openly licensed translation, from the online catalogue
  /// (BibleCatalog, 3 Nov 2026 — owner: "add many Bible translations, as
  /// many languages as possible"). Registered at runtime.
  static final Map<String, BibleTranslation> _catalog = {};

  /// Real book lists for catalogue translations (API book codes).
  static final Map<String, Set<String>> _books = {};

  static void registerCatalog(Iterable<BibleTranslation> list) {
    for (final t in list) {
      _catalog[t.id] = t;
    }
  }

  static void registerBooks(String id, Set<String> codes) =>
      _books[id] = codes;

  static Iterable<BibleTranslation> get catalog => _catalog.values;

  static BibleTranslation byId(String id) =>
      all.firstWhere(
        (t) => t.id == id,
        orElse: () => _catalog[id] ?? kjv,
      );

  /// Three-letter API book codes in canonical order, so a bundled-KJV book
  /// index maps straight onto the remote API's book id.
  static const bookCodes = <String>[
    'GEN', 'EXO', 'LEV', 'NUM', 'DEU', 'JOS', 'JDG', 'RUT', '1SA', '2SA',
    '1KI', '2KI', '1CH', '2CH', 'EZR', 'NEH', 'EST', 'JOB', 'PSA', 'PRO',
    'ECC', 'SNG', 'ISA', 'JER', 'LAM', 'EZK', 'DAN', 'HOS', 'JOL', 'AMO',
    'OBA', 'JON', 'MIC', 'NAM', 'HAB', 'ZEP', 'HAG', 'ZEC', 'MAL',
    'MAT', 'MRK', 'LUK', 'JHN', 'ACT', 'ROM', '1CO', '2CO', 'GAL', 'EPH',
    'PHP', 'COL', '1TH', '2TH', '1TI', '2TI', 'TIT', 'PHM', 'HEB', 'JAS',
    '1PE', '2PE', '1JN', '2JN', '3JN', 'JUD', 'REV',
  ];

  /// API book code for a 0-based canonical book index, or null when out of
  /// range.
  static String? codeFor(int bookIndex) =>
      (bookIndex >= 0 && bookIndex < bookCodes.length)
          ? bookCodes[bookIndex]
          : null;
}
