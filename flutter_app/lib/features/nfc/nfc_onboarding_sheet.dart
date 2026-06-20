import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/nfc_payload_service.dart';
import '../../services/nfc_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/custom_ui.dart';
import 'nfc_animation.dart';

/// NFC deployment onboarding sheet with progress tracking.
class NfcOnboardingSheet extends StatefulWidget {
  final ValueListenable<List<Map<String, dynamic>>> configNotifier;
  final String securityKey;
  final String aesKey;
  final VoidCallback onComplete;
  final Function(String) onError;

  const NfcOnboardingSheet({
    super.key,
    required this.configNotifier,
    required this.securityKey,
    required this.aesKey,
    required this.onComplete,
    required this.onError,
  });

  @override
  State<NfcOnboardingSheet> createState() => _NfcOnboardingSheetState();
}

class _NfcOnboardingSheetState extends State<NfcOnboardingSheet> {
  bool _isLoading = false;
  int _progressPercent = 0;
  String _loadingMessage = '';
  String? _errorMessage;

  static const int stagePreparing = 10;
  static const int stageSaving = 30;
  static const int stageNfcReady = 50;
  static const int stageWaitingTap = 70;
  static const int stageVerifying = 90;
  static const int stageComplete = 100;

  Future<void> _startNfcTransfer() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isLoading = true;
      _progressPercent = stagePreparing;
      _loadingMessage = 'Preparing NFC configuration...';
      _errorMessage = null;
    });

    try {
      final isSupported = await NfcService.isDirectTapSupported();
      if (!isSupported) {
        setState(() {
          _errorMessage = 'NFC HCE not supported. Enable NFC in phone settings.';
          _progressPercent = 0;
          _isLoading = false;
        });
        widget.onError(
            'NFC HCE not supported. Enable NFC in phone settings and ensure phone supports HCE. Try "Write NFC Tag" instead.');
        return;
      }

      final config = widget.configNotifier.value;
      if (config.isEmpty) {
        setState(() {
          _errorMessage = 'No configuration to deploy.';
          _progressPercent = 0;
          _isLoading = false;
        });
        widget.onError('No configuration to deploy. Add sensor nodes first.');
        return;
      }

      final configPayload = <String, dynamic>{
        'config': config,
        'latitude': 0.0,
        'longitude': 0.0,
        'keys': {
          'aes128': widget.aesKey,
          'auth': NfcPayloadService.defaultAuthKey,
        },
      };

      setState(() {
        _progressPercent = stageSaving;
        _loadingMessage = 'Saving configuration locally...';
      });
      await StorageService.saveConfig(config, widget.securityKey);

      setState(() {
        _progressPercent = stageNfcReady;
        _loadingMessage = 'Phone NFC ready. Tap to PN532 now!';
      });
      await NfcService.prepareDirectPhoneTap(
        configPayload: configPayload,
        securityKey: widget.securityKey,
        aesKey: widget.aesKey,
      );

      setState(() {
        _progressPercent = stageWaitingTap;
        _loadingMessage = 'Waiting for NFC tap...';
      });
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Tap Phone to PN532'),
          content: const Text(
            'Your phone NFC is ready.\n\n'
            '1. Hold your phone near the PN532 module on the ESP32\n'
            '2. Wait for the ESP32 to process (LED may blink)\n'
            '3. Click "DONE" ONLY after ESP32 confirms receipt\n\n'
            'The ESP32 will confirm via its status LED.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('DONE'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (confirmed != true) {
        await NfcService.stopDirectPhoneTap();
        setState(() {
          _errorMessage = 'NFC deploy cancelled by user.';
          _progressPercent = 0;
          _isLoading = false;
        });
        widget.onError('NFC deploy cancelled.');
        return;
      }

      setState(() {
        _progressPercent = stageVerifying;
        _loadingMessage = 'Verifying with ESP32...';
      });

      bool success = false;
      String errorMsg = '';

      for (int attempt = 0; attempt < 5; attempt++) {
        if (!mounted) return;
        setState(() {
          _loadingMessage = 'Verifying with ESP32... (${attempt + 1}/5)';
        });
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;

        try {
          final healthResult = await ApiService.fetchHealth();
          if (healthResult['ok'] == true) {
            success = true;
            break;
          }
          errorMsg = 'ESP32 not responding';
        } catch (e) {
          errorMsg = 'Cannot connect to ESP32: ${e.toString()}';
        }
      }

      await NfcService.stopDirectPhoneTap();

      if (!mounted) return;

      if (success) {
        setState(() {
          _progressPercent = stageComplete;
          _loadingMessage = 'NFC configuration deployed successfully!';
        });
        widget.onComplete();
      } else {
        final failureReason =
            errorMsg.isNotEmpty ? errorMsg : 'ESP32 did not acknowledge';
        setState(() {
          _errorMessage =
              'FAILED: $failureReason\nDid you tap the phone to PN532?';
          _progressPercent = stageVerifying;
          _isLoading = false;
        });
        widget.onError(
            'ESP32 did not acknowledge config. $failureReason. Make sure the phone was tapped to PN532 and try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _progressPercent = 0;
        _isLoading = false;
      });
      widget.onError('NFC transfer failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: StitchColors.surfaceLowest,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: StitchColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "NFC DEPLOYMENT",
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
            ),
            const SizedBox(height: 24),
            NfcAnimatedTelemetry(
              isError: _errorMessage != null,
              isComplete: _progressPercent == 100,
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: StitchColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: StitchColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: StitchColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
            ],
            Text(
              _isLoading || _errorMessage != null
                  ? _loadingMessage
                  : "Hold the back of your phone near the PN532 telemetry receiver module on the ESP32.",
              style: TextStyle(
                fontSize: 13,
                color: _errorMessage != null
                    ? StitchColors.error
                    : StitchColors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_isLoading || _errorMessage != null) ...[
              if (_errorMessage != null)
                SizedBox(
                  width: double.infinity,
                  child: StitchPrimaryButton(
                    onPressed: _startNfcTransfer,
                    child: const Text('RETRY DEPLOY'),
                  ),
                )
              else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progressPercent / 100,
                    minHeight: 8,
                    color: StitchColors.primaryContainer,
                    backgroundColor: StitchColors.surfaceLow,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '$_progressPercent% COMPLETE',
                  style: const TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: StitchColors.primaryContainer,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ] else
              SizedBox(
                width: double.infinity,
                child: StitchPrimaryButton(
                  onPressed: _startNfcTransfer,
                  child: const Text('START CONFIG TRANSFER'),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: StitchGhostButton(
                onPressed: () {
                  NfcService.stopDirectPhoneTap();
                  Navigator.pop(context);
                },
                child: const Text('CANCEL'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
