import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/stream/ctr.dart';

class NfcPayloadService {
  NfcPayloadService._(); // Private constructor to prevent instantiation.

  // ---------------------------------------------------------------------------
  // Named constants
  // ---------------------------------------------------------------------------

  /// AES IV length in bytes (128-bit).
  static const int aesIvLength = 16;

  /// AES key length in bytes (128-bit).
  static const int aesKeyLength = 16;

  /// Development default AES key -- only used when no key is configured.
  /// In production, always set a unique key per node.
  static const String _defaultAesKey = 'SmartPonic123456';
  static const String defaultAuthKey = 'AQUA77';
  static const String mimeType = 'application/x-smartponic';
  static const int minLongNdefPayloadLength = 256;
  static const int maxDirectHcePayloadLength = 2048;

  static Uint8List buildEncryptedPayload({
    required Map<String, dynamic> configPayload,
    required String aesKey,
  }) {
    final normalizedKey = _normalizeAesKey(aesKey);
    final jsonPayload = _jsonForFirmware(configPayload);
    final plaintext = Uint8List.fromList(utf8.encode(jsonPayload));
    final iv = _secureRandomBytes(aesIvLength);
    final ciphertext = _aesCtr(plaintext, normalizedKey, iv);

    return Uint8List.fromList([...iv, ...ciphertext]);
  }

  static Map<String, dynamic> withFirmwareFields({
    required Map<String, dynamic> configPayload,
    required String securityKey,
    required String aesKey,
    String authKey = defaultAuthKey,
  }) {
    final payload = Map<String, dynamic>.from(configPayload);
    payload['securityKey'] = securityKey;
    payload['keys'] = {'aes128': _normalizeAesKey(aesKey), 'auth': authKey};

    return _padForLongNdef(payload);
  }

  static String validateAesKey(String value) {
    if (value.trim().isEmpty) return _defaultAesKey;
    return _normalizeAesKey(value);
  }

  static String _jsonForFirmware(Map<String, dynamic> payload) {
    return jsonEncode(payload);
  }

  static Map<String, dynamic> _padForLongNdef(Map<String, dynamic> payload) {
    final padded = Map<String, dynamic>.from(payload);
    var padLength = 0;

    while (utf8.encode(jsonEncode(padded)).length + aesIvLength <
        minLongNdefPayloadLength) {
      padLength += aesIvLength;
      padded['_pad'] = '0' * padLength;
    }

    return padded;
  }

  static String _normalizeAesKey(String value) {
    final key = value.trim();
    if (key.length != aesKeyLength) {
      throw FormatException(
        'NFC AES key must be exactly $aesKeyLength characters.',
      );
    }
    return key;
  }

  static Uint8List _aesCtr(Uint8List data, String key, Uint8List iv) {
    final cipher = CTRStreamCipher(AESEngine())
      ..init(
        true,
        ParametersWithIV<KeyParameter>(
          KeyParameter(Uint8List.fromList(utf8.encode(key))),
          iv,
        ),
      );
    return cipher.process(data);
  }

  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
