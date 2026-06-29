/// Shared date formatting helpers.

const List<String> _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Formats a profile's join date as "31 May 2026" for the
/// "Joined Advent Connect ZW" line shown on every profile.
String formatJoinDate(DateTime date) {
  final d = date.toLocal();
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}
