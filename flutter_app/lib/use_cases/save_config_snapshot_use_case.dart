import '../services/storage_service.dart';

/// Saves a configuration snapshot to local storage.
///
/// Persists the current config and security key so they survive
/// app restarts.
class SaveConfigSnapshotUseCase {
  /// Save [config] with [securityKey] to local storage.
  Future<void> call(
    List<Map<String, dynamic>> config,
    String securityKey,
  ) async {
    await StorageService.saveConfig(config, securityKey);
  }
}
