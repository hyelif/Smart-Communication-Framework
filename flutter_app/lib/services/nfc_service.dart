import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:ndef_record/ndef_record.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

import 'nfc_payload_service.dart';

typedef NfcDiscoveredCallback = void Function(Map<String, dynamic> data);

class NfcWriteResult {
  final int bytesWritten;
  final int ndefBytes;

  const NfcWriteResult({required this.bytesWritten, required this.ndefBytes});
}

class NfcService {
  static const MethodChannel _hceChannel = MethodChannel('smartponic/hce');
  static const MethodChannel _nfcDispatchChannel = MethodChannel('smartponic/nfc_dispatch');

  static NfcDiscoveredCallback? _onNfcDiscovered;

  static void initNfcDispatch({NfcDiscoveredCallback? onDiscovered}) {
    _onNfcDiscovered = onDiscovered;
    _nfcDispatchChannel.setMethodCallHandler((call) async {
      if (call.method == 'onNfcDiscovered') {
        final args = call.arguments as Map<String, dynamic>?;
        if (args != null && _onNfcDiscovered != null) {
          _onNfcDiscovered!(args);
        }
      }
    });
  }

  static Future<bool> isAvailable() async {
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      return false;
    }
    try {
      final availability = await NfcManager.instance.checkAvailability();
      return availability == NfcAvailability.enabled;
    } on Object {
      return false;
    }
  }

  static Future<bool> isDirectTapSupported() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      return await _hceChannel.invokeMethod<bool>('isSupported') ?? false;
    } on Object {
      return false;
    }
  }

  static Future<NfcWriteResult> prepareDirectPhoneTap({
    required Map<String, dynamic> configPayload,
    required String securityKey,
    required String aesKey,
    Duration activeFor = const Duration(minutes: 2),
  }) async {
    if (!await isDirectTapSupported()) {
      throw const NfcException(
        'Direct phone-to-PN532 deploy needs Android NFC HCE support.',
      );
    }

    final firmwarePayload = NfcPayloadService.withFirmwareFields(
      configPayload: configPayload,
      securityKey: securityKey,
      aesKey: aesKey,
    );
    final encryptedPayload = NfcPayloadService.buildEncryptedPayload(
      configPayload: firmwarePayload,
      aesKey: aesKey,
    );
    if (encryptedPayload.length > NfcPayloadService.maxDirectHcePayloadLength) {
      throw NfcException(
        'Direct NFC config is ${encryptedPayload.length} bytes; max is ${NfcPayloadService.maxDirectHcePayloadLength} bytes.',
      );
    }

    await _hceChannel.invokeMethod<bool>('setPayload', {
      'payload': encryptedPayload,
      'ttlSeconds': activeFor.inSeconds,
    });

    return NfcWriteResult(
      bytesWritten: encryptedPayload.length,
      ndefBytes: encryptedPayload.length,
    );
  }

  static Future<void> stopDirectPhoneTap() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _hceChannel.invokeMethod<bool>('clearPayload');
  }

  static Future<NfcWriteResult> writeSmartPonicTag({
    required Map<String, dynamic> configPayload,
    required String securityKey,
    required String aesKey,
  }) async {
    if (!await isAvailable()) {
      throw const NfcException(
        'NFC is not available. Enable NFC or use Wi-Fi deploy.',
      );
    }

    final firmwarePayload = NfcPayloadService.withFirmwareFields(
      configPayload: configPayload,
      securityKey: securityKey,
      aesKey: aesKey,
    );
    final encryptedPayload = NfcPayloadService.buildEncryptedPayload(
      configPayload: firmwarePayload,
      aesKey: aesKey,
    );
    final message = _buildMessage(encryptedPayload);
    final completer = Completer<NfcWriteResult>();

    await NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443},
      alertMessageIos: 'Hold your phone near the SmartPonic NFC tag.',
      onDiscovered: (tag) async {
        try {
          await _writeMessage(tag, message);
          await NfcManager.instance.stopSession(
            alertMessageIos: 'SmartPonic config written.',
          );
          if (!completer.isCompleted) {
            completer.complete(
              NfcWriteResult(
                bytesWritten: encryptedPayload.length,
                ndefBytes: message.byteLength,
              ),
            );
          }
        } catch (error, stackTrace) {
          await NfcManager.instance.stopSession(
            errorMessageIos: 'NFC write failed.',
          );
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        }
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () async {
        await NfcManager.instance.stopSession(
          errorMessageIos: 'NFC write timed out.',
        );
        throw TimeoutException('NFC write timed out.');
      },
    );
  }

  static NdefMessage _buildMessage(Uint8List encryptedPayload) {
    final aarPayload = Uint8List.fromList(utf8.encode('com.example.smartponic_v2'));
    final aarRecord = NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: Uint8List.fromList([0x61]),
      identifier: Uint8List(0),
      payload: aarPayload,
    );

    return NdefMessage(
      records: [
        NdefRecord(
          typeNameFormat: TypeNameFormat.media,
          type: Uint8List.fromList(utf8Bytes(NfcPayloadService.mimeType)),
          identifier: Uint8List(0),
          payload: encryptedPayload,
        ),
        aarRecord,
      ],
    );
  }

  static Future<void> _writeMessage(NfcTag tag, NdefMessage message) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final ndef = NdefAndroid.from(tag);
      if (ndef == null) {
        throw const NfcException('This tag is not NDEF compatible.');
      }
      if (!ndef.isWritable) {
        throw const NfcException('This NFC tag is read-only.');
      }
      if (message.byteLength > ndef.maxSize) {
        throw NfcException(
          'Config is ${message.byteLength} bytes but this tag only holds ${ndef.maxSize} bytes.',
        );
      }
      await ndef.writeNdefMessage(message);
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ndef = NdefIos.from(tag);
      if (ndef == null) {
        throw const NfcException('This tag is not NDEF compatible.');
      }
      final status = await ndef.queryNdefStatus();
      if (status.status != NdefStatusIos.readWrite) {
        throw const NfcException('This NFC tag is not writable.');
      }
      if (message.byteLength > status.capacity) {
        throw NfcException(
          'Config is ${message.byteLength} bytes but this tag only holds ${status.capacity} bytes.',
        );
      }
      await ndef.writeNdef(message);
      return;
    }

    throw const NfcException(
      'NFC writing is only supported on Android and iOS.',
    );
  }

  static List<int> utf8Bytes(String value) {
    return Uint8List.fromList(value.codeUnits);
  }
}

class NfcException implements Exception {
  final String message;

  const NfcException(this.message);

  @override
  String toString() => message;
}