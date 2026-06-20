import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  LocationService._(); // Private constructor to prevent instantiation.

  /// Public factory for dependency injection.
  factory LocationService() => _instance;
  static final LocationService _instance = LocationService._();

  // ---------------------------------------------------------------------------
  // Named constants
  // ---------------------------------------------------------------------------

  /// GPS location timeout in seconds.
  static const int _locationTimeoutSeconds = 10;

  /// Threshold in meters below which distance is shown in meters (1 km).
  static const double _metersThreshold = 1000;

  /// Number of meters in one kilometre.
  static const double _metersPerKm = 1000;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  static LocationPermission? _cachedPermission;

  /// Request location permission from user
  static Future<PermissionStatus> requestPermission() async {
    final status = await Permission.locationWhenInUse.request();
    _cachedPermission = await Geolocator.checkPermission();
    return status;
  }

  /// Check current permission status
  static Future<bool> hasPermission() async {
    _cachedPermission ??= await Geolocator.checkPermission();
    return _cachedPermission == LocationPermission.whileInUse ||
           _cachedPermission == LocationPermission.always;
  }

  /// Get current GPS location
  static Future<Position?> getCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: _locationTimeoutSeconds),
        ),
      );
      return position;
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }

  /// Calculate distance between two GPS coordinates (Haversine formula)
  static double calculateDistance({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// Format distance for display
  static String formatDistance(double meters) {
    if (meters < _metersThreshold) {
      return '${meters.toStringAsFixed(1)} m';
    }
    return '${(meters / _metersPerKm).toStringAsFixed(2)} km';
  }

  /// Open phone's location settings
  static Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }
}
