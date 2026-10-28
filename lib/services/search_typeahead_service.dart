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
  });

  final SearchHitKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final bool verified;

  /// Kind-specific data the tap needs (a [BibleReference], a [Hymn]).
  final Object? payload;
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
    return [
      SearchHit(
        kind: SearchHitKind.verse,
        id: label,
        title: label,
        subtitle: 'Open in the Bible',
        payload: ref,
      ),
    ];
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
    return [
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
            'Page',
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

  static String _price(Object? price, Object? currency) {
    final p = (price as num?)?.toDouble() ?? 0;
    final c = (currency as String?) ?? 'USD';
    final symbol = c == 'USD' ? r'$' : '$c ';
    return p == p.roundToDouble()
        ? '$symbol${p.toStringAsFixed(0)}'
        : '$symbol${p.toStringAsFixed(2)}';
  }
}
