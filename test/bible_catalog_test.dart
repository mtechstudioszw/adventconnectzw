import 'dart:convert';
import 'dart:io';

import 'package:advent_connect_zw/models/bible_translation.dart';
import 'package:advent_connect_zw/services/bible_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _t(
  String id,
  String lang, {
  String commercial = 'allowed',
  String attribution = 'required',
  int books = 66,
  bool license = true,
}) => {
  'id': id,
  'name': '$id native',
  'englishName': '$id english',
  'language': lang,
  'languageName': lang,
  'languageEnglishName': lang,
  'textDirection': 'ltr',
  'numberOfBooks': books,
  'licenseUrl': 'https://example.org/$id',
  if (license)
    'license': {'commercialUse': commercial, 'attribution': attribution},
};

void main() {
  test('keeps only commercial-use, NT-or-more, non-duplicate Bibles', () {
    final list = BibleCatalog.parse({
      'translations': [
        _t('nde_bib', 'North Ndebele'),
        _t('nc_bib', 'Xhosa', commercial: 'not-allowed'),
        _t('one_book', 'Zulu', books: 1),
        _t('nolicence', 'Venda', license: false),
        _t('sna_bib', 'Shona'), // already bundled
        _t('swh_nt', 'Swahili', books: 27, attribution: 'not-required'),
      ],
    });
    expect(list.map((t) => t.id), ['nde_bib', 'swh_nt']);
    final nt = list.last;
    expect(nt.coverage, TranslationCoverage.newTestament);
    expect(nt.hasBook(0), isFalse); // Genesis
    expect(nt.hasBook(42), isTrue); // John
    expect(nt.attribution, isNull);
    expect(list.first.attribution, contains('open licence'));
  });

  test('registered catalogue ids resolve through byId', () {
    final list = BibleCatalog.parse({
      'translations': [_t('nya_bib', 'Nyanja')],
    });
    BibleTranslations.registerCatalog(list);
    expect(BibleTranslations.byId('nya_bib').languageEnglish, 'Nyanja');
    expect(BibleTranslations.byId('missing').id, BibleTranslations.kjv.id);
  });

  test('a real book list overrides coverage (partial Bibles)', () {
    final t = BibleCatalog.parse({
      'translations': [_t('part_bib', 'Tonga', books: 30)],
    }).single;
    BibleTranslations.registerBooks('part_bib', {'MAT', 'JHN', 'RUT'});
    expect(t.hasBook(7), isTrue); // Ruth
    expect(t.hasBook(41), isFalse); // Luke
  });

  test('the live catalogue snapshot yields hundreds of languages', () {
    final f = File('test/fixtures/bible_catalog_sample.json');
    if (!f.existsSync()) return; // optional fixture
    final list = BibleCatalog.parse(
      jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
    );
    expect(list.length, greaterThan(100));
  });
}
