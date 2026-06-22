import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Local storage for ESP32 configuration, profiles, and calibration data.
///
/// All public methods handle errors gracefully — returning empty/default
/// values instead of throwing.
class StorageService {
  StorageService._();

  factory StorageService() => _instance;
  static final StorageService _instance = StorageService._();

  // ---------------------------------------------------------------------------
  // Keys
  // ---------------------------------------------------------------------------

  static const String configKey = 'esp_config_data';
  static const String profilesKey = 'esp_profiles_list';
  static const String aesKey = 'esp_aes_key';
  static const String calibrationKey = 'esp_calibration_profiles';

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  static Future<SharedPreferences>? _prefsFuture;
  static bool _configLoaded = false;
  static bool _profilesLoaded = false;
  static bool _keyLoaded = false;
  static bool _calibrationLoaded = false;
  static String? _cachedConfigJson;
  static String? _cachedProfilesJson;
  static List<Map<String, dynamic>>? _cachedProfilesParsed;
  static String? _cachedKey;
  static String? _cachedCalibrationJson;
  static Map<String, dynamic>? _cachedCalibrationParsed;

  /// Clear all cached data. Call when switching accounts or resetting.
  static void clearCache() {
    _configLoaded = false;
    _profilesLoaded = false;
    _keyLoaded = false;
    _calibrationLoaded = false;
    _cachedConfigJson = null;
    _cachedProfilesJson = null;
    _cachedProfilesParsed = null;
    _cachedKey = null;
    _cachedCalibrationJson = null;
    _cachedCalibrationParsed = null;
  }

  static Future<SharedPreferences> _prefs() {
    return _prefsFuture ??= SharedPreferences.getInstance();
  }

  static Future<void> _ensureConfigCache() async {
    if (_configLoaded) return;
    try {
      final prefs = await _prefs();
      _cachedConfigJson = prefs.getString(configKey);
    } catch (_) {
      _cachedConfigJson = null;
    }
    _configLoaded = true;
  }

  static Future<void> _ensureProfilesCache() async {
    if (_profilesLoaded) return;
    try {
      final prefs = await _prefs();
      _cachedProfilesJson = prefs.getString(profilesKey);
    } catch (_) {
      _cachedProfilesJson = null;
    }
    _profilesLoaded = true;
  }

  static Future<void> _ensureKeyCache() async {
    if (_keyLoaded) return;
    try {
      final prefs = await _prefs();
      _cachedKey = prefs.getString(aesKey);
    } catch (_) {
      _cachedKey = null;
    }
    _keyLoaded = true;
  }

  static Future<void> _ensureCalibrationCache() async {
    if (_calibrationLoaded) return;
    try {
      final prefs = await _prefs();
      _cachedCalibrationJson = prefs.getString(calibrationKey);
    } catch (_) {
      _cachedCalibrationJson = null;
    }
    _calibrationLoaded = true;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Save ESP32 config and AES key to local storage.
  static Future<void> saveConfig(List<Map<String, dynamic>> config, String key) async {
    try {
      final prefs = await _prefs();
      final json = jsonEncode(config);
      await prefs.setString(configKey, json);
      await prefs.setString(aesKey, key);
      _cachedConfigJson = json;
      _cachedKey = key;
      _configLoaded = true;
      _keyLoaded = true;
    } catch (_) {
      // Silently fail — next save will retry.
    }
  }

  /// Load ESP32 config and AES key from local storage.
  static Future<Map<String, dynamic>> loadConfig() async {
    await Future.wait([
      _ensureConfigCache(),
      _ensureKeyCache(),
    ]);
    return {
      'config': _cachedConfigJson,
      'key': _cachedKey,
    };
  }

  /// Get all saved profiles.
  static Future<List<Map<String, dynamic>>> getProfiles() async {
    await _ensureProfilesCache();
    if (_cachedProfilesParsed != null) return _cachedProfilesParsed!;
    final data = _cachedProfilesJson;
    if (data == null) return [];
    try {
      final decoded = jsonDecode(data);
      if (decoded is List) {
        _cachedProfilesParsed = List<Map<String, dynamic>>.from(decoded);
      }
    } catch (_) {
      // Corrupted data — return empty.
      _cachedProfilesParsed = [];
    }
    return _cachedProfilesParsed ?? [];
  }

  /// Load calibration profiles from local storage.
  static Future<Map<String, dynamic>> loadCalibrationProfiles() async {
    await _ensureCalibrationCache();
    if (_cachedCalibrationParsed != null) return _cachedCalibrationParsed!;
    final data = _cachedCalibrationJson;
    if (data == null || data.isEmpty) return {};
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        _cachedCalibrationParsed = decoded;
        return decoded;
      }
    } catch (_) {
      // Corrupted data — return empty.
    }
    return {};
  }

  /// Save calibration profiles to local storage.
  static Future<void> saveCalibrationProfiles(Map<String, dynamic> profiles) async {
    try {
      final prefs = await _prefs();
      final json = jsonEncode(profiles);
      await prefs.setString(calibrationKey, json);
      _cachedCalibrationJson = json;
      _cachedCalibrationParsed = profiles;
      _calibrationLoaded = true;
    } catch (_) {
      // Silently fail.
    }
  }

  /// Save a new profile to the profiles list.
  static Future<void> saveAsNewProfile(
    String name,
    List<Map<String, dynamic>> config,
  ) async {
    try {
      final prefs = await _prefs();
      final profiles = await getProfiles();
      final newProfile = {
        'name': name,
        'time': DateTime.now().toIso8601String(),
        'config': config,
      };
      final updated = [newProfile, ...profiles];
      final json = jsonEncode(updated);
      await prefs.setString(profilesKey, json);
      _cachedProfilesJson = json;
      _cachedProfilesParsed = updated;
      _profilesLoaded = true;
    } catch (_) {
      // Silently fail.
    }
  }

  /// Save a profile (legacy wrapper for [saveAsNewProfile]).
  static Future<void> saveProfile(
    String name,
    List<Map<String, dynamic>> config,
  ) async {
    await saveAsNewProfile(name, config);
  }

  /// Delete a profile by index.
  static Future<void> deleteProfile(int index) async {
    try {
      final prefs = await _prefs();
      final profiles = await getProfiles();
      if (index >= 0 && index < profiles.length) {
        final updated = List<Map<String, dynamic>>.from(profiles)..removeAt(index);
        final json = jsonEncode(updated);
        await prefs.setString(profilesKey, json);
        _cachedProfilesJson = json;
        _cachedProfilesParsed = updated;
        _profilesLoaded = true;
      }
    } catch (_) {
      // Silently fail.
    }
  }
}
