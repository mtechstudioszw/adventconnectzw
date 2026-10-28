import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/postgrest_filter.dart';
import 'bible_service.dart';
import 'hymn_service.dart';

/// What a suggestion is — decides its icon and where a tap goes.
enum SearchHitKind { person, page, church, product, job, verse, hymn }

/// One suggestion in the as-you-type list.
class SearchHit {
  const SearchHit({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.verified = false,
    this.payload,
    this.mutualFriends,
    this.preview,
  });

  final SearchHitKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final bool verified;

  /// Kind-specific data the tap needs (a [BibleReference], a [Hymn]).
  final Object? payload;

  /// For a person: friends you have in common (real count), when known.
  final int? mutualFriends;

  /// For a verse: its text, shown under the reference.
  final String? preview;

  SearchHit withMutual(int n) => SearchHit(
    kind: kind,
    id: id,
    title: title,
    subtitle: subtitle,
    imageUrl: imageUrl,
    verified: verified,
    payload: payload,
    mutualFriends: n,
    preview: preview,
  );
}

/// Suggestions while typing (search redesign, 28 Oct 2026).
///
/// Light by design — the full search runs only on submit. Each source asks
/// for a handful of rows and only the columns a suggestion row shows; they
/// run in parallel and each fails alone. Church and people names are
/// matched through the trigram indexes already on those tables
/// (idx_churches_name_trgm, idx_profiles_full_name_trgm). Bible references
/// ("John 3:16") and hymn numbers/titles resolve on the device.
///
/// No new backend: when a single combined search function is approved it
/// can replace [suggest]'s body without touching the screen.
class SearchTypeaheadService {
  SearchTypeaheadService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static const perKind = 3;

  static Future<List<SearchHit>> suggest(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return const [];
    // `like` is quoted for or() filters; `pattern` is the raw form .ilike()
    // takes.
    final like = orFilterValue('%$q%');
    final pattern = '%$q%';

    Future<List<SearchHit>> safe(Future<List<SearchHit>> Function() f) async {
      try {
        return await f();
      } catch (_) {
        return const [];
      }
    }

    final parts = await Future.wait([
      safe(() => _verse(q)),
      safe(() => _versesContaining(q)),
      safe(() => _hymns(q)),
      safe(() => _people(like)),
      safe(() => _pages(pattern)),
      safe(() => _churches(pattern)),
      safe(() => _products(pattern)),
      safe(() => _jobs(like)),
    ]);
    // Order: a direct jump first (verse, hymn), then people, Pages,
    // churches, shop, jobs.
    return [for (final p in parts) ...p];
  }

  static Future<List<SearchHit>> _verse(String q) async {
    // Needs a digit to be a reference — "John" alone is a person search.
    if (!RegExp(r'\d').hasMatch(q) || q.length < 4) return const [];
    final ref = await BibleService.resolveReference(q);
    if (ref == null) return const [];
    final label =
        '${ref.book.name} ${ref.chapter}${ref.verse == null ? '' : ':${ref.verse}'}';
    String? text;
    final c = ref.chapter - 1;
    final v = (ref.verse ?? 1) - 1;
    if (c >= 0 &&
        c < ref.book.chapters.length &&
        v >= 0 &&
        v < ref.book.chapters[c].length) {
      text = BibleService.cleanVerse(ref.book.chapters[c][v]);
    }
    return [
      SearchHit(
        kind: SearchHitKind.verse,
        id: label,
        title: label,
        subtitle: 'Open in the Bible',
        payload: ref,
        preview: text,
      ),
    ];
  }

  /// "love one another" → the verses that say it (bundled KJV, on the
  /// device). Only for phrases — two words or more — so a name search
  /// isn't buried under scripture.
  static Future<List<SearchHit>> _versesContaining(String q) async {
    final words = q
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toList();
    if (words.length < 2 || q.length < 7 || RegExp(r'\d').hasMatch(q)) {
      return const [];
    }
    // The exact phrase first ("love one another" → John 13:34); failing
    // that, every word as a WHOLE word — plain substring matching found
    // "love" inside "beloved" and returned the wrong verses.
    final phrase = words.join(' ');
    final wholeWords = [
      for (final w in words) RegExp('\\b${RegExp.escape(w)}\\b'),
    ];
    final books = await BibleService.books();
    final exact = <SearchHit>[];
    final loose = <SearchHit>[];
    for (final book in books) {
      for (var c = 0; c < book.chapters.length; c++) {
        final verses = book.chapters[c];
        for (var v = 0; v < verses.length; v++) {
          final text = BibleService.cleanVerse(verses[v]);
          final lower = text.toLowerCase();
          final isExact = lower.contains(phrase);
          if (!isExact &&
              (loose.length >= 2 ||
                  !wholeWords.every((r) => r.hasMatch(lower)))) {
            continue;
          }
          final hit = SearchHit(
            kind: SearchHitKind.verse,
            id: '${book.name} ${c + 1}:${v + 1}',
            title: '${book.name} ${c + 1}:${v + 1}',
            subtitle: 'Bible verse',
            preview: text,
            payload: BibleReference(book: book, chapter: c + 1, verse: v + 1),
          );
          (isExact ? exact : loose).add(hit);
          if (exact.length >= 2) return exact;
        }
      }
    }
    return [...exact, ...loose].take(2).toList();
  }

