// The EGW EPUB parser.
//
// Why the EGW shelf moved off PDF at all: `flutter_pdfview` renders PAGES
// and exposes no text layer, so highlight / copy / share-a-quote and real
// Day/Sepia/Night were impossible, and the reader could only ever "feel
// like a PDF" (founder, 17 Aug). The same books ship as EPUB from the same
// White Estate server, and those carry the two things that make the whole
// feature possible:
//
//   * the CANONICAL printed page numbers, inline as
//     `<span epub:type="pagebreak" title="18">[18]</span>` — without these
//     a shared quote cannot be cited, which is most of the point;
//   * scripture already tagged as
//     `<span class="bible-kjv" title="Colossians 2:3">` — so references can
//     be tappable into the app's own Bible tab with no text-matching guess.
//
// The fixture below is a miniature of the real markup (verified against
// `en_SC.epub`), built in memory so this test needs no checked-in binary.
//
// Verified separately against all 61 seeded books on 17 Aug 2026: 61/61
// parsed, 46.3M chars, 21,676 page anchors, 17,652 scripture refs, no
// failures. Twelve are daily devotionals with no page anchors at all —
// they are organised by DATE, so cite those by date, not page.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/egw_book_model.dart';
import 'package:advent_connect_zw/services/egw_epub_parser.dart';

const _container = '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf"
 media-type="application/oebps-package+xml"/></rootfiles></container>
''';

const _opf = '''
<?xml version="1.0" encoding="utf-8" ?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>Steps to Christ</dc:title>
<dc:creator id="creator">Ellen G. White</dc:creator>
</metadata>
<manifest>
<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
<item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>
<item id="content01" href="content01.xhtml" media-type="application/xhtml+xml"/>
<item id="content02" href="content02.xhtml" media-type="application/xhtml+xml"/>
</manifest>
<spine>
<itemref idref="cover"/>
<itemref idref="content01"/>
<itemref idref="content02"/>
</spine></package>
''';

const _ncx = '''
<?xml version="1.0" encoding="utf-8" ?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
<navMap>
<navPoint id="content02" class="chapter" playOrder="3">
<navLabel><text>NCX fallback label</text></navLabel>
<content src="content02.xhtml"/>
</navPoint>
</navMap></ncx>
''';

/// Mirrors the real chapter markup, including the pretty-printed newlines
/// that must not survive into the rendered text.
const _chapter1 = '''
<?xml version="1.0" encoding="utf-8" ?>
<html xmlns="http://www.w3.org/1999/xhtml"
      xmlns:epub="http://www.idpf.org/2007/ops" dir="ltr">
<head><title>Steps to Christ</title></head>
<body>
<div class="chapter" id="content01">
	<h2 class="chapterhead">Chapter 2—The Sinner's Need of Christ</h2>
	<p class="standard-indented">Man was originally endowed
	with noble powers.</p>
	<p class="standard-indented">He held communion with Him
	<span class="bible-kjv" title="Colossians 2:3">Colossians 2:3</span>.
	His motives would be alien to
	<span epub:type="pagebreak" id="p18" title="18" class="pagebreak">[18]</span>
	those that actuate the sinless dwellers there.</p>
	<p class="poem-noindent">A poem line</p>
	<blockquote><p>A quoted passage.</p></blockquote>
	<p class="standard-indented">Text with <em>emphasis</em> inside.</p>
