import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/stream/ctr.dart';

class EncryptionService {
  /// AES-128 block size in bytes.
  static const int AES_BLOCK_SIZE = 16;

  /// AES-128-CTR encrypt a plaintext string.
  /// Returns base64(IV + ciphertext).
  String encrypt(String input, String key) {
    final normalizedKey = _normalizeKey(key);
    final plaintext = Uint8List.fromList(utf8.encode(input));
    final iv = _secureRandomBytes(AES_BLOCK_SIZE);
    final ciphertext = _aesCtr(plaintext, normalizedKey, iv);
    final combined = Uint8List.fromList([...iv, ...ciphertext]);
    return base64Encode(combined);
  }

  /// AES-128-CTR decrypt a base64(IV + ciphertext) string.
  /// Returns the original plaintext, or null on failure.
  String? decrypt(String input, String key) {
    if (input.isEmpty) return null;
    try {
      final normalizedKey = _normalizeKey(key);
      final combined = base64Decode(input);
      if (combined.length < AES_BLOCK_SIZE) return null;
      final iv = combined.sublist(0, AES_BLOCK_SIZE);
      final ciphertext = combined.sublist(AES_BLOCK_SIZE);
      final plaintext = _aesCtr(ciphertext, normalizedKey, iv);
      return utf8.decode(plaintext);
    } on FormatException catch (e) {
      dev.log('Decryption failed: invalid base64 input', error: e);
      return null;
    } on ArgumentError catch (e) {
      dev.log('Decryption failed: invalid argument', error: e);
      return null;
    } catch (e) {
      dev.log('Decryption failed: unexpected error', error: e);
      return null;
    }
  }

  /// Normalize a key string to exactly [AES_BLOCK_SIZE] bytes for AES-128.
  ///
  /// Uses the first [AES_BLOCK_SIZE] bytes of the UTF-8 encoding directly,
  /// avoiding a lossy bytes-to-string-to-bytes round-trip that could split
  /// multi-byte characters. If the key is shorter than [AES_BLOCK_SIZE] bytes,
  /// the remaining bytes are zero-padded.
  Uint8List _normalizeKey(String value) {
    final bytes = utf8.encode(value);
    final result = Uint8List(AES_BLOCK_SIZE);
    final len = bytes.length < AES_BLOCK_SIZE ? bytes.length : AES_BLOCK_SIZE;
    result.setRange(0, len, bytes);
    return result;
  }

  static Uint8List _aesCtr(Uint8List data, Uint8List key, Uint8List iv) {
    final cipher = CTRStreamCipher(AESEngine())
      ..init(
        true,
        ParametersWithIV<KeyParameter>(
          KeyParameter(key),
          iv,
        ),
      );
    return cipher.process(data);
  }

  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    final result = Uint8List(length);
    for (int i = 0; i < length; i++) {
      result[i] = random.nextInt(256);
    }
    return result;
  }
}
