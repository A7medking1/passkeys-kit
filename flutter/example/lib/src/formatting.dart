const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Nov 21, 2026".
String formatDate(DateTime date) =>
    '${_months[date.month - 1]} ${date.day}, ${date.year}';

/// "just now", "5 minutes ago", "yesterday", then the date after a week.
String timeAgo(DateTime date, {DateTime? now}) {
  final ago = (now ?? DateTime.now()).difference(date);
  if (ago.inMinutes < 1) return 'just now';
  if (ago.inHours < 1) return _plural(ago.inMinutes, 'minute');
  if (ago.inDays < 1) return _plural(ago.inHours, 'hour');
  if (ago.inDays == 1) return 'yesterday';
  if (ago.inDays < 7) return '${ago.inDays} days ago';
  return formatDate(date);
}

String _plural(int count, String unit) =>
    count == 1 ? '1 $unit ago' : '$count ${unit}s ago';
