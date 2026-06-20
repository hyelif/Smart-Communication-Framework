import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/api_service.dart';
import '../../services/location_service.dart';
import '../../services/nfc_payload_service.dart';
import '../../services/nfc_service.dart';
import '../../services/storage_service.dart';
import '../../use_cases/deploy_configuration_use_case.dart';
import '../../use_cases/import_export_config_use_case.dart';
import '../../use_cases/load_device_config_use_case.dart';
import '../../use_cases/save_config_snapshot_use_case.dart';
import '../../use_cases/validate_configuration_use_case.dart';
import '../../utils/config_validator.dart';
import 'models/config_state.dart';

/// Riverpod provider for the Config (Architect) screen state.
final configControllerProvider =
    StateNotifierProvider<ConfigController, ConfigState>((ref) {
  return ConfigController();
});

/// Controller for the Config (Architect) screen.
///
/// Manages all state and business logic for the configuration workflow,
/// delegating to use cases for operations.
class ConfigController extends StateNotifier<ConfigState> {
  final DeployConfigurationUseCase _deployUseCase;
  final ValidateConfigurationUseCase _validateUseCase;
  final LoadDeviceConfigUseCase _loadUseCase;
  final SaveConfigSnapshotUseCase _saveUseCase;
  final ImportExportConfigUseCase _importExportUseCase;

