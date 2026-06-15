import 'package:flutter/foundation.dart';
import '../models/sensor_model.dart';
import '../repositories/sensor_repository.dart';
import '../core/dependency_injection.dart';

class SensorProvider extends ChangeNotifier {
  final SensorRepository _repository = getIt<SensorRepository>();

  List<SensorModel> _sensors = [];
  List<Map<String, dynamic>> _rawConfig = [];
  bool _isLoading = false;
  String? _error;

  List<SensorModel> get sensors => _sensors;
  List<Map<String, dynamic>> get rawConfig => _rawConfig;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchConfig(String securityKey) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _repository.fetchConfig(securityKey);
      if (result['ok'] == true && result['data'] != null) {
        _rawConfig = List<Map<String, dynamic>>.from(result['data']['config'] ?? []);
        _sensors = _rawConfig.map((json) => SensorModel.fromMap(json)).toList();
      } else {
        _error = result['body'] ?? 'Failed to fetch config';
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> sendConfig(List<Map<String, dynamic>> config, String securityKey) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _repository.sendConfig(config, securityKey);
      _isLoading = false;
      notifyListeners();
      return result['ok'] == true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> loadSavedConfig() async {
    _isLoading = true;
    notifyListeners();

    try {
      _rawConfig = await _repository.loadConfig();
      _sensors = _rawConfig.map((json) => SensorModel.fromMap(json)).toList();
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
      _rawConfig = config;
      _sensors = config.map((json) => SensorModel.fromMap(json)).toList();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadSavedSensors() async {
    await loadSavedConfig();
  }
}