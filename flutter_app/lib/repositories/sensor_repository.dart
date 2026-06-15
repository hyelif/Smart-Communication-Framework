import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../models/sensor_model.dart';

class SensorRepository {
  Future<Map<String, dynamic>> fetchConfig(String securityKey) async {
    return ApiService.fetchConfig(securityKey);
  }

  Future<Map<String, dynamic>> sendConfig(
    List<Map<String, dynamic>> config,
    String securityKey,
  ) async {
    return ApiService.sendConfig(config, securityKey);
  }

  Future<Map<String, dynamic>> fetchHealth() async {
    return ApiService.fetchHealth();
  }

  Future<List<Map<String, dynamic>>> loadConfig() async {
    final data = await StorageService.loadConfig();
    final configJson = data['config'];
    if (configJson == null) return [];
    return List<Map<String, dynamic>>.from(configJson);
  }

  Future<void> saveConfig(List<Map<String, dynamic>> config, String key) async {
    await StorageService.saveConfig(config, key);
  }

  Future<List<SensorModel>> loadSavedSensors() async {
    final config = await loadConfig();
    return config.map((json) => SensorModel.fromMap(json)).toList();
  }
}