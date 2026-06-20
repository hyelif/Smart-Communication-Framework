import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/settings_repository.dart';
import '../core/dependency_injection.dart';

/// State for settings-related data.
class SettingsState {
  final Map<String, dynamic> config;
  final List<Map<String, dynamic>> profiles;
  final Map<String, dynamic> calibrationProfiles;
  final bool isLoading;
  final String? error;

  const SettingsState({
    this.config = const {},
    this.profiles = const [],
    this.calibrationProfiles = const {},
    this.isLoading = false,
    this.error,
  });

  SettingsState copyWith({
    Map<String, dynamic>? config,
    List<Map<String, dynamic>>? profiles,
    Map<String, dynamic>? calibrationProfiles,
    bool? isLoading,
    String? error,
  }) {
    return SettingsState(
      config: config ?? this.config,
      profiles: profiles ?? this.profiles,
      calibrationProfiles: calibrationProfiles ?? this.calibrationProfiles,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Riverpod provider for settings state.
class SettingsNotifier extends StateNotifier<SettingsState> {
  final SettingsRepository _repository;

  SettingsNotifier(this._repository) : super(const SettingsState());

  Future<void> loadConfig() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final config = await _repository.loadConfig();
      state = state.copyWith(config: config, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<void> saveConfig(List<Map<String, dynamic>> config, String key) async {
    try {
      await _repository.saveConfig(config, key);
      state = state.copyWith(config: {'config': config, 'key': key});
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> loadProfiles() async {
    state = state.copyWith(isLoading: true);
    try {
      final profiles = await _repository.getProfiles();
      state = state.copyWith(profiles: profiles, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<void> saveAsNewProfile(String name, List<Map<String, dynamic>> config) async {
    try {
      await _repository.saveAsNewProfile(name, config);
      await loadProfiles();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteProfile(int index) async {
    try {
      await _repository.deleteProfile(index);
      final updated = List<Map<String, dynamic>>.from(state.profiles)..removeAt(index);
      state = state.copyWith(profiles: updated);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> loadCalibrationProfiles() async {
    state = state.copyWith(isLoading: true);
    try {
      final profiles = await _repository.loadCalibrationProfiles();
      state = state.copyWith(calibrationProfiles: profiles, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<void> saveCalibrationProfiles(Map<String, dynamic> profiles) async {
    try {
      await _repository.saveCalibrationProfiles(profiles);
      state = state.copyWith(calibrationProfiles: profiles);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  String encryptData(String data, String key) {
    return _repository.encrypt(data, key);
  }

  String decryptData(String data, String key) {
    return _repository.decrypt(data, key);
  }
}

/// The Riverpod provider for [SettingsNotifier].
final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier(getIt<SettingsRepository>());
});
