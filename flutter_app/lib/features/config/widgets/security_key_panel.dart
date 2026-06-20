import 'package:flutter/material.dart';

import '../../../widgets/app_theme.dart';
import '../../../widgets/custom_ui.dart';

/// Security key and NFC AES key input fields.
class SecurityKeyPanel extends StatelessWidget {
  final String securityKey;
  final String aesKey;
  final bool isKeyVisible;
  final ValueChanged<String> onSecurityKeyChanged;
  final ValueChanged<String> onAesKeyChanged;
  final VoidCallback onToggleVisibility;

  const SecurityKeyPanel({
    super.key,
    required this.securityKey,
    required this.aesKey,
    required this.isKeyVisible,
    required this.onSecurityKeyChanged,
    required this.onAesKeyChanged,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    return StitchPanel(
      color: StitchColors.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StitchSectionLabel('Security Key'),
          const SizedBox(height: 16),
          TextField(
            onChanged: onSecurityKeyChanged,
            controller: TextEditingController.fromValue(
              TextEditingValue(text: securityKey),
            ),
            obscureText: !isKeyVisible,
            style: const TextStyle(
              color: StitchColors.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
            decoration: InputDecoration(
              hintText: 'Enter secure node key',
              prefixIcon: const Icon(
                Icons.lock_outline_rounded,
                color: StitchColors.secondary,
              ),
              suffixIcon: IconButton(
                onPressed: onToggleVisibility,
                icon: Icon(
                  isKeyVisible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Required for node load/deploy. The ESP32 now checks this key before exposing config access.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: onAesKeyChanged,
            controller: TextEditingController.fromValue(
              TextEditingValue(text: aesKey),
            ),
            obscureText: !isKeyVisible,
            maxLength: 16,
            style: const TextStyle(
              color: StitchColors.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
            decoration: const InputDecoration(
              counterText: '',
              labelText: 'NFC AES Key',
              hintText: '16 characters',
              prefixIcon: Icon(
                Icons.enhanced_encryption_outlined,
                color: StitchColors.secondary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Used only for NFC payload encryption. Keep it the same as the AES key stored on the node.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
