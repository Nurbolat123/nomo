// Formatting helpers that avoid locale data downloads.

/// 1200 → "1 200 ₸"
String money(int amount, {String currency = 'KZT'}) {
  final s = amount.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  final sign = amount < 0 ? '−' : '';
  final symbol = switch (currency) { 'KZT' => '₸', 'RUB' => '₽', 'USD' => r'$', _ => currency };
  return '$sign$b $symbol';
}

/// Seconds → "5 мин" (at least 1 minute).
String minutes(int seconds, {String unit = 'мин'}) {
  final m = (seconds / 60).ceil();
  return '${m < 1 ? 1 : m} $unit';
}

/// Meters → "850 м" or "4,2 км".
String distance(int meters, {String m = 'м', String km = 'км'}) {
  if (meters < 1000) return '$meters $m';
  return '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} $km';
}

String two(int n) => n.toString().padLeft(2, '0');

/// "16.10, 14:05"
String dateTime(DateTime t) => '${two(t.day)}.${two(t.month)}, ${two(t.hour)}:${two(t.minute)}';

/// "+7 701 111 22 33"
String prettyPhone(String phone) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.length == 11 && d.startsWith('7')) {
    return '+7 ${d.substring(1, 4)} ${d.substring(4, 7)} ${d.substring(7, 9)} ${d.substring(9)}';
  }
  return phone;
}
