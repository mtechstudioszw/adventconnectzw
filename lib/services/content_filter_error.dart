/// The database's word filter (patch_284) refused a save: a post, comment,
/// prayer, listing, bio and so on contained a word on the blocked list.
///
/// Detected from the error text rather than the exception type, because
/// screens wrap and rethrow errors on the way up.
class ContentFilterError {
  ContentFilterError._();

  static const String message =
      "This contains words that aren't allowed in Adventist Super App. "
      'Please edit it and try again.';

  static bool matches(Object error) =>
      error.toString().contains('CONTENT_BLOCKED');
}
