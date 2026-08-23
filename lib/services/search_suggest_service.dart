import 'package:supabase_flutter/supabase_flutter.dart';

/// One "did you mean…" row — a close match to a search that found nothing.
class SearchSuggestion {
  const SearchSuggestion({
    required this.kind,
    required this.refId,
    required this.label,
    this.sublabel,
    this.photoUrl,
    required this.score,
  });

  /// 'person' or 'church'. Decides the icon and where a tap goes.
  final String kind;
  final String refId;
  final String label;
  final String? sublabel;
  final String? photoUrl;

  /// Trigram similarity, 0..1. Exposed so the UI can lead with the single
  /// strongest match ("Did you mean Highfield?") when one clearly wins.
  final double score;

  bool get isPerson => kind == 'person';

  factory SearchSuggestion.fromJson(Map<String, dynamic> json) =>
      SearchSuggestion(
        kind: (json['kind'] ?? 'person').toString(),
        refId: (json['ref_id'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
        sublabel: (json['sublabel'] as String?)?.trim().isEmpty == true
            ? null
            : json['sublabel'] as String?,
        photoUrl: (json['photo_url'] as String?)?.trim().isEmpty == true
            ? null
            : json['photo_url'] as String?,
        score: (json['score'] as num?)?.toDouble() ?? 0,
      );
}

/// Close matches for a search that returned nothing.
///
/// Backed by `search_did_you_mean` (patch_230), which uses the pg_trgm
/// similarity already installed in this database. Covers people and
/// churches — the two things members search by NAME, and therefore the two
/// things they misspell. "Chitungwisa" finds Chitungwiza; "Highfeld" finds
/// Highfield.
///
/// This is deliberately separate from the generic "people you might know"
/// fallback that was already on the empty state. That one changes the
/// subject; this one answers the question that was asked.
class SearchSuggestService {
  SearchSuggestService._();

  static final SupabaseClient _client = Supabase.instance.client;

  /// Best-effort: a failure here must never turn an empty result into an
  /// error screen. The member already found nothing; a red banner on top of
  /// that helps no one.
  static Future<List<SearchSuggestion>> didYouMean(
    String term, {
    int limit = 8,
  }) async {
    final t = term.trim();
    // The RPC needs 2 characters to say anything useful, and asking on one
    // character would match most of the table.
    if (t.length < 2) return const [];
    try {
      final rows = await _client
          .rpc(
            'search_did_you_mean',
            params: {'p_term': t, 'p_limit': limit},
          )
          .timeout(const Duration(seconds: 4));
      return (rows as List)
          .map((r) => SearchSuggestion.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
