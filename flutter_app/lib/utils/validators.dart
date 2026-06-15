class Validators {
  static String? validateIpAddress(String? value) {
    if (value == null || value.isEmpty) {
      return 'IP address is required';
    }
    final regex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (!regex.hasMatch(value)) {
      return 'Enter a valid IP address';
    }
    final parts = value.split('.');
    for (final part in parts) {
      if (int.parse(part) > 255) {
        return 'Invalid IP address';
      }
    }
    return null;
  }

  static String? validatePort(String? value) {
    if (value == null || value.isEmpty) {
      return 'Port is required';
    }
    final port = int.tryParse(value);
    if (port == null || port < 1 || port > 65535) {
      return 'Enter a valid port (1-65535)';
    }
    return null;
  }

  static String? validateSensorName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Sensor name is required';
    }
    if (value.length > 50) {
      return 'Name must be less than 50 characters';
    }
    return null;
  }

  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }
}