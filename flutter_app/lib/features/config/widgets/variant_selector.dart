import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

import '../../../utils/config_validator.dart';
import '../../../widgets/app_theme.dart';
import '../../../widgets/custom_ui.dart';

/// ESP32 variant selector with two toggle buttons (30-Pin / 38-Pin).
class VariantSelector extends StatelessWidget {
  final Esp32Variant selected;
  final ValueChanged<Esp32Variant> onChanged;

  const VariantSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StitchPanel(
      color: StitchColors.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StitchSectionLabel('ESP32 Variant'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _VariantButton(
                  label: '30-Pin (WiFi)',
                  icon: Icons.wifi_rounded,
                  isSelected: selected == Esp32Variant.esp32Node30Pin,
                  onTap: () => onChanged(Esp32Variant.esp32Node30Pin),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _VariantButton(
                  label: '38-Pin (NFC)',
                  icon: Icons.nfc_rounded,
                  isSelected: selected == Esp32Variant.esp32Node38Pin,
                  onTap: () => onChanged(Esp32Variant.esp32Node38Pin),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            selected == Esp32Variant.esp32Node30Pin
                ? 'Uses WiFi AP for configuration'
                : 'Uses NFC tag for configuration',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: StitchColors.secondaryContainer,
                ),
          ),
        ],
      ),
    );
  }
}

class _VariantButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _VariantButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StitchBounce(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? StitchColors.surfaceContainer
              : StitchColors.surfaceLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? StitchColors.primaryContainer
                : StitchColors.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: StitchColors.primaryContainer.withValues(alpha: 0.15),
                    blurRadius: 8,
                    spreadRadius: 0,
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? StitchColors.primaryContainer
                  : StitchColors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: AutoSizeText(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? StitchColors.primaryContainer
                      : StitchColors.onSurfaceVariant,
                ),
                maxLines: 1,
                minFontSize: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
