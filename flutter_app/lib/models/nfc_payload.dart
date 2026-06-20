import 'dart:typed_data';

/// Payload for NFC configuration operations.
class NfcPayload {
  final Map<String, dynamic> configWithMetadata;
  final String securityKey;
  final String aesKey;
  final Uint8List encryptedBytes;

  const NfcPayload({
    required this.configWithMetadata,
    required this.securityKey,
    required this.aesKey,
    required this.encryptedBytes,
  });

  int get byteLength => encryptedBytes.length;

  @override
  String toString() =>
      'NfcPayload(bytes: $byteLength, securityKey: ${securityKey.length} chars)';
}
