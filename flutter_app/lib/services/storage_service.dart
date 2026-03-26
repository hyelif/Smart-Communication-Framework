import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _configKey = 'esp_config_data';
  static const String _profilesKey = 'esp_profiles_list';
  static const String _aesKey = 'esp_aes_key';

  static Future<void> saveConfig(List<Map<String, dynamic>> config, String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config));
    await prefs.setString(_aesKey, key);
  }

  static Future<Map<String, dynamic>> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'config': prefs.getString(_configKey),
      'key': prefs.getString(_aesKey),
    };
  }

  static Future<List<Map<String, dynamic>>> getProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_profilesKey);
    if (data == null) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(data));
  }

  static Future<void> saveAsNewProfile(
    String name,
    List<Map<String, dynamic>> config,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await getProfiles();
    profiles.insert(0, {
      'name': name,
      'time': DateTime.now().toIso8601String(),
      'config': config,
    });
    await prefs.setString(_profilesKey, jsonEncode(profiles));
  }

  static Future<void> saveProfile(
    String name,
    List<Map<String, dynamic>> config,
  ) async {
    await saveAsNewProfile(name, config);
  }

  static Future<void> deleteProfile(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await getProfiles();
    if (index >= 0 && index < profiles.length) {
      profiles.removeAt(index);
      await prefs.setString(_profilesKey, jsonEncode(profiles));
    }
  }
}
