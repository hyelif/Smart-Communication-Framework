import 'package:flutter/foundation.dart';
import '../repositories/device_repository.dart';
import '../services/nfc_service.dart';
import '../core/dependency_injection.dart';

class DeviceProvider extends ChangeNotifier {
  final DeviceRepository _repository = getIt<DeviceRepository>();

  List<Map<String, dynamic>> _liveSensors = [];
  bool _isLoading = false;
  bool _nfcAvailable = false;
  String? _error;
  bool _disposed = false;

  List<Map<String, dynamic>> get liveSensors => _liveSensors;
  bool get isLoading => _isLoading;
  bool get nfcAvailable => _nfcAvailable;
  String? get error => _error;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  Future<void> checkNfcAvailability() async {
    _nfcAvailable = await _repository.isNfcAvailable();
    _notifyListeners();
  }

  Future<void> fetchLiveSensors() async {
    _isLoading = true;
    _error = null;
    _notifyListeners();

    try {
      _liveSensors = await _repository.fetchLiveSensors();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      _notifyListeners();
    }
  }

  Future<NfcWriteResult?> writeSmartPonicTag({
    required Map<String, dynamic> configPayload,
    required String securityKey,
    required String aesKey,
  }) async {
    _isLoading = true;
    _error = null;
    _notifyListeners();

    try {
      final result = await _repository.writeSmartPonicTag(
        configPayload: configPayload,
        securityKey: securityKey,
        aesKey: aesKey,
      );
      _isLoading = false;
      _notifyListeners();
      return result;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      _notifyListeners();
      return null;
    }
  }

  Future<NfcWriteResult?> prepareDirectPhoneTap({
    required Map<String, dynamic> configPayload,
    required String securityKey,
    required String aesKey,
  }) async {
    _isLoading = true;
    _error = null;
    _notifyListeners();

    try {
      final result = await _repository.prepareDirectPhoneTap(
        configPayload: configPayload,
        securityKey: securityKey,
        aesKey: aesKey,
      );
      _isLoading = false;
      _notifyListeners();
      return result;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      _notifyListeners();
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