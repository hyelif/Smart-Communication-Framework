import 'package:flutter/material.dart';

void showAddSensorSheet({
  required BuildContext context,
  required List<Map<String, dynamic>> config,
  required Map<int, List<String>> pinCapabilities,
  required Map<String, String> sensorRequirements,
  required Function(Map<String, dynamic>) onSave,
}) {
  String selectedSensor = 'pH';
  int? selectedPin;

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF161B22),
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setStateModal) {
        final req = sensorRequirements[selectedSensor]!;

        final pins = pinCapabilities.keys.where((p) {
          return pinCapabilities[p]!.contains(req) &&
              !config.any((c) => c['pin'] == p);
        }).toList()
          ..sort();

        if (selectedPin == null || !pins.contains(selectedPin)) {
          selectedPin = pins.isNotEmpty ? pins.first : null;
        }

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedSensor,
                items: sensorRequirements.keys
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setStateModal(() => selectedSensor = v!),
              ),
              DropdownButtonFormField<int>(
                initialValue: selectedPin,
                items: pins
                    .map(
                      (p) => DropdownMenuItem(
                        value: p,
                        child: Text('GPIO $p'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setStateModal(() => selectedPin = v),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: selectedPin == null
                    ? null
                    : () {
                        onSave({
                          'pin': selectedPin,
                          'sensor': selectedSensor,
                          'type': req,
                        });
                        Navigator.pop(context);
                      },
                child: const Text('CONFIRM'),
              ),
            ],
          ),
        );
      },
    ),
  );
}
