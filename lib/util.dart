const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Dates are stored as 'yyyy-MM-dd' strings so they sort and compare correctly.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDay(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String todayKey() => dayKey(DateTime.now());

String daysAgoKey(int days) {
  final n = DateTime.now();
  return dayKey(DateTime(n.year, n.month, n.day - days));
}

String shiftDay(String key, int delta) {
  final d = parseDay(key);
  return dayKey(DateTime(d.year, d.month, d.day + delta));
}

int daysBetween(DateTime a, DateTime b) => (dateOnly(b).difference(dateOnly(a)).inHours / 24).round();

String shortDate(String key) {
  final d = parseDay(key);
  return '${d.day} ${_months[d.month - 1]}';
}

String prettyDay(String key) {
  final diff = daysBetween(parseDay(key), DateTime.now());
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return shortDate(key);
}

/// 60 -> "60", 62.5 -> "62.5"
String fmtW(double w) => w == w.roundToDouble() ? w.toStringAsFixed(0) : w.toStringAsFixed(1);

double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

double minOf(Iterable<double> xs) => xs.fold<double>(double.infinity, (a, b) => a < b ? a : b);
double maxOf(Iterable<double> xs) => xs.fold<double>(double.negativeInfinity, (a, b) => a > b ? a : b);
