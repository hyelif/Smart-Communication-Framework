import 'package:flutter_test/flutter_test.dart';
import 'package:smartponic_v2/services/encryption_service.dart';

void main() {
  late EncryptionService service;

  setUp(() {
    service = EncryptionService();
  });

  group('EncryptionService', () {
    group('encrypt/decrypt round-trip', () {
      test('round-trip with a valid 16-byte key', () {
        const key = '1234567890123456'; // exactly 16 chars
        const plaintext = 'Hello, SmartPonic!';
        final encrypted = service.encrypt(plaintext, key);
        expect(encrypted, isNotEmpty);
        final decrypted = service.decrypt(encrypted, key);
        expect(decrypted, equals(plaintext));
      });

      test('round-trip with a short key (padded with zeros)', () {
        const key = 'short'; // less than 16 bytes
        const plaintext = 'Test message with short key';
        final encrypted = service.encrypt(plaintext, key);
        expect(encrypted, isNotEmpty);
        final decrypted = service.decrypt(encrypted, key);
        expect(decrypted, equals(plaintext));
      });

      test('round-trip with a long key (trimmed to 16 bytes)', () {
        const key = 'this is a very long key that exceeds sixteen bytes';
        const plaintext = 'Long key test';
        final encrypted = service.encrypt(plaintext, key);
        expect(encrypted, isNotEmpty);
        final decrypted = service.decrypt(encrypted, key);
        expect(decrypted, equals(plaintext));
      });

      test('round-trip with empty string input', () {
        const key = '1234567890123456';
        const plaintext = '';
        final encrypted = service.encrypt(plaintext, key);
        expect(encrypted, isEmpty);
        final decrypted = service.decrypt(encrypted, key);
        expect(decrypted, isEmpty);
      });

      test('round-trip with special characters', () {
        const key = 'aB3#xY9!zQ1@pW7*';
        const plaintext = 'Special: !@#\$%^&*()_+{}[]|;:,.<>?/~`';
        final encrypted = service.encrypt(plaintext, key);
        expect(encrypted, isNotEmpty);
        final decrypted = service.decrypt(encrypted, key);
        expect(decrypted, equals(plaintext));
      });

      test('round-trip with unicode characters', () {
        const key = '1234567890123456';
        const plaintext = 'Unicode: ñoño 中文 русский 日本語';
        final encrypted = service.encrypt(plaintext, key);
        expect(encrypted, isNotEmpty);
        final decrypted = service.decrypt(encrypted, key);
        expect(decrypted, equals(plaintext));
      });
    });

    group('key handling', () {
      test('different keys produce different ciphertext', () {
        const key1 = '1111111111111111';
        const key2 = '2222222222222222';
        const plaintext = 'Sensitive data';
        final encrypted1 = service.encrypt(plaintext, key1);
        final encrypted2 = service.encrypt(plaintext, key2);
        expect(encrypted1, isNot(equals(encrypted2)));
      });

      test('keys that normalize to the same value produce decryptable ciphertext',
          () {
        // Both keys should normalize to the same 16-byte value
        const keyA = 'abcdefghijklmnop'; // exactly 16
        const keyB = 'abcdefghijklmnopqrstuvwxyz'; // longer, trimmed to 16
        const plaintext = 'Same key after normalization';
        final encrypted = service.encrypt(plaintext, keyA);
        final decrypted = service.decrypt(encrypted, keyB);
        expect(decrypted, equals(plaintext));
      });
    });

    group('decryption failure', () {
      test('decrypting with wrong key returns original ciphertext', () {
        const encryptKey = 'correct_key_128!';
        const decryptKey = 'wrong_key_128!!';
        const plaintext = 'Secret message';
        final encrypted = service.encrypt(plaintext, encryptKey);
        final decrypted = service.decrypt(encrypted, decryptKey);
        // decrypt returns the original input on failure
        expect(decrypted, isNot(equals(plaintext)));
        expect(decrypted, equals(encrypted));
      });

      test('decrypting invalid base64 returns original input', () {
        const key = '1234567890123456';
        const invalidInput = 'not-valid-base64!!!';
        final result = service.decrypt(invalidInput, key);
        expect(result, equals(invalidInput));
      });

      test('decrypting too-short data returns original input', () {
        const key = '1234567890123456';
        const shortInput = 'short'; // less than 16 bytes after base64 decode
        final result = service.decrypt(shortInput, key);
        expect(result, equals(shortInput));
      });
    });

    group('IV randomness', () {
      test('same plaintext produces different ciphertext each time', () {
        const key = '1234567890123456';
        const plaintext = 'Same text every time';
        final results = <String>{};
        for (var i = 0; i < 5; i++) {
          results.add(service.encrypt(plaintext, key));
        }
        // Each encryption should produce a unique output due to random IV
        expect(results.length, equals(5));
      });
    });
  });
}
