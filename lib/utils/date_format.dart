/// Shared date formatting helpers.

const List<String> _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Formats a profile's join date as "31 May 2026" for the
/// "Joined Adventist Super App" line shown on every profile.
String formatJoinDate(DateTime date) {
  final d = date.toLocal();
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

const List<String> _shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Compact relative age — `now`, `5m`, `3h`, `2d`, `6w`, then a date.
///
/// The same four-line ladder was written out by hand in at least four
/// places (Watch, church announcements, the inbox, the feed), each with
/// slightly different wording and cut-offs. This is that ladder, once.
///
/// Stops being relative after about six weeks: "63d ago" is arithmetic, not
/// information, and by then a member wants the date.
String formatTimeAgo(DateTime time) {
  final t = time.toLocal();
  final diff = DateTime.now().difference(t);

  if (diff.isNegative || diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  if (diff.inDays < 42) return '${(diff.inDays / 7).floor()}w';
  final sameYear = t.year == DateTime.now().year;
  final date = '${t.day} ${_shortMonths[t.month - 1]}';
  return sameYear ? date : '$date ${t.year}';
}
