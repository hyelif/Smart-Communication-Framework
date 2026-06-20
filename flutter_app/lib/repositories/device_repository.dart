import '../services/device_service.dart';
import '../services/nfc_service.dart';
import '../services/encryption_service.dart';

class DeviceRepository {
  final DeviceService _deviceService;
  final EncryptionService _encryptionService;

  DeviceRepository(
    this._deviceService,
    this._encryptionService,
  );

  Future<List<Map<String, dynamic>>> fetchLiveSensors() async {
    return _deviceService.fetchLiveSensors();
  }

  Future<bool> isNfcAvailable() async {
    return NfcService.isAvailable();
  }

  Future<NfcWriteResult> writeSmartPonicTag({
    required Map<String, dynamic> configPayload,
    required String securityKey,
    required String aesKey,
  }) async {
    return NfcService.writeSmartPonicTag(
      configPayload: configPayload,
      securityKey: securityKey,
      aesKey: aesKey,
    );
  }

  Future<NfcWriteResult> prepareDirectPhoneTap({
    required Map<String, dynamic> configPayload,
    required String securityKey,
    required String aesKey,
  }) async {
    return NfcService.prepareDirectPhoneTap(
      configPayload: configPayload,
      securityKey: securityKey,
      aesKey: aesKey,
    );
  }

  Future<void> stopDirectPhoneTap() async {
    await NfcService.stopDirectPhoneTap();
  }

  String encrypt(String input, String key) {
    return _encryptionService.encrypt(input, key);
  }

  String decrypt(String input, String key) {
    return _encryptionService.decrypt(input, key) ?? input;
  }
}