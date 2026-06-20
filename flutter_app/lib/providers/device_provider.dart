import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/device_repository.dart';
import '../services/nfc_service.dart';
import '../core/dependency_injection.dart';

/// State for device-related data.
class DeviceState {
  final List<Map<String, dynamic>> liveSensors;
  final bool isLoading;
  final bool nfcAvailable;
  final String? error;

  const DeviceState({
    this.liveSensors = const [],
    this.isLoading = false,
    this.nfcAvailable = false,
    this.error,
  });

  DeviceState copyWith({
    List<Map<String, dynamic>>? liveSensors,
    bool? isLoading,
    bool? nfcAvailable,
    String? error,
  }) {
    return DeviceState(
      liveSensors: liveSensors ?? this.liveSensors,
      isLoading: isLoading ?? this.isLoading,
      nfcAvailable: nfcAvailable ?? this.nfcAvailable,
      error: error,
    );
  }
}

/// Riverpod provider for device state.
class DeviceNotifier extends StateNotifier<DeviceState> {
  final DeviceRepository _repository;

  DeviceNotifier(this._repository) : super(const DeviceState());

  Future<void> checkNfcAvailability() async {
    final available = await _repository.isNfcAvailable();
    state = state.copyWith(nfcAvailable: available);
  }

  Future<void> fetchLiveSensors() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final sensors = await _repository.fetchLiveSensors();
      state = state.copyWith(liveSensors: sensors, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<NfcWriteResult?> writeSmartPonicTag({
    required Map<String, dynamic> configPayload,
    required String securityKey,
    required String aesKey,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repository.writeSmartPonicTag(
        configPayload: configPayload,
        securityKey: securityKey,
        aesKey: aesKey,
      );
      state = state.copyWith(isLoading: false);
      return result;
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
      return null;
    }
  }

  Future<NfcWriteResult?> prepareDirectPhoneTap({
    required Map<String, dynamic> configPayload,
    required String securityKey,
    required String aesKey,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repository.prepareDirectPhoneTap(
        configPayload: configPayload,
        securityKey: securityKey,
        aesKey: aesKey,
      );
      state = state.copyWith(isLoading: false);
      return result;
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
      return null;
    }
  }

  Future<void> stopDirectPhoneTap() async {
    await _repository.stopDirectPhoneTap();
  }

  String encrypt(String input, String key) {
    return _repository.encrypt(input, key);
  }

  String decrypt(String input, String key) {
    return _repository.decrypt(input, key);
  }
}

/// The Riverpod provider for [DeviceNotifier].
final deviceProvider = StateNotifierProvider<DeviceNotifier, DeviceState>((ref) {
  return DeviceNotifier(getIt<DeviceRepository>());
});
