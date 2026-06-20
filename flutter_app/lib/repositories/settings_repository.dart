import '../services/storage_service.dart';
import '../services/encryption_service.dart';

class SettingsRepository {
  final EncryptionService _encryptionService;

  SettingsRepository(this._encryptionService);

  Future<Map<String, dynamic>> loadConfig() async {
    return StorageService.loadConfig();
  }

  Future<void> saveConfig(List<Map<String, dynamic>> config, String key) async {
    await StorageService.saveConfig(config, key);
  }

  Future<List<Map<String, dynamic>>> getProfiles() async {
    return StorageService.getProfiles();
  }

  Future<void> saveAsNewProfile(
    String name,
    List<Map<String, dynamic>> config,
  ) async {
    await StorageService.saveAsNewProfile(name, config);
  }

  Future<void> deleteProfile(int index) async {
    await StorageService.deleteProfile(index);
  }

  Future<Map<String, dynamic>> loadCalibrationProfiles() async {
    return StorageService.loadCalibrationProfiles();
  }

  Future<void> saveCalibrationProfiles(Map<String, dynamic> profiles) async {
    await StorageService.saveCalibrationProfiles(profiles);
  }

  String encrypt(String input, String key) {
    return _encryptionService.encrypt(input, key);
  }

  String decrypt(String input, String key) {
    return _encryptionService.decrypt(input, key) ?? input;
  }
}