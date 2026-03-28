import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileExchangeService {
  static Future<List<Map<String, dynamic>>> importConfigFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      throw const _FileExchangeException('File selection cancelled.');
    }

    final file = result.files.single;
    final bytes = file.bytes ?? await _readBytesFromPath(file.path);
    if (bytes == null || bytes.isEmpty) {
      throw const _FileExchangeException('Selected file is empty.');
    }

    final decoded = jsonDecode(utf8.decode(bytes));
    final payload = decoded is Map<String, dynamic> ? decoded['config'] : decoded;

    if (payload is! List) {
      throw const _FileExchangeException('JSON file does not contain a valid config list.');
    }

    return payload
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<void> exportAndShareConfig(
    List<Map<String, dynamic>> config,
  ) async {
    if (config.isEmpty) {
      throw const _FileExchangeException('Add at least one sensor node before exporting.');
    }

    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${directory.path}\\smartponic_config_$timestamp.json');

    final payload = {
      'app': 'SmartPonic',
      'exportedAt': DateTime.now().toIso8601String(),
      'config': config,
    };

    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      text: 'SmartPonic node configuration',
      subject: 'SmartPonic Config Export',
    );
  }

  static Future<Uint8List?> _readBytesFromPath(String? path) async {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }
}

class _FileExchangeException implements Exception {
  final String message;

  const _FileExchangeException(this.message);

  @override
  String toString() => message;
}
