import 'dart:convert';
import 'dart:io';

import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/sabbath_school_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// A phone with no connection at all: every request fails.
class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _DeadClient();
}

class _DeadClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      Future.error(const SocketException('offline'));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late Directory dir;
  const lang = 'en';
  const q = '2026-04';

  Future<void> put(String key, Object value) =>
      CacheService.writeString(key, jsonEncode(value));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ss_offline');
    Hive.init(dir.path);
    await CacheService.debugUseBox(await Hive.openBox<String>('ss'));
    HttpOverrides.global = _NoNetwork();

    await put('ss:quarterlies:$lang', [
      {'id': q, 'title': 'Saved quarter', 'path': '$lang/quarterlies/$q'},
    ]);
    await put('ss:lessons:$lang:$q', [
      {'id': '01', 'title': 'Week one'},
      {'id': '02', 'title': 'Week two'},
    ]);
    // Week one fully saved (both days); week two never opened.
    await put('ss:days:$lang:$q:01', [
      {'id': '01', 'title': 'Sabbath', 'read_path': 'r/01/01'},
      {'id': '02', 'title': 'Sunday', 'read_path': 'r/01/02'},
    ]);
    for (final p in ['r/01/01', 'r/01/02']) {
      await put('ss:read:$p', {
        'id': p,
        'title': 'Day',
        'content': '<p>Hi</p>',
      });
    }
  });

  tearDown(() async {
    HttpOverrides.global = null;
    await CacheService.debugUseBox(null);
    await dir.delete(recursive: true);
  });

  test('a saved quarter opens with no connection', () async {
    final shelf = await SabbathSchoolService.quarterlies(lang: lang);
    expect(shelf.single.title, 'Saved quarter');

    final weeks = await SabbathSchoolService.lessons(q, lang: lang);
    expect(weeks.map((w) => w.title), ['Week one', 'Week two']);

    final days = await SabbathSchoolService.days(q, '01', lang: lang);
    expect(days, hasLength(2));

    final body = await SabbathSchoolService.dayContent('r/01/02');
    expect(body?.contentHtml, '<p>Hi</p>');
  });

  test('saved weeks and lessons open instantly (no network wait)', () async {
    final sw = Stopwatch()..start();
    await SabbathSchoolService.lessons(q, lang: lang);
    await SabbathSchoolService.days(q, '01', lang: lang);
    expect(sw.elapsedMilliseconds, lessThan(500));
  });

  test('saved-week count drives the Download all row', () async {
    expect(
      await SabbathSchoolService.isLessonDownloaded(q, '01', lang: lang),
      isTrue,
    );
    expect(
      await SabbathSchoolService.isLessonDownloaded(q, '02', lang: lang),
      isFalse,
    );
    final s = await SabbathSchoolService.quarterlySaved(q, lang: lang);
    expect((s.saved, s.total), (1, 2));
  });

  test('Download all offline reports the weeks it could not save', () async {
    final failed = await SabbathSchoolService.downloadQuarterly(q, lang: lang);
    expect(failed, 1); // week two needs the network; week one was skipped
    expect(SabbathSchoolService.quarterProgress.value, isEmpty);
  });
}
