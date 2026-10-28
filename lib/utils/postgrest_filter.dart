/// Quotes [value] for a PostgREST `or()` filter string.
///
/// Search terms used to be pasted in raw, so a comma or bracket — "Bible,
/// KJV", "Hymnal (Shona)", "Mutare (Sakubva)" — was read as filter syntax,
/// the request failed, and the search silently came back empty. Double
/// quotes make PostgREST read the whole thing as one value; `"` and `\`
/// inside are backslash-escaped.
String orFilterValue(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
