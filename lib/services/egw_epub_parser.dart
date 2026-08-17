import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/egw_book_model.dart';

/// Turns a White Estate EPUB into an [EgwBook] the reader can lay out with
/// the app's own text widgets.
///
/// ## Why this exists at all
///
/// The EGW shelf was PDFs, and `flutter_pdfview` renders PAGES with no text
/// layer — so highlight, copy, share-a-quote and real Day/Sepia/Night were
/// not merely hard, they were impossible, and the reader could only ever
/// "feel like a PDF". The same books ship as EPUB from the same server
/// (`media2.egwwritings.org/epub/en_<CODE>.epub`), and those carry:
///
///   * clean semantic XHTML, one file per chapter;
///   * the CANONICAL printed page numbers inline, as
///     `<span epub:type="pagebreak" title="18">[18]</span>`;
///   * scripture already tagged, as
///     `<span class="bible-kjv" title="Colossians 2:3">`.
///
/// The page numbers are the reason a quote card can honestly say
/// "Steps to Christ, p. 18"; the scripture tags are why references can be
/// tappable into the app's own Bible tab without any text-matching guesswork.
///
/// ## Parsing rules worth knowing
///
/// * Element names are matched on their LOCAL name. The documents declare
///   several namespaces (`xhtml`, `epub`, `svg`), and matching qualified
///   names silently finds nothing.
/// * The visible `[18]` of a page break is DROPPED. It becomes metadata on
///   the span instead. Leaving it inline is exactly the print artefact that
///   makes a reader feel like a scan.
/// * Front matter (cover, title page, the EPUB's own table of contents) is
///   skipped: it is navigation, and the app has its own.
class EgwEpubParser {
  EgwEpubParser._();

  /// Spine items that are packaging, not reading.
  static const _skipIds = <String>{'cover', 'titlepage', 'toc', 'nav'};

  /// Parses [bytes] of a `.epub` file. Throws [FormatException] if the
  /// archive is not a readable EPUB — callers fall back to the PDF.
  static EgwBook parse(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FormatException('Not a readable EPUB archive: $e');
    }

    final opfPath = _rootfilePath(archive);
    final opf = _xml(archive, opfPath);
    // Hrefs inside the OPF are relative to the OPF's own folder.
    final base = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';

    final title = _metaText(opf, 'title') ?? 'Untitled';
    final author = _metaText(opf, 'creator');

    // id -> href, for resolving the spine.
    final manifest = <String, String>{};
    for (final item in _byLocal(opf, 'item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) manifest[id] = href;
    }

    final tocTitles = _tocTitles(archive, manifest, base);

    final chapters = <EgwChapter>[];
    for (final ref in _byLocal(opf, 'itemref')) {
      final id = ref.getAttribute('idref');
      if (id == null || _skipIds.contains(id)) continue;
      final href = manifest[id];
      if (href == null || !href.toLowerCase().endsWith('.xhtml')) continue;

      final doc = _tryXml(archive, '$base$href');
      if (doc == null) continue;

      final blocks = _blocks(doc);
      if (blocks.isEmpty) continue;

      // Prefer the document's own heading; the NCX label is the fallback,
      // and the spine id the last resort.
      final heading = blocks
          .where((b) => b.kind == EgwBlockKind.heading)
          .map((b) => b.text.trim())
          .where((t) => t.isNotEmpty)
          .firstOrNull;

      chapters.add(EgwChapter(
        id: id,
        title: heading ?? tocTitles[href] ?? id,
        blocks: blocks,
      ));
    }

    return EgwBook(title: title, author: author, chapters: chapters);
  }

  // ---- Container / OPF ------------------------------------------------------

  static String _rootfilePath(Archive archive) {
    final container = _tryXml(archive, 'META-INF/container.xml');
    final path = container == null
        ? null
        : _byLocal(container, 'rootfile').firstOrNull?.getAttribute(
            'full-path',
          );
    if (path != null && path.isNotEmpty) return path;
    // Some builds omit or misname the container; fall back to any .opf.
    final opf = archive.files
        .map((f) => f.name)
        .where((n) => n.toLowerCase().endsWith('.opf'))
        .firstOrNull;
    if (opf == null) throw const FormatException('EPUB has no .opf package');
    return opf;
  }

