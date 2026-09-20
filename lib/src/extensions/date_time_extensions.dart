/// DateTime extension utilities available on non-nullable [DateTime].
extension LikeDateTimeExtension on DateTime {
  /// Whether the date is today.
  bool get isToday => isSameDay(DateTime.now());

  /// Checks if this date is the same day as [other].
  bool isSameDay(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }

  /// Checks if this date is in the same month as [other].
  bool isSameMonth(DateTime other) {
    return year == other.year && month == other.month;
  }

  /// Checks if this date is in the same year as [other].
  bool isSameYear(DateTime other) {
    return year == other.year;
  }

  /// Returns the next day (+1 day).
  DateTime get nextDay => add(const Duration(days: 1));

  /// Returns the previous day (-1 day).
  DateTime get previousDay => subtract(const Duration(days: 1));

  /// Returns the next week (+7 days).
  DateTime get nextWeek => add(const Duration(days: 7));

  /// Returns the previous week (-7 days).
  DateTime get previousWeek => subtract(const Duration(days: 7));

  /// Returns the same day in the next month.
  DateTime get nextMonth {
    final newMonth = month == 12 ? 1 : month + 1;
    final newYear = month == 12 ? year + 1 : year;
    final lastDayOfNewMonth = DateTime(newYear, newMonth + 1, 0).day;
    final newDay = day > lastDayOfNewMonth ? lastDayOfNewMonth : day;
    return DateTime(newYear, newMonth, newDay, hour, minute, second,
        millisecond, microsecond);
  }

  /// Returns the same day in the previous month.
  DateTime get previousMonth {
    final newMonth = month == 1 ? 12 : month - 1;
    final newYear = month == 1 ? year - 1 : year;
    final lastDayOfNewMonth = DateTime(newYear, newMonth + 1, 0).day;
    final newDay = day > lastDayOfNewMonth ? lastDayOfNewMonth : day;
    return DateTime(newYear, newMonth, newDay, hour, minute, second,
        millisecond, microsecond);
  }

  /// Returns the same day in the next year.
  DateTime get nextYear => DateTime(
      year + 1, month, day, hour, minute, second, millisecond, microsecond);

  /// Returns the same day in the previous year.
  DateTime get previousYear => DateTime(
      year - 1, month, day, hour, minute, second, millisecond, microsecond);

  /// Returns start of the day (00:00:00.000).
  DateTime get startOfDay => DateTime(year, month, day);

  /// Returns end of the day (23:59:59.999).
  DateTime get endOfDay => DateTime(year, month, day, 23, 59, 59, 999);

  /// Returns start of the week (Monday 00:00:00).
  DateTime get startOfWeek {
    final monday = subtract(Duration(days: weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  /// Returns end of the week (Sunday 23:59:59.999).
  DateTime get endOfWeek {
    final sunday = add(Duration(days: DateTime.daysPerWeek - weekday));
    return DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59, 999);
  }

  /// Returns start of the month (1st day 00:00:00).
  DateTime get startOfMonth => DateTime(year, month, 1);

  /// Returns end of the month (last day 23:59:59.999).
  DateTime get endOfMonth => DateTime(year, month + 1, 0, 23, 59, 59, 999);

  /// Returns start of the year (Jan 1 00:00:00).
  DateTime get startOfYear => DateTime(year, 1, 1);

  /// Returns end of the year (Dec 31 23:59:59.999).
  DateTime get endOfYear => DateTime(year, 12, 31, 23, 59, 59, 999);

  /// Returns the difference duration between this date and [other].
  Duration differenceFrom(DateTime other) => difference(other);

  /// Returns ISO-8601 formatted date string (YYYY-MM-DD).
  String get toDateString {
    return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }

  /// Returns human-readable relative time string (e.g. "just now", "5m ago", "2h ago", "3d ago").
  String get timeAgo {
    final diff = DateTime.now().difference(this);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return toDateString;
  }
}
