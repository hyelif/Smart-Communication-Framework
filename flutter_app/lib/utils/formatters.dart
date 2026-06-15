import 'package:intl/intl.dart';

class Formatters {
  static String formatDateTime(DateTime dateTime) {
    return DateFormat('MMM dd, yyyy HH:mm').format(dateTime);
  }

  static String formatDate(DateTime dateTime) {
    return DateFormat('MMM dd, yyyy').format(dateTime);
  }

  static String formatTime(DateTime dateTime) {
    return DateFormat('HH:mm').format(dateTime);
  }

  static String formatTemperature(double value, {String unit = 'C'}) {
    return '${value.toStringAsFixed(1)}°$unit';
  }

  static String formatPercentage(double value) {
    return '${value.toStringAsFixed(1)}%';
  }

  static String formatPh(double value) {
    return 'pH ${value.toStringAsFixed(1)}';
  }

  static String formatSensorValue(double value, String unit) {
    return '${value.toStringAsFixed(2)} $unit';
  }
}