import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  StorageService._(); // Private constructor to prevent instantiation.

  /// Public factory for dependency injection.
  factory StorageService() => _instance;
  static final StorageService _instance = StorageService._();

  // ---------------------------------------------------------------------------
  // Named string key constants
  // ---------------------------------------------------------------------------

  /// SharedPreferences key for the ESP32 config data JSON.
  static const String configKey = 'esp_config_data';

  /// SharedPreferences key for the ESP32 profiles list JSON.
  static const String profilesKey = 'esp_profiles_list';

  /// SharedPreferences key for the ESP32 AES key.
  static const String aesKey = 'esp_aes_key';

  /// SharedPreferences key for the ESP32 calibration profiles JSON.
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

  static Future<SharedPreferences> _prefs() {
    return _prefsFuture ??= SharedPreferences.getInstance();
  }

  static Future<void> _ensureConfigCache() async {
    if (_configLoaded) return;
    final prefs = await _prefs();
    _cachedConfigJson = prefs.getString(configKey);
    _configLoaded = true;
  }

  static Future<void> _ensureProfilesCache() async {
    if (_profilesLoaded) return;
    final prefs = await _prefs();
    _cachedProfilesJson = prefs.getString(profilesKey);
    _profilesLoaded = true;
  }

  static Future<void> _ensureKeyCache() async {
    if (_keyLoaded) return;
    final prefs = await _prefs();
    _cachedKey = prefs.getString(aesKey);
    _keyLoaded = true;
  }

  static Future<void> _ensureCalibrationCache() async {
    if (_calibrationLoaded) return;
    final prefs = await _prefs();
    _cachedCalibrationJson = prefs.getString(calibrationKey);
    _calibrationLoaded = true;
  }

  static Future<void> saveConfig(List<Map<String, dynamic>> config, String key) async {
    final prefs = await _prefs();
    _cachedConfigJson = jsonEncode(config);
    _cachedKey = key;
    _configLoaded = true;
    _keyLoaded = true;
    await prefs.setString(configKey, _cachedConfigJson!);
    await prefs.setString(aesKey, key);
  }

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

  static Future<List<Map<String, dynamic>>> getProfiles() async {
    await _ensureProfilesCache();
    if (_cachedProfilesParsed != null) return _cachedProfilesParsed!;
    final data = _cachedProfilesJson;
    if (data == null) return [];
    _cachedProfilesParsed = List<Map<String, dynamic>>.from(jsonDecode(data));
    return _cachedProfilesParsed!;
  }

  // Calibration profiles are stored as:
  // { "temperature": {threshold_min, threshold_max, calibration_a, calibration_b, calibration_c}, ... }
  static Future<Map<String, dynamic>> loadCalibrationProfiles() async {
    await _ensureCalibrationCache();
    if (_cachedCalibrationParsed != null) return _cachedCalibrationParsed!;
    final data = _cachedCalibrationJson;
    if (data == null || data.isEmpty) return {};
    final decoded = jsonDecode(data);
    if (decoded is Map<String, dynamic>) {
      _cachedCalibrationParsed = decoded;
      return decoded;
    }
    return {};
  }

  static Future<void> saveCalibrationProfiles(Map<String, dynamic> profiles) async {
    final prefs = await _prefs();
    _cachedCalibrationJson = jsonEncode(profiles);
    _cachedCalibrationParsed = profiles;
    _calibrationLoaded = true;
    await prefs.setString(calibrationKey, _cachedCalibrationJson!);
  }

  static Future<void> saveAsNewProfile(
    String name,
    List<Map<String, dynamic>> config,
  ) async {
    final prefs = await _prefs();
    final profiles = await getProfiles();
    final newProfile = {
      'name': name,
      'time': DateTime.now().toIso8601String(),
      'config': config,
    };
    final updated = [newProfile, ...profiles];
    _cachedProfilesJson = jsonEncode(updated);
    _cachedProfilesParsed = updated;
    _profilesLoaded = true;
    await prefs.setString(profilesKey, _cachedProfilesJson!);
  }

  static Future<void> saveProfile(
    String name,
    List<Map<String, dynamic>> config,
  ) async {
    await saveAsNewProfile(name, config);
  }

  static Future<void> deleteProfile(int index) async {
    final prefs = await _prefs();
    final profiles = await getProfiles();
    if (index >= 0 && index < profiles.length) {
      final updated = List<Map<String, dynamic>>.from(profiles)..removeAt(index);
      _cachedProfilesJson = jsonEncode(updated);
      _cachedProfilesParsed = updated;
      _profilesLoaded = true;
      await prefs.setString(profilesKey, _cachedProfilesJson!);
    }
  }
}