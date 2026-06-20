import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sensor_model.dart';
import '../repositories/sensor_repository.dart';
import '../core/dependency_injection.dart';

/// State for sensor configuration data.
class SensorState {
  final List<SensorModel> sensors;
  final List<Map<String, dynamic>> rawConfig;
  final bool isLoading;
  final String? error;

  const SensorState({
    this.sensors = const [],
    this.rawConfig = const [],
    this.isLoading = false,
    this.error,
  });

  SensorState copyWith({
    List<SensorModel>? sensors,
    List<Map<String, dynamic>>? rawConfig,
    bool? isLoading,
    String? error,
  }) {
    return SensorState(
      sensors: sensors ?? this.sensors,
      rawConfig: rawConfig ?? this.rawConfig,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Riverpod provider for sensor configuration state.
class SensorNotifier extends StateNotifier<SensorState> {
  final SensorRepository _repository;

  SensorNotifier(this._repository) : super(const SensorState());

  Future<void> fetchConfig(String securityKey) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repository.fetchConfig(securityKey);
      if (result['ok'] == true && result['data'] != null) {
        final rawConfig = List<Map<String, dynamic>>.from(
          result['data']['config'] ?? [],
        );
        final sensors = rawConfig.map((json) => SensorModel.fromMap(json)).toList();
        state = state.copyWith(
          rawConfig: rawConfig,
          sensors: sensors,
          isLoading: false,
        );
      } else {
        state = state.copyWith(
          error: result['body']?.toString() ?? 'Failed to fetch config',
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<bool> sendConfig(List<Map<String, dynamic>> config, String securityKey) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repository.sendConfig(config, securityKey);
      final success = result['ok'] == true;
      state = state.copyWith(isLoading: false);
      return success;
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
      return false;
    }
  }

  Future<void> loadSavedConfig() async {
    state = state.copyWith(isLoading: true);
    try {
      final rawConfig = await _repository.loadConfig();
      final sensors = rawConfig.map((json) => SensorModel.fromMap(json)).toList();
      state = state.copyWith(rawConfig: rawConfig, sensors: sensors, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<void> saveConfig(List<Map<String, dynamic>> config, String key) async {
    try {
      await _repository.saveConfig(config, key);
      final sensors = config.map((json) => SensorModel.fromMap(json)).toList();
      state = state.copyWith(rawConfig: config, sensors: sensors);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

/// The Riverpod provider for [SensorNotifier].
final sensorProvider = StateNotifierProvider<SensorNotifier, SensorState>((ref) {
  return SensorNotifier(getIt<SensorRepository>());
});
