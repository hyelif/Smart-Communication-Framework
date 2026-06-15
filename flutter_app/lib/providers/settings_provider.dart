import 'package:flutter/foundation.dart';
import '../repositories/settings_repository.dart';
import '../core/dependency_injection.dart';

class SettingsProvider extends ChangeNotifier {
  final SettingsRepository _repository = getIt<SettingsRepository>();

  Map<String, dynamic> _config = {};
  List<Map<String, dynamic>> _profiles = [];
  Map<String, dynamic> _calibrationProfiles = {};
  bool _isLoading = false;
  String? _error;

  Map<String, dynamic> get config => _config;
  List<Map<String, dynamic>> get profiles => _profiles;
  Map<String, dynamic> get calibrationProfiles => _calibrationProfiles;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadConfig() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _config = await _repository.loadConfig();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveConfig(List<Map<String, dynamic>> config, String key) async {
    try {
      await _repository.saveConfig(config, key);
      _config = {'config': config, 'key': key};
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadProfiles() async {
    _isLoading = true;
    notifyListeners();

    try {
      _profiles = await _repository.getProfiles();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveAsNewProfile(String name, List<Map<String, dynamic>> config) async {
    try {
      await _repository.saveAsNewProfile(name, config);
      await loadProfiles();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteProfile(int index) async {
    try {
      await _repository.deleteProfile(index);
      _profiles.removeAt(index);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadCalibrationProfiles() async {
    _isLoading = true;
    notifyListeners();

    try {
      _calibrationProfiles = await _repository.loadCalibrationProfiles();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveCalibrationProfiles(Map<String, dynamic> profiles) async {
    try {
      await _repository.saveCalibrationProfiles(profiles);
      _calibrationProfiles = profiles;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  String encryptData(String data, String key) {
    return _repository.encrypt(data, key);
  }

  String decryptData(String data, String key) {
    return _repository.decrypt(data, key);
  }
}