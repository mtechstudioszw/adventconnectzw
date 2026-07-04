/// Shared validation for real names + usernames.
///
/// Real names (first name + surname) get a LIGHT junk filter — we block
/// obvious garbage (blank, single letters, keyboard-mash, repeated
/// characters, digits/symbols) but deliberately DON'T try to judge whether a
/// name is "funny", because that wrongly rejects real but unusual, mononym or
/// non-English names. Anything questionable that slips through is handled by
/// report + admin review, not a pre-emptive block.
///
/// Usernames may be playful — the only rules are a sane format and
/// uniqueness (enforced case-insensitively by the DB).
class NameValidator {
  NameValidator._();

  /// Obvious placeholder / keyboard-mash tokens that are never real names.
  static const _junk = <String>{
    'test', 'testing', 'tests', 'asdf', 'asdfgh', 'asdfghjkl', 'qwerty',
    'qwe', 'qwerty123', 'abc', 'abcd', 'abcde', 'xxx', 'xyz', 'blah',
    'name', 'firstname', 'lastname', 'surname', 'fullname', 'user',
    'username', 'anonymous', 'anon', 'unknown', 'none', 'null', 'nil',
    'na', 'nan', 'nobody', 'noname', 'dummy', 'sample', 'example',
  };

  /// Validate ONE name part (first name or surname). [field] is folded into
  /// the message, e.g. "First name is required". Returns null when acceptable.
  static String? namePart(String? raw, String field) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return '$field is required.';
    if (v.length < 2) return 'Enter your real $field.';
    // Letters (any script, incl. accents), plus spaces, apostrophes, dots and
    // hyphens — no digits or other symbols in a real name.
    if (!RegExp(r"^\p{L}[\p{L} .'\-]*$", unicode: true).hasMatch(v)) {
      return 'Use letters only for your $field.';
    }
    final lower = v.toLowerCase();
    if (_junk.contains(lower)) return 'Please enter your real $field.';
    // All one repeated letter ("aaaa", "zzz") — keyboard-mash, not a name.
    final letters = lower.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
    if (letters.isNotEmpty && letters.split('').toSet().length == 1) {
      return 'Please enter your real $field.';
    }
    return null;
  }

  /// Validate a combined display name (older single-field screens): must be a
  /// first name AND a surname, each passing [namePart].
  static String? fullName(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return 'Your name is required.';
    final parts = v.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) return 'Enter your first name and surname.';
    return namePart(parts.first, 'First name') ??
        namePart(parts.last, 'Surname');
  }

  /// Assemble a stored full name from the two fields (collapses whitespace).
  static String combine(String first, String surname) =>
      '${first.trim()} ${surname.trim()}'.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Username format check (uniqueness is enforced by the DB, checked live via
  /// [UserProfileService]). Funny is fine; junk format is not. 3–20 chars,
  /// letters / digits / dot / underscore, must contain at least one letter.
  static String? username(String? raw, {bool required = false}) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return required ? 'Username is required.' : null;
    if (v.length < 3) return 'At least 3 characters.';
    if (v.length > 20) return 'Keep it under 20 characters.';
    if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(v)) {
      return 'Letters, numbers, . and _ only.';
    }
    if (!RegExp(r'[a-zA-Z]').hasMatch(v)) return 'Include at least one letter.';
    return null;
  }
}
