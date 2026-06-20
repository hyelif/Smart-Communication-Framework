import '../services/file_exchange_service.dart';

/// Result of importing a config from a file.
class ImportResult {
  final List<Map<String, dynamic>> config;
  final bool cancelled;

  const ImportResult({
    required this.config,
    this.cancelled = false,
  });

  bool get isEmpty => config.isEmpty;
}

/// Handles importing and exporting node configurations to/from files.
class ImportExportConfigUseCase {
  /// Import a configuration from a user-selected JSON file.
  ///
  /// Returns [ImportResult] with the parsed config, or with
  /// [ImportResult.cancelled] set to true if the user cancelled.
  Future<ImportResult> importConfig() async {
    try {
      final config = await FileExchangeService.importConfigFromFile();
      return ImportResult(config: config);
    } catch (e) {
      if (e.toString().contains('cancelled')) {
        return const ImportResult(config: [], cancelled: true);
      }
      rethrow;
    }
  }

  /// Export [config] to a JSON file and open the share sheet.
  Future<void> exportConfig(List<Map<String, dynamic>> config) async {
    await FileExchangeService.exportAndShareConfig(config);
  }
}