  ConfigController()
      : _deployUseCase = DeployConfigurationUseCase(),
        _validateUseCase = ValidateConfigurationUseCase(),
        _loadUseCase = LoadDeviceConfigUseCase(),
        _saveUseCase = SaveConfigSnapshotUseCase(),
        _importExportUseCase = ImportExportConfigUseCase(),
        super(const ConfigState()) {
    _refreshPage();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void setSecurityKey(String value) {
    state = state.copyWith(securityKey: value);
  }

  void setAesKey(String value) {
    state = state.copyWith(aesKey: value);
  }

  void setLatitude(String value) {
    state = state.copyWith(latitude: value);
  }

  void setLongitude(String value) {
    state = state.copyWith(longitude: value);
  }

  void setVariant(Esp32Variant variant) {
    state = state.copyWith(selectedVariant: variant);
  }

  void toggleKeyVisibility() {
    state = state.copyWith(isKeyVisible: !state.isKeyVisible);
  }

  void setConfig(List<Map<String, dynamic>> config) {
    state = state.copyWith(config: config);
  }

  void removeNode(int index) {
    final updated = List<Map<String, dynamic>>.from(state.config)
      ..removeAt(index);
    state = state.copyWith(config: updated);
  }

  void addNode(Map<String, dynamic> item) {
    final updated = List<Map<String, dynamic>>.from(state.config)
      ..add(item);
    state = state.copyWith(config: updated);
  }

  void clearFeedback() {
    state = state.copyWith(clearFeedback: true);
  }

  // ---------------------------------------------------------------------------
  // Operations
  // ---------------------------------------------------------------------------

  Future<void> _refreshPage() async {
    if (state.isRefreshingPage) return;
    state = state.copyWith(isRefreshingPage: true);
    try {
      final stored = await StorageService.loadConfig();
      final key = stored['key'] as String?;
      final raw = stored['config'] as String?;
      final parsed = raw == null || raw.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(jsonDecode(raw));

      final newKey = key ?? state.securityKey;
      final normalized = _validateUseCase.normalize(parsed);
      final configChanged = !_validateUseCase.sameConfig(normalized, state.config);

      state = state.copyWith(
        securityKey: newKey,
        config: configChanged ? normalized : state.config,
        isRefreshingPage: false,
        feedbackMessage: 'Architect page refreshed.',
        feedbackIsError: false,
      );
    } catch (_) {
      state = state.copyWith(isRefreshingPage: false);
    }
  }

  Future<void> saveSnapshot() async {
    final normalized = _validateUseCase.normalize(state.config);
    if (!_validateUseCase.sameConfig(normalized, state.config)) {
      state = state.copyWith(config: normalized);
    }
    await _saveUseCase(normalized, state.securityKey);
    state = state.copyWith(
      feedbackMessage: 'Architect draft saved locally.',
      feedbackIsError: false,
    );
  }

  Future<void> fetchCurrentLocation() async {
    state = state.copyWith(isFetchingLocation: true);
    try {
      final hasPerm = await LocationService.hasPermission();
      if (!hasPerm) {
        final status = await LocationService.requestPermission();
        if (status != PermissionStatus.granted) {
          state = state.copyWith(
            isFetchingLocation: false,
            feedbackMessage: 'Location permission denied',
            feedbackIsError: true,
          );
          return;
        }
      }

      final position = await LocationService.getCurrentLocation();
      if (position != null) {
        state = state.copyWith(
          latitude: position.latitude.toStringAsFixed(6),
          longitude: position.longitude.toStringAsFixed(6),
          isFetchingLocation: false,
          feedbackMessage: 'GPS location captured',
        );
      } else {
        state = state.copyWith(
          isFetchingLocation: false,
          feedbackMessage: 'Failed to get GPS location',
          feedbackIsError: true,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isFetchingLocation: false,
        feedbackMessage: 'Location error: $e',
        feedbackIsError: true,
      );
    }
  }

  Future<Map<String, dynamic>?> _buildConfigWithMetadata({
    required String securityKey,
    required bool includeNfcKeys,
  }) async {
    if (securityKey.isEmpty) {
      state = state.copyWith(
        feedbackMessage: 'Enter the node security key before deploying config.',
        feedbackIsError: true,
      );
      return null;
    }

    final latitude = double.tryParse(state.latitude);
    final longitude = double.tryParse(state.longitude);

    if (latitude == null || longitude == null) {
      state = state.copyWith(
        feedbackMessage: 'Invalid GPS coordinates',
        feedbackIsError: true,
      );
      return null;
    }

    if (includeNfcKeys) {
      try {
        NfcPayloadService.validateAesKey(state.aesKey);
      } on FormatException catch (e) {
        state = state.copyWith(
          feedbackMessage: e.message,
          feedbackIsError: true,
        );
        return null;
      }
    }

    final normalizedConfig = _validateUseCase.normalize(state.config);
    final configErrors = _validateUseCase(
      normalizedConfig,
      variant: state.selectedVariant,
    );
    if (configErrors.isNotEmpty) {
      state = state.copyWith(
        feedbackMessage: configErrors.first.message,
        feedbackIsError: true,
      );
      return null;
    }

    if (!_validateUseCase.sameConfig(normalizedConfig, state.config)) {
      state = state.copyWith(config: normalizedConfig);
    }

    final configWithMetadata = <String, dynamic>{
      'config': normalizedConfig,
      'latitude': latitude,
      'longitude': longitude,
    };

    try {
      final profiles = await StorageService.loadCalibrationProfiles();
      if (profiles.isNotEmpty) {
        configWithMetadata['calibration'] = profiles;
      }
    } catch (_) {}

    try {
      final aesKey = NfcPayloadService.validateAesKey(state.aesKey);
      configWithMetadata['keys'] = {
        'aes128': aesKey,
        'auth': NfcPayloadService.defaultAuthKey,
      };
    } on FormatException {
      if (includeNfcKeys) rethrow;
    }

    return configWithMetadata;
  }

  Future<void> deployToNode() async {
    final securityKey = state.securityKey;
    final configWithMetadata = await _buildConfigWithMetadata(
      securityKey: securityKey,
      includeNfcKeys: false,
    );
    if (configWithMetadata == null) return;

    state = state.copyWith(isDeploying: true);

    try {
      await _saveUseCase(state.config, securityKey);
      final result = await _deployUseCase(configWithMetadata, securityKey);

      state = state.copyWith(
        isDeploying: false,
        feedbackMessage: result.message,
        feedbackIsError: !result.success,
      );
    } catch (e) {
      state = state.copyWith(
        isDeploying: false,
        feedbackMessage: ApiService.friendlyConnectionMessage(e),
        feedbackIsError: true,
      );
    }
  }

  Future<void> loadFromNode() async {
    final securityKey = state.securityKey;
    if (securityKey.isEmpty) {
      state = state.copyWith(
        feedbackMessage: 'Enter the node security key before loading config.',
        feedbackIsError: true,
      );
      return;
    }

    state = state.copyWith(isLoadingNode: true);

    try {
      final loaded = await _loadUseCase(securityKey);
      state = state.copyWith(
        config: loaded,
        isLoadingNode: false,
        feedbackMessage: 'Loaded config from ESP32.',
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingNode: false,
        feedbackMessage: e.toString(),
        feedbackIsError: true,
      );
    }
  }

  Future<void> importFromFile() async {
    if (state.isImportingFile) return;
    state = state.copyWith(isImportingFile: true);

    try {
      final result = await _importExportUseCase.importConfig();
      if (result.cancelled) {
        state = state.copyWith(isImportingFile: false);
        return;
      }

      final normalized = _validateUseCase.normalize(result.config);
      final errors = _validateUseCase(
        normalized,
        variant: state.selectedVariant,
      );
      if (errors.isNotEmpty) {
        throw Exception(errors.first.message);
      }

      state = state.copyWith(
        config: normalized,
        isImportingFile: false,
        feedbackMessage: 'Imported ${normalized.length} node(s) from phone storage.',
      );
      await _saveUseCase(normalized, state.securityKey);
    } catch (e) {
      state = state.copyWith(
        isImportingFile: false,
        feedbackMessage: 'Import failed: $e',
        feedbackIsError: true,
      );
    }
  }

  Future<void> exportToFile() async {
    if (state.isExportingFile) return;
    state = state.copyWith(isExportingFile: true);

    try {
      await _importExportUseCase.exportConfig(state.config);
      state = state.copyWith(
        isExportingFile: false,
        feedbackMessage: 'Config file prepared for sharing.',
      );
    } catch (e) {
      state = state.copyWith(
        isExportingFile: false,
        feedbackMessage: 'Export failed: $e',
        feedbackIsError: true,
      );
    }
  }

  Future<void> writeNfcTag() async {
    final securityKey = state.securityKey;
    final configWithMetadata = await _buildConfigWithMetadata(
      securityKey: securityKey,
      includeNfcKeys: true,
    );
    if (configWithMetadata == null) return;

    state = state.copyWith(isWritingNfc: true);

    try {
      await _saveUseCase(state.config, securityKey);
      state = state.copyWith(
        feedbackMessage: 'Hold the NFC tag near your phone.',
      );

      final result = await NfcService.writeSmartPonicTag(
        configPayload: configWithMetadata,
        securityKey: securityKey,
        aesKey: state.aesKey,
      );

      state = state.copyWith(
        isWritingNfc: false,
        feedbackMessage:
            'NFC tag written (${result.bytesWritten} encrypted bytes). Tap it to the ESP32 node.',
      );
    } on TimeoutException {
      state = state.copyWith(
        isWritingNfc: false,
        feedbackMessage: 'NFC write timed out.',
        feedbackIsError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isWritingNfc: false,
        feedbackMessage: 'NFC write failed: $e',
        feedbackIsError: true,
      );
    }
  }

  Future<void> prepareDirectNfcTap() async {
    final securityKey = state.securityKey;
    if (securityKey.isEmpty) {
      state = state.copyWith(
        feedbackMessage: 'Please enter the security key first',
        feedbackIsError: true,
      );
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final notifStatus = await Permission.notification.request();
      if (notifStatus.isDenied) {
        state = state.copyWith(
          feedbackMessage: 'NFC needs notification permission',
          feedbackIsError: true,
        );
        return;
      }
    }
  }
}
