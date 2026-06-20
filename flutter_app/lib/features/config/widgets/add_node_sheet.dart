import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

import '../../../utils/config_validator.dart';
import '../../../widgets/app_theme.dart';
import '../../../widgets/custom_ui.dart';

/// Bottom sheet for adding a new sensor node to the configuration.
class AddNodeSheet extends StatefulWidget {
  final List<Map<String, dynamic>> existingConfig;

  const AddNodeSheet({super.key, required this.existingConfig});

  @override
  State<AddNodeSheet> createState() => _AddNodeSheetState();
}

class _AddNodeSheetState extends State<AddNodeSheet> {
  final TextEditingController _relayLabelController = TextEditingController();
  String _selectedSensor = 'pH';
  int? _selectedPin;

  @override
  void dispose() {
    _relayLabelController.dispose();
    super.dispose();
  }

  String get _requiredType =>
      ConfigValidator.sensorRequirements[_selectedSensor]!;

  bool get _isRelay => _selectedSensor == 'Relay';

  List<int> get _availablePins {
    final usedPins = widget.existingConfig.map((e) => e['pin'] as int).toSet();
    return ConfigValidator.pinGroups[_requiredType]!
        .where((pin) => !usedPins.contains(pin))
        .toList();
  }

  IconData _componentIcon(String component) =>
      ConfigValidator.componentIcon(component);

  Future<T?> _showPickerSheet<T>({
    required BuildContext context,
    required String title,
    required List<T> values,
    required T? selectedValue,
    required String Function(T value) labelBuilder,
    required IconData Function(T value) iconBuilder,
  }) async {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: StitchColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: StitchColors.outlineVariant.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(title,
                    style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: values.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final value = values[index];
                      final selected = value == selectedValue;
                      return Material(
                        color: selected
                            ? StitchColors.primaryContainer.withValues(alpha: 0.10)
                            : StitchColors.surfaceLow,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(sheetContext, value),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  iconBuilder(value),
                                  color: selected
                                      ? StitchColors.primaryContainer
                                      : StitchColors.secondary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    labelBuilder(value),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(color: StitchColors.primary),
                                  ),
                                ),
                                if (selected)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: StitchColors.primaryContainer,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final availablePins = _availablePins;
    final selectedPin = availablePins.contains(_selectedPin)
        ? _selectedPin
        : (availablePins.isNotEmpty ? availablePins.first : null);
    final relayLabel = _relayLabelController.text.trim();

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: StitchColors.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const StitchSectionLabel('Add Node'),
            const SizedBox(height: 6),
            Text(
              'Choose the component type first, then map it to a valid GPIO pin.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _SelectionField<String>(
              label: 'Component Type',
              icon: _componentIcon(_selectedSensor),
              valueLabel: _selectedSensor,
              enabled: true,
              onTap: () async {
                final value = await _showPickerSheet<String>(
                  context: context,
                  title: 'Select Component Type',
                  values: ConfigValidator.sensorRequirements.keys.toList(),
                  selectedValue: _selectedSensor,
                  labelBuilder: (sensor) => sensor,
                  iconBuilder: _componentIcon,
                );
                if (value == null || !mounted) return;
                final defaultPin = ConfigValidator.defaultSensorPins[value];
                setState(() {
                  _selectedSensor = value;
                  _selectedPin = defaultPin;
                  if (_selectedSensor != 'Relay') {
                    _relayLabelController.clear();
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            _SelectionField<int>(
              label: 'GPIO Pin ($_requiredType)',
              icon: Icons.settings_input_component,
              valueLabel: selectedPin == null
                  ? 'Select a GPIO pin'
                  : 'GPIO $selectedPin',
              enabled: availablePins.isNotEmpty,
              onTap: availablePins.isEmpty
                  ? null
                  : () async {
                      final value = await _showPickerSheet<int>(
                        context: context,
                        title: 'Select GPIO Pin',
                        values: availablePins,
                        selectedValue: selectedPin,
                        labelBuilder: (pin) => 'GPIO $pin',
                        iconBuilder: (pin) => Icons.memory_rounded,
                      );
                      if (value == null || !mounted) return;
                      setState(() {
                        _selectedPin = value;
                      });
                    },
            ),
            if (_isRelay) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _relayLabelController,
                onChanged: (_) {
                  if (mounted) setState(() {});
                },
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Relay Role',
                  hintText: 'Valve, Water Pump, Aerator...',
                  prefixIcon: Icon(Icons.label_outline_rounded),
                ),
              ),
            ],
            const SizedBox(height: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: StitchColors.surfaceLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: availablePins.isEmpty
                      ? StitchColors.error
                      : StitchColors.outlineVariant,
                ),
              ),
              child: Text(
                availablePins.isEmpty
                    ? 'No available pins left for $_requiredType.'
                    : _isRelay
                        ? 'Required signal type: $_requiredType  |  Name this relay so the node knows what it controls.'
                        : 'Required signal type: $_requiredType  |  ${availablePins.length} pin(s) available',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: availablePins.isEmpty
                      ? StitchColors.error
                      : StitchColors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: StitchGhostButton(
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      Navigator.pop(context);
                    },
                    child: const Text('CANCEL'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StitchPrimaryButton(
                    onPressed:
                        selectedPin == null || (_isRelay && relayLabel.isEmpty)
                            ? null
                            : () {
                                final item = <String, dynamic>{
                                  'pin': selectedPin,
                                  'sensor': _selectedSensor,
                                  'type': _requiredType,
                                };
                                if (_isRelay) {
                                  item['label'] = relayLabel;
                                }
                                FocusManager.instance.primaryFocus?.unfocus();
                                Navigator.pop(context, item);
                              },
                    child: const Center(
                      child: Text(
                        'ADD NODE',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: StitchColors.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionField<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final String valueLabel;
  final bool enabled;
  final VoidCallback? onTap;

  const _SelectionField({
    required this.label,
    required this.icon,
    required this.valueLabel,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? onTap : null,
        child: Ink(
          decoration: BoxDecoration(
            color: StitchColors.surfaceLowest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: StitchColors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: enabled
                      ? StitchColors.secondary
                      : StitchColors.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AutoSizeText(
                        label,
                        style: Theme.of(context).textTheme.labelMedium,
                        maxLines: 1,
                        minFontSize: 9,
                      ),
                      const SizedBox(height: 6),
                      AutoSizeText(
                        valueLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              color: enabled
                                  ? StitchColors.primary
                                  : StitchColors.onSurfaceVariant,
                            ),
                        minFontSize: 10,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: enabled
                      ? StitchColors.secondary
                      : StitchColors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