</div>
</body></html>
''';

/// No heading — the parser must fall back to the NCX label.
const _chapter2 = '''
<?xml version="1.0" encoding="utf-8" ?>
<html xmlns="http://www.w3.org/1999/xhtml"><body>
<div class="chapter"><p class="standard-indented">Body only.</p></div>
</body></html>
''';

const _cover = '''
<?xml version="1.0" encoding="utf-8" ?>
<html xmlns="http://www.w3.org/1999/xhtml"><body>
<p>COVER ART PLACEHOLDER</p></body></html>
''';

Uint8List _epub({Map<String, String>? override}) {
  final files = <String, String>{
    'META-INF/container.xml': _container,
    'OEBPS/content.opf': _opf,
    'OEBPS/toc.ncx': _ncx,
    'OEBPS/cover.xhtml': _cover,
    'OEBPS/content01.xhtml': _chapter1,
    'OEBPS/content02.xhtml': _chapter2,
    ...?override,
  };
  final archive = Archive();
  files.forEach((name, body) {
    final bytes = utf8.encode(body);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

EgwBook _parse() => EgwEpubParser.parse(_epub());

void main() {
  group('metadata', () {
    test('reads dc: title and creator despite the namespace prefix', () {
      // `findAllElements('title')` misses `<dc:title>` — the parser has to
      // match on local name, and this is the regression guard for that.
      final book = _parse();
      expect(book.title, 'Steps to Christ');
      expect(book.author, 'Ellen G. White');
    });
  });

  group('structure', () {
    test('skips front matter, keeps real chapters', () {
      final book = _parse();
      expect(book.chapters.length, 2);
      expect(book.chapters.map((c) => c.id), ['content01', 'content02']);
      // The cover is navigation, not reading.
      expect(
        book.chapters.expand((c) => c.blocks).map((b) => b.text).join(),
        isNot(contains('COVER ART')),
      );
    });

    test('prefers the in-document heading over the NCX label', () {
      expect(_parse().chapters.first.title, contains("Sinner's Need"));
    });

    test('falls back to the NCX label when there is no heading', () {
      expect(_parse().chapters[1].title, 'NCX fallback label');
    });

    test('classifies blocks', () {
      final kinds = _parse().chapters.first.blocks.map((b) => b.kind);
      expect(kinds, contains(EgwBlockKind.heading));
      expect(kinds, contains(EgwBlockKind.paragraph));
      expect(kinds, contains(EgwBlockKind.verse));
      expect(kinds, contains(EgwBlockKind.blockquote));
    });

    test('does not emit a quoted paragraph twice', () {
      // <p> nested in <blockquote> must be claimed by the blockquote only.
      final text = _parse()
          .chapters
          .first
          .blocks
          .map((b) => b.text)
          .join('|');
      expect('A quoted passage.'.allMatches(text).length, 1);
    });
  });

  group('page anchors — the reason EPUB was chosen', () {
    test('captures the printed page number', () {
      final pages = _parse()
          .chapters
          .expand((c) => c.blocks)
          .expand((b) => b.spans)
          .map((s) => s.page)
          .whereType<int>();
      expect(pages, contains(18));
    });

    test('drops the visible "[18]" from the reading text', () {
      // Leaving the print artefact inline is half of why the current
      // reader feels like a scan.
      final text = _parse()
          .chapters
          .expand((c) => c.blocks)
          .map((b) => b.text)
          .join(' ');
      expect(text, isNot(contains('[18]')));
      expect(text, contains('those that actuate'));
    });

    test('exposes a chapter start page for citation', () {
      expect(_parse().chapters.first.startPage, 18);
    });
  });

  group('scripture', () {
    test('keeps the reference the source tagged', () {
      final refs = _parse()
          .chapters
          .expand((c) => c.blocks)
          .expand((b) => b.spans)
          .map((s) => s.scriptureRef)
          .whereType<String>();
      expect(refs, contains('Colossians 2:3'));
    });
  });

  group('text quality', () {
    test('collapses source line-wrapping', () {
      // The XHTML is pretty-printed; raw text nodes carry newlines and tabs
      // that would otherwise open gaps mid-sentence.
      final para = _parse()
          .chapters
          .first
          .blocks
          .firstWhere((b) => b.text.contains('noble powers'));
      expect(para.text.trim(), 'Man was originally endowed with noble powers.');
      expect(para.text, isNot(contains('\n')));
      expect(para.text, isNot(contains('\t')));
    });

    test('marks italics without splitting the sentence apart', () {
      final block = _parse()
          .chapters
          .first
          .blocks
          .firstWhere((b) => b.text.contains('emphasis'));
      expect(block.text, 'Text with emphasis inside.');
      expect(block.spans.where((s) => s.italic).map((s) => s.text),
          contains('emphasis'));
      // Runs that render alike are merged, so a paragraph is a handful of
      // spans rather than one per text node.
      expect(block.spans.length, 3);
    });
  });

  group('robustness', () {
    test('a non-EPUB throws FormatException so callers can fall back', () {
      expect(
        () => EgwEpubParser.parse(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<FormatException>()),
      );
    });

    test('survives a missing NCX', () {
      final bytes = _epub(override: {'OEBPS/toc.ncx': '<not-xml'});
      final book = EgwEpubParser.parse(bytes);
      expect(book.chapters, isNotEmpty);
      // Heading still wins; the label-less chapter degrades to its id.
      expect(book.chapters[1].title, 'content02');
    });
  });
}
