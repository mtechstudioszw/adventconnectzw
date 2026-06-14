/// A daily devotion — a public-domain KJV Bible verse paired with a
/// public-domain Ellen G. White quote (patch_108).
class Devotion {
  const Devotion({
    required this.bibleRef,
    required this.bibleText,
    required this.egwQuote,
    required this.egwSource,
    this.theme,
  });

  final String bibleRef;
  final String bibleText;
  final String egwQuote;
  final String egwSource;
  final String? theme;

  factory Devotion.fromJson(Map<String, dynamic> json) {
    return Devotion(
      bibleRef: (json['bible_ref'] ?? '') as String,
      bibleText: (json['bible_text'] ?? '') as String,
      egwQuote: (json['egw_quote'] ?? '') as String,
      egwSource: (json['egw_source'] ?? '') as String,
      theme: json['theme'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'bible_ref': bibleRef,
        'bible_text': bibleText,
        'egw_quote': egwQuote,
        'egw_source': egwSource,
        'theme': theme,
      };
}
