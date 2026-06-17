import 'package:intl/intl.dart';

/// Utility class for formatting common data types into display strings.
class Formatters {
  Formatters._(); // Private constructor to prevent instantiation.

  // ---------------------------------------------------------------------------
  // Date/time format patterns
  // ---------------------------------------------------------------------------

  /// Pattern for full date-time display: "Jan 15, 2025 14:30".
  static const String _dateTimePattern = 'MMM dd, yyyy HH:mm';

  /// Pattern for date-only display: "Jan 15, 2025".
  static const String _dateOnlyPattern = 'MMM dd, yyyy';

  /// Pattern for time-only display: "14:30".
  static const String _timeOnlyPattern = 'HH:mm';

  // ---------------------------------------------------------------------------
  // Public formatting methods
  // ---------------------------------------------------------------------------

  /// Formats [dateTime] as "Jan 15, 2025 14:30".
  static String formatDateTime(DateTime dateTime) {
    return DateFormat(_dateTimePattern).format(dateTime);
  }

  /// Formats [dateTime] as "Jan 15, 2025".
  static String formatDate(DateTime dateTime) {
    return DateFormat(_dateOnlyPattern).format(dateTime);
  }

  /// Formats [dateTime] as "14:30".
  static String formatTime(DateTime dateTime) {
    return DateFormat(_timeOnlyPattern).format(dateTime);
  }

  /// Formats a temperature [value] with one decimal and a degree symbol, e.g. "26.5 C".
  static String formatTemperature(double value, {String unit = 'C'}) {
    return '${value.toStringAsFixed(1)}°$unit';
  }

  /// Formats a percentage [value] with one decimal, e.g. "72.5%".
  static String formatPercentage(double value) {
    return '${value.toStringAsFixed(1)}%';
  }

  /// Formats a pH [value] with one decimal, e.g. "pH 6.8".
  static String formatPh(double value) {
    return 'pH ${value.toStringAsFixed(1)}';
  }

  /// Formats a generic sensor [value] with two decimals and a [unit], e.g. "340.00 ppm".
  static String formatSensorValue(double value, String unit) {
    return '${value.toStringAsFixed(2)} $unit';
  }
}