  static Future<List<SearchHit>> _hymns(String q) async {
    final isNumber = int.tryParse(q) != null;
    if (!isNumber && q.length < 3) return const [];
    final hymns = await HymnService.search(q);
    return [
      for (final h in hymns.take(isNumber ? 1 : 2))
        SearchHit(
          kind: SearchHitKind.hymn,
          id: h.id,
          title: h.number == null ? h.title : '${h.number}. ${h.title}',
          subtitle: 'Hymn',
          payload: h,
        ),
    ];
  }

  static Future<List<SearchHit>> _people(String like) async {
    final rows = await _client
        .from('profiles')
        .select('id, full_name, username, profile_photo_url, city, is_verified')
        .eq('is_discoverable', true)
        .or('full_name.ilike.$like,username.ilike.$like')
        .limit(perKind + 1);
    final me = _client.auth.currentUser?.id;
    final people = [
      for (final r in rows as List)
        if (r['id'] != me)
          SearchHit(
            kind: SearchHitKind.person,
            id: r['id'].toString(),
            title: (r['full_name'] as String?)?.trim().isNotEmpty == true
                ? r['full_name'] as String
                : '@${r['username'] ?? 'member'}',
            subtitle: [
              if ((r['username'] as String?)?.isNotEmpty == true)
                '@${r['username']}',
              if ((r['city'] as String?)?.isNotEmpty == true) r['city'],
            ].join(' · '),
            imageUrl: r['profile_photo_url'] as String?,
            verified: r['is_verified'] == true,
          ),
    ].take(perKind).toList();
    // "3 mutual friends" — the real count, from mutual_friends (which only
    // ever reveals the overlap, never the other person's friend list).
    if (me == null) return people;
    final counts = await Future.wait([
      for (final p in people)
        _client
            .rpc('mutual_friends', params: {'p_user': p.id, 'p_limit': 1})
            .then<int>((rows) {
              final list = rows as List;
              if (list.isEmpty) return 0;
              return ((list.first as Map)['total'] as num?)?.toInt() ??
                  list.length;
            })
            .catchError((_) => 0),
    ]);
    return [
      for (var i = 0; i < people.length; i++)
        counts[i] > 0 ? people[i].withMutual(counts[i]) : people[i],
    ];
  }

  static Future<List<SearchHit>> _pages(String like) async {
    final rows = await _client
        .from('pages')
        .select('id, name, category, logo_url, city, is_verified')
        .eq('status', 'active')
        .ilike('name', like)
        .limit(perKind);
    return [
      for (final r in rows as List)
        SearchHit(
          kind: SearchHitKind.page,
          id: r['id'].toString(),
          title: r['name'] as String? ?? 'Page',
          subtitle: [
            _pageCategory(r['category'] as String?),
            if ((r['city'] as String?)?.isNotEmpty == true) r['city'],
          ].join(' · '),
          imageUrl: r['logo_url'] as String?,
          verified: r['is_verified'] == true,
        ),
    ];
  }

  static Future<List<SearchHit>> _churches(String like) async {
    final rows = await _client
        .from('churches')
        .select('id, name, city, profile_photo_url')
        .ilike('name', like)
        .limit(perKind);
    return [
      for (final r in rows as List)
        SearchHit(
          kind: SearchHitKind.church,
          id: r['id'].toString(),
          title: r['name'] as String? ?? 'Church',
          subtitle: [
            'Church',
            if ((r['city'] as String?)?.isNotEmpty == true) r['city'],
          ].join(' · '),
          imageUrl: r['profile_photo_url'] as String?,
        ),
    ];
  }

  static Future<List<SearchHit>> _products(String like) async {
    final rows = await _client
        .from('products')
        .select('id, title, price, price_currency, image_urls')
        .eq('status', 'available')
        .ilike('title', like)
        .limit(perKind);
    return [
      for (final r in rows as List)
        SearchHit(
          kind: SearchHitKind.product,
          id: r['id'].toString(),
          title: r['title'] as String? ?? 'Item',
          subtitle: 'Shop · ${_price(r['price'], r['price_currency'])}',
          imageUrl:
              (r['image_urls'] is List && (r['image_urls'] as List).isNotEmpty)
              ? (r['image_urls'] as List).first.toString()
              : null,
        ),
    ];
  }

  static Future<List<SearchHit>> _jobs(String like) async {
    final rows = await _client
        .from('jobs')
        .select('id, title, company, location')
        .eq('status', 'open')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .or('title.ilike.$like,company.ilike.$like')
        .limit(perKind);
    return [
      for (final r in rows as List)
        SearchHit(
          kind: SearchHitKind.job,
          id: r['id'].toString(),
          title: r['title'] as String? ?? 'Job',
          subtitle: [
            'Job',
            if ((r['company'] as String?)?.isNotEmpty == true) r['company'],
            if ((r['location'] as String?)?.isNotEmpty == true) r['location'],
          ].join(' · '),
        ),
    ];
  }

  static String _pageCategory(String? c) => switch (c) {
    'ministry' => 'Ministry',
    'school' => 'School',
    'community' => 'Community organization',
    'business' => 'Business',
    _ => 'Page',
  };

  static String _price(Object? price, Object? currency) {
    final p = (price as num?)?.toDouble() ?? 0;
    final c = (currency as String?) ?? 'USD';
    final symbol = c == 'USD' ? r'$' : '$c ';
    return p == p.roundToDouble()
        ? '$symbol${p.toStringAsFixed(0)}'
        : '$symbol${p.toStringAsFixed(2)}';
  }
}