  /// Dublin Core metadata, matched on local name so the `dc:` prefix is
  /// irrelevant.
  static String? _metaText(XmlDocument opf, String local) {
    final el = _byLocal(opf, local).firstOrNull;
    final text = el?.innerText.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  /// href -> chapter label, from the NCX.
  static Map<String, String> _tocTitles(
    Archive archive,
    Map<String, String> manifest,
    String base,
  ) {
    final ncxHref = manifest.values
        .where((h) => h.toLowerCase().endsWith('.ncx'))
        .firstOrNull;
    if (ncxHref == null) return const {};
    final ncx = _tryXml(archive, '$base$ncxHref');
    if (ncx == null) return const {};

    final out = <String, String>{};
    for (final point in _byLocal(ncx, 'navPoint')) {
      final src = _byLocal(point, 'content').firstOrNull?.getAttribute('src');
      final label = _byLocal(point, 'text').firstOrNull?.innerText.trim();
      if (src == null || label == null || label.isEmpty) continue;
      // Strip any fragment: several points can share one file.
      out.putIfAbsent(src.split('#').first, () => label);
    }
    return out;
  }

  // ---- Chapter body ---------------------------------------------------------

  static const _blockTags = <String>{
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'blockquote',
  };

  static List<EgwBlock> _blocks(XmlDocument doc) {
    final body = _byLocal(doc, 'body').firstOrNull;
    if (body == null) return const [];

    final out = <EgwBlock>[];
    for (final el in body.descendantElements) {
      if (!_blockTags.contains(el.name.local.toLowerCase())) continue;
      // Skip nested blocks — a <p> inside a <blockquote> is emitted by the
      // blockquote pass, and taking both would duplicate the text.
      if (el.ancestorElements.any(
        (a) => _blockTags.contains(a.name.local.toLowerCase()),
      )) {
        continue;
      }
      final spans = _spans(el);
      final block = EgwBlock(kind: _kindOf(el), spans: spans);
      // Keep blocks that carry a page marker even when they have no words:
      // dropping them would lose the page anchor.
      if (block.isBlank && !spans.any((s) => s.page != null)) continue;
      out.add(block);
    }
    return out;
  }

  static EgwBlockKind _kindOf(XmlElement el) {
    final tag = el.name.local.toLowerCase();
    final cls = (el.getAttribute('class') ?? '').toLowerCase();
    if (tag == 'blockquote') return EgwBlockKind.blockquote;
    if (cls.contains('chapterhead') || tag.startsWith('h')) {
      return EgwBlockKind.heading;
    }
    // The EGW books set poetry and signature lines apart from body copy.
    if (cls.contains('poem') || cls.contains('signature')) {
      return EgwBlockKind.verse;
    }
    return EgwBlockKind.paragraph;
  }

  /// Flattens an element's inline content into runs, preserving the two
  /// things the source marks up for us: page anchors and scripture.
  static List<EgwSpan> _spans(XmlElement el, {bool italic = false}) {
    final out = <EgwSpan>[];

    void walk(XmlNode node, bool inItalic) {
      if (node is XmlText || node is XmlCDATA) {
        final t = _squash(node.value ?? '');
        if (t.isNotEmpty) out.add(EgwSpan(text: t, italic: inItalic));
        return;
      }
      if (node is! XmlElement) return;

      final tag = node.name.local.toLowerCase();
      final cls = (node.getAttribute('class') ?? '').toLowerCase();
      final epubType = (node.getAttribute('type') ?? '').toLowerCase();

      // Page anchor. The visible "[18]" is deliberately dropped — it is a
      // print artefact, and keeping it inline is half of why the current
      // reader feels like a scan. The number survives as metadata.
      if (cls.contains('pagebreak') || epubType.contains('pagebreak')) {
        final page = int.tryParse(node.getAttribute('title') ?? '');
        if (page != null) out.add(EgwSpan(text: '', page: page));
        return;
      }

      // Scripture the source already identified for us.
      if (cls.contains('bible')) {
        final text = _squash(node.innerText);
        if (text.isNotEmpty) {
          out.add(EgwSpan(
            text: text,
            scriptureRef: node.getAttribute('title')?.trim() ?? text,
            italic: inItalic,
          ));
        }
        return;
      }

      final nowItalic =
          inItalic || tag == 'em' || tag == 'i' || cls.contains('italic');
      for (final child in node.children) {
        walk(child, nowItalic);
      }
    }

    for (final child in el.children) {
      walk(child, italic);
    }
    return _merge(out);
  }

  /// Collapses source line-wrapping into single spaces. The XHTML is
  /// pretty-printed, so raw text nodes carry tabs and newlines that would
  /// otherwise show up as gaps mid-sentence.
  static String _squash(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ');

  /// Joins adjacent runs that render identically, so a paragraph is a
  /// handful of spans rather than one per text node.
  static List<EgwSpan> _merge(List<EgwSpan> spans) {
    final out = <EgwSpan>[];
    for (final s in spans) {
      final last = out.isEmpty ? null : out.last;
      final mergeable = last != null &&
          last.page == null &&
          s.page == null &&
          last.scriptureRef == null &&
          s.scriptureRef == null &&
          last.italic == s.italic;
      if (mergeable) {
        out[out.length - 1] = EgwSpan(
          text: '${last.text}${s.text}',
          italic: last.italic,
        );
      } else {
        out.add(s);
      }
    }
    return out;
  }

  // ---- XML helpers ----------------------------------------------------------

  /// Descendant elements matched on LOCAL name, ignoring namespace prefixes.
  /// `findAllElements('title')` misses `<dc:title>`; this does not.
  static Iterable<XmlElement> _byLocal(XmlNode root, String local) {
    final want = local.toLowerCase();
    return root.descendantElements.where(
      (e) => e.name.local.toLowerCase() == want,
    );
  }

  static XmlDocument _xml(Archive archive, String path) {
    final doc = _tryXml(archive, path);
    if (doc == null) throw FormatException('EPUB is missing $path');
    return doc;
  }

  static XmlDocument? _tryXml(Archive archive, String path) {
    final file = _find(archive, path);
    if (file == null) return null;
    try {
      return XmlDocument.parse(utf8.decode(file, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  /// Zip entries are case-sensitive and some builds differ in casing, so
  /// fall back to a case-insensitive match rather than failing outright.
  static List<int>? _find(Archive archive, String path) {
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (f.name == path) return f.content as List<int>;
    }
    final want = path.toLowerCase();
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (f.name.toLowerCase() == want) return f.content as List<int>;
    }
    return null;
  }
}
