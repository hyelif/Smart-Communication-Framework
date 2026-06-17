/// Utility class for input validation.
class Validators {
  Validators._(); // Private constructor to prevent instantiation.

  // ---------------------------------------------------------------------------
  // Named constants for validation limits
  // ---------------------------------------------------------------------------

  /// Maximum value for any octet in an IPv4 address.
  static const int _maxIpOctet = 255;

  /// Minimum valid port number.
  static const int _minPort = 1;

  /// Maximum valid port number.
  static const int _maxPort = 65535;

  /// Maximum length for a sensor name.
  static const int _maxSensorNameLength = 50;

  /// Cached regex for validating IPv4 address format.
  static final RegExp _ipAddressRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');

  // ---------------------------------------------------------------------------
  // Public validation methods
  // ---------------------------------------------------------------------------

  /// Validates that [value] is a well-formed IPv4 address.
  static String? validateIpAddress(String? value) {
    if (value == null || value.isEmpty) {
      return 'IP address is required';
    }
    if (!_ipAddressRegex.hasMatch(value)) {
      return 'Enter a valid IP address';
    }
    final parts = value.split('.');
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet > _maxIpOctet) {
        return 'Invalid IP address';
      }
    }
    return null;
  }

  /// Validates that [value] is a valid port number (1-65535).
  static String? validatePort(String? value) {
    if (value == null || value.isEmpty) {
      return 'Port is required';
    }
    final port = int.tryParse(value);
    if (port == null || port < _minPort || port > _maxPort) {
      return 'Enter a valid port ($_minPort-$_maxPort)';
    }
    return null;
  }

  /// Validates that [value] is a non-empty sensor name no longer than 50 characters.
  static String? validateSensorName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Sensor name is required';
    }
    if (value.length > _maxSensorNameLength) {
      return 'Name must be less than $_maxSensorNameLength characters';
    }
    return null;
  }

  /// Validates that [value] is non-empty, using [fieldName] in the error message.
  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }
}
