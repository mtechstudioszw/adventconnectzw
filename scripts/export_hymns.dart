// Exports the published `hymns` table from Supabase into a bundled asset so
// the Hymnal tab is 100% offline — no network call on the read path, working
// on a fresh install in airplane mode.
//
// Run from the repo root whenever hymns are added / edited / removed:
//
//   dart run scripts/export_hymns.dart
//
// Then rebuild the app. The generated file is committed to the repo so CI and
// other machines don't need Supabase access to build.
//
// Reads the same public anon key the app ships with (lib/config/
// supabase_config.dart), so no secrets are needed. Override with:
//   dart run scripts/export_hymns.dart --url=... --key=...

import 'dart:convert';
import 'dart:io';

/// Keep in sync with lib/config/supabase_config.dart.
const _defaultUrl = 'https://eqbyvasteolqyktbqbem.supabase.co';
const _defaultKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVxYnl2YXN0ZW9scXlrdGJxYmVtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5NzU3NjAsImV4cCI6MjA5MzU1MTc2MH0.mur8gWyJI6EhxIbK2FHeeLUOBNgypZiELZxq2-L8d3o';

/// PostgREST caps a single response; page through in chunks this size.
const _pageSize = 500;

const _outputPath = 'assets/hymns/hymns.json';

Future<void> main(List<String> args) async {
  final url = _arg(args, 'url') ?? _defaultUrl;
  final key = _arg(args, 'key') ?? _defaultKey;

  stdout.writeln('Exporting hymns from $url …');

  final client = HttpClient();
  final rows = <Map<String, dynamic>>[];

  try {
    var offset = 0;
    while (true) {
      final page = await _fetchPage(client, url, key, offset);
      rows.addAll(page);
      stdout.writeln('  fetched ${rows.length} …');
      if (page.length < _pageSize) break;
      offset += _pageSize;
    }
  } catch (e) {
    stderr.writeln('FAILED: $e');
    exitCode = 1;
    return;
  } finally {
    client.close();
  }

  if (rows.isEmpty) {
    stderr.writeln('FAILED: no hymns returned — refusing to write an empty '
        'asset over a good one.');
    exitCode = 1;
    return;
  }

  // Keep only the fields the app model reads. Dropping is_published/created_at
  // shrinks the asset and avoids shipping columns the client never uses.
  final slim = [
    for (final r in rows)
      {
        'id': r['id'].toString(),
        'number': r['number'],
        'title': r['title'] ?? 'Untitled',
        'lyrics': r['lyrics'] ?? '',
        'language': r['language'] ?? 'Shona',
        'category': r['category'],
        'collection': r['collection'] ?? 'kristu_munzwiyo',
      },
  ];

  // Stable ordering: collection, then number, then title. A deterministic file
  // means re-running the export produces no spurious git diff.
  slim.sort((a, b) {
    final c = (a['collection'] as String).compareTo(b['collection'] as String);
    if (c != 0) return c;
    final an = (a['number'] as num?)?.toInt() ?? 1 << 30;
    final bn = (b['number'] as num?)?.toInt() ?? 1 << 30;
    if (an != bn) return an.compareTo(bn);
    return (a['title'] as String).compareTo(b['title'] as String);
  });

  final file = File(_outputPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(slim),
  );

  final byCollection = <String, int>{};
  for (final h in slim) {
    final c = h['collection'] as String;
    byCollection[c] = (byCollection[c] ?? 0) + 1;
  }

  final kb = (await file.length()) / 1024;
  stdout.writeln('Wrote ${slim.length} hymns to $_outputPath '
      '(${kb.toStringAsFixed(0)} KB)');
  byCollection.forEach((c, n) => stdout.writeln('  $c: $n'));
}

Future<List<Map<String, dynamic>>> _fetchPage(
  HttpClient client,
  String baseUrl,
  String key,
  int offset,
) async {
  final uri = Uri.parse(
    '$baseUrl/rest/v1/hymns'
    '?select=id,number,title,lyrics,language,category,collection'
    '&is_published=eq.true'
    '&order=collection.asc,number.asc',
  );
  final req = await client.getUrl(uri);
  req.headers.set('apikey', key);
  req.headers.set('Authorization', 'Bearer $key');
  req.headers.set('Range-Unit', 'items');
  req.headers.set('Range', '$offset-${offset + _pageSize - 1}');
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  // 206 Partial Content is the normal paged response; 200 means it all fit.
  if (resp.statusCode != 200 && resp.statusCode != 206) {
    throw HttpException('HTTP ${resp.statusCode}: $body');
  }
  return (jsonDecode(body) as List).cast<Map<String, dynamic>>();
}

String? _arg(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('--$name=')) return a.substring(name.length + 3);
  }
  return null;
}
