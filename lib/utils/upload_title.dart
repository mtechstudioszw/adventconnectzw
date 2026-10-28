/// A readable default title from an uploaded file's name.
///
/// Bulk music upload used the bare file name, so the shelf read
/// "Love_at_Home_-_SDA_Hymn_#_652(0)". This strips the extension, the
/// download-tool suffixes — "(0)", "(1)", "(256k)" — and the underscores
/// standing in for spaces. Admins can still rename; this is only the
/// starting point.
String titleFromFileName(String fileName) {
  var t = fileName.trim();
  final dot = t.lastIndexOf('.');
  if (dot > 0) t = t.substring(0, dot);
  final suffix = RegExp(r'\s*\((\d+k?)\)\s*$', caseSensitive: false);
  while (suffix.hasMatch(t)) {
    t = t.replaceFirst(suffix, '');
  }
  t = t
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'#\s+(?=\d)'), '#')
      .replaceAll(RegExp(r'\s+-\s+'), ' - ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
  return t.isEmpty ? fileName : t;
}
