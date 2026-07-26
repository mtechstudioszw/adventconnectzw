/// Models for the Sabbath School quarterlies served by Adventech's public
/// API (`sabbath-school.adventech.io`) — the same source the official
/// Sabbath School app reads, so lessons are always current and available in
/// English, Shona and 88 other languages with no data entry on our side.
///
/// Shape reference (v1):
///   /{lang}/quarterlies/index.json                     → `List<Quarterly>`
///   /{lang}/quarterlies/{qid}/index.json               → {quarterly, lessons}
///   /{lang}/quarterlies/{qid}/lessons/{lid}/index.json → {lesson, days}
///   /{lang}/.../days/{did}/read/index.json             → SsDayContent
library;

/// One of the ~90 languages Adventech publishes Sabbath School in.
class SsLanguage {
  const SsLanguage({required this.code, required this.name});

  /// ISO code used in every API path, e.g. 'sn', 'en', 'af'.
  final String code;

  /// English display name as the API gives it, e.g. 'Shona'.
  final String name;

  factory SsLanguage.fromJson(Map<String, dynamic> json) => SsLanguage(
        code: (json['code'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'code': code, 'name': name};
}

/// A quarter's worth of lessons (13 weeks).
class Quarterly {
  const Quarterly({
    required this.id,
    required this.lang,
    required this.title,
    required this.humanDate,
    this.description = '',
    this.cover,
    this.splash,
    this.colorPrimary,
    this.introduction,
    this.groupName,
    this.startDate,
    this.endDate,
  });

  /// e.g. "2026-03".
  final String id;
  final String lang;
  final String title;

  /// e.g. "July · August · September 2026".
  final String humanDate;
  final String description;
  final String? cover;
  final String? splash;

  /// Quarterly's own accent colour, as an ARGB int. Used to tint the cover
  /// card so each quarter feels distinct.
  final int? colorPrimary;
  final String? introduction;

  /// e.g. "Standard Adult" — lets us surface the adult quarterly first and
  /// group the rest (Primary, Youth, …).
  final String? groupName;
  final DateTime? startDate;
  final DateTime? endDate;

  /// True when today falls inside this quarter — drives the "Current" badge
  /// and which quarterly opens by default.
  bool get isCurrent {
    final now = DateTime.now();
    final s = startDate;
    final e = endDate;
    if (s == null || e == null) return false;
    return !now.isBefore(s) && !now.isAfter(e.add(const Duration(days: 1)));
  }

  factory Quarterly.fromJson(Map<String, dynamic> json) {
    return Quarterly(
      id: (json['id'] ?? '').toString(),
      lang: (json['lang'] ?? 'en').toString(),
      title: (json['title'] ?? 'Untitled').toString(),
      humanDate: (json['human_date'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      cover: json['cover'] as String?,
      splash: json['splash'] as String?,
      colorPrimary: parseHexColor(json['color_primary'] as String?),
      introduction: json['introduction'] as String?,
      groupName: (json['quarterly_group'] is Map)
          ? (json['quarterly_group']['name'] as String?)
          : null,
      startDate: parseSsDate(json['start_date'] as String?),
      endDate: parseSsDate(json['end_date'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'lang': lang,
        'title': title,
        'human_date': humanDate,
        'description': description,
        'cover': cover,
        'splash': splash,
        'color_primary': colorPrimary == null
            ? null
            : '#${(colorPrimary! & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        'introduction': introduction,
        'quarterly_group': groupName == null ? null : {'name': groupName},
        'start_date': formatSsDate(startDate),
        'end_date': formatSsDate(endDate),
      };
}

/// One week of the quarter.
class SsLesson {
  const SsLesson({
    required this.id,
    required this.title,
    this.cover,
    this.startDate,
    this.endDate,
  });

  /// Zero-padded week number, e.g. "05".
  final String id;
  final String title;
  final String? cover;
  final DateTime? startDate;
  final DateTime? endDate;

  int get weekNumber => int.tryParse(id) ?? 0;

  /// True when today falls inside this week.
  bool get isCurrent {
    final now = DateTime.now();
    final s = startDate;
    final e = endDate;
    if (s == null || e == null) return false;
    return !now.isBefore(s) && !now.isAfter(e.add(const Duration(days: 1)));
  }

  factory SsLesson.fromJson(Map<String, dynamic> json) => SsLesson(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? 'Untitled').toString(),
        cover: json['cover'] as String?,
        startDate: parseSsDate(json['start_date'] as String?),
        endDate: parseSsDate(json['end_date'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'cover': cover,
        'start_date': formatSsDate(startDate),
        'end_date': formatSsDate(endDate),
      };
}

/// One day within a lesson week (Sabbath afternoon through Friday).
class SsDay {
  const SsDay({
    required this.id,
    required this.title,
    required this.readPath,
    this.date,
  });

  final String id;
  final String title;

  /// Relative path used to fetch the day's content, e.g.
  /// `en/quarterlies/2026-03/lessons/05/days/01/read`.
  final String readPath;
  final DateTime? date;

  /// True when this is today's reading.
  bool get isToday {
    final d = date;
    if (d == null) return false;
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  factory SsDay.fromJson(Map<String, dynamic> json) => SsDay(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        readPath: (json['read_path'] ?? '').toString(),
        date: parseSsDate(json['date'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'read_path': readPath,
        'date': formatSsDate(date),
      };
}

/// The readable body of a single day, plus the Bible passages it cites.
class SsDayContent {
  const SsDayContent({
    required this.id,
    required this.title,
    required this.contentHtml,
    this.bible = const {},
    this.date,
  });

  final String id;
  final String title;

  /// Lesson body as HTML. Rendered natively by `SsHtmlText` — the tag set is
  /// small (h*, p, a, blockquote, em/strong, hr, br, small).
  final String contentHtml;

  /// Verse reference → verse HTML, keyed exactly as the `verse` attribute on
  /// inline `<a class="verse">` links, so tapping a reference can show the
  /// passage without a network call.
  final Map<String, String> bible;

  final DateTime? date;

  factory SsDayContent.fromJson(Map<String, dynamic> json) {
    // `bible` is a list of translations, each with its own verse map. We
    // flatten to the FIRST translation — the API orders it as the intended
    // one for that language, and a translation picker would be noise here.
    final bible = <String, String>{};
    final raw = json['bible'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map && entry['verses'] is Map) {
          (entry['verses'] as Map).forEach((k, v) {
            bible.putIfAbsent(k.toString(), () => v.toString());
          });
        }
      }
    }
    return SsDayContent(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      contentHtml: (json['content'] ?? '').toString(),
      bible: bible,
      date: parseSsDate(json['date'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': contentHtml,
        'date': formatSsDate(date),
        'bible': [
          {'name': 'default', 'verses': bible},
        ],
      };
}

// ---------------------------------------------------------------------------
//  Helpers
// ---------------------------------------------------------------------------

/// Parses the API's `dd/MM/yyyy` dates. Returns null on anything unexpected
/// rather than throwing — a missing date only costs a badge.
DateTime? parseSsDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final parts = raw.split('/');
  if (parts.length != 3) return DateTime.tryParse(raw);
  final d = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final y = int.tryParse(parts[2]);
  if (d == null || m == null || y == null) return null;
  return DateTime(y, m, d);
}

/// Inverse of [parseSsDate], for the offline cache round-trip.
String? formatSsDate(DateTime? date) {
  if (date == null) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year}';
}

/// `#RRGGBB` → opaque ARGB int. Null when absent or malformed.
int? parseHexColor(String? hex) {
  if (hex == null) return null;
  final clean = hex.replaceAll('#', '').trim();
  if (clean.length != 6) return null;
  final value = int.tryParse(clean, radix: 16);
  return value == null ? null : 0xFF000000 | value;
}
