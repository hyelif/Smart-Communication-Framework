import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/custom_ui.dart';

class ConfigScreen extends StatefulWidget {
  final ValueNotifier<List<Map<String, dynamic>>> configNotifier;

  const ConfigScreen({super.key, required this.configNotifier});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final TextEditingController _keyController = TextEditingController();
  bool _isKeyVisible = false;
  bool _isDeploying = false;
  bool _isLoadingNode = false;

  static const Map<String, List<int>> pinGroups = {
    'AI': [32, 33, 34, 35, 36, 39],
    'AO': [25, 26],
    'DO': [16, 17, 21, 22, 25, 26, 27, 32, 33],
    'DI': [16, 17, 21, 22, 25, 26, 27, 32, 33, 34, 35, 36, 39],
  };

  static const Map<String, String> sensorRequirements = {
    'pH': 'AI',
    'TDS': 'AI',
    'Turbidity': 'AI',
    'DHT22': 'DI',
    'WaterTemp': 'DI',
  };

  @override
  void initState() {
    super.initState();
    _loadStoredDraft();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadStoredDraft() async {
    final stored = await StorageService.loadConfig();
    final key = stored['key'] as String?;
    if (key != null && mounted) {
      _keyController.text = key;
    }
  }

  Future<void> _saveSnapshot() async {
    await StorageService.saveConfig(
      widget.configNotifier.value,
      _keyController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Architect draft saved locally.')),
    );
  }

  Future<void> _loadFromNode() async {
    setState(() => _isLoadingNode = true);

    try {
      final result = await ApiService.fetchConfig();

      if (!mounted) return;

      if (result['ok'] == true) {
        final data = result['data'];
        if (data is Map<String, dynamic> && data['config'] is List) {
          final loaded = List<Map<String, dynamic>>.from(data['config'] as List);
          widget.configNotifier.value = loaded;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Loaded config from ESP32.')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ESP32 returned invalid config format.')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Load failed. Status: ${result['statusCode']}'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot reach ESP32. Connect phone to AQUA_NODE Wi-Fi first. Error: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingNode = false);
      }
    }
  }

  Future<void> _deployToNode() async {
    if (widget.configNotifier.value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one sensor node first.')),
      );
      return;
    }

    setState(() => _isDeploying = true);

    try {
      await StorageService.saveConfig(
        widget.configNotifier.value,
        _keyController.text.trim(),
      );

      final result = await ApiService.sendConfig(widget.configNotifier.value);

      if (!mounted) return;

      if (result['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Config deployed to ESP32 successfully.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deploy failed. Status: ${result['statusCode']}'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot reach ESP32. Connect phone to AQUA_NODE Wi-Fi first. Error: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeploying = false);
      }
    }
  }

  void _removeNode(int index) {
    final updated = List<Map<String, dynamic>>.from(widget.configNotifier.value);
    updated.removeAt(index);
    widget.configNotifier.value = updated;
  }

  Future<void> _showAddNodeSheet() async {
    String selectedSensor = 'pH';
    int? selectedPin;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: StitchColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final requiredType = sensorRequirements[selectedSensor]!;
            final usedPins = widget.configNotifier.value
                .map((e) => e['pin'] as int)
                .toSet();

            final availablePins = pinGroups[requiredType]!
                .where((pin) => !usedPins.contains(pin))
                .toList();

            if (selectedPin == null || !availablePins.contains(selectedPin)) {
              selectedPin = availablePins.isNotEmpty ? availablePins.first : null;
            }

            return Padding(
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
                  const StitchSectionLabel('Add Node'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSensor,
                    dropdownColor: StitchColors.surfaceHigh,
                    decoration: const InputDecoration(
                      labelText: 'Sensor Type',
                      prefixIcon: Icon(Icons.sensors_outlined),
                    ),
                    items: sensorRequirements.keys
                        .map(
                          (sensor) => DropdownMenuItem(
                            value: sensor,
                            child: Text(sensor),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setModalState(() {
                        selectedSensor = value;
                        selectedPin = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: selectedPin,
                    dropdownColor: StitchColors.surfaceHigh,
                    decoration: InputDecoration(
                      labelText: 'GPIO Pin ($requiredType)',
                      prefixIcon: const Icon(Icons.settings_input_component),
                    ),
                    items: availablePins
                        .map(
                          (pin) => DropdownMenuItem(
                            value: pin,
                            child: Text('GPIO $pin'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setModalState(() {
                        selectedPin = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    availablePins.isEmpty
                        ? 'No available pins left for $requiredType.'
                        : 'Required signal type: $requiredType',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: StitchGhostButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('CANCEL'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StitchPrimaryButton(
                          onPressed: selectedPin == null
                              ? null
                              : () {
                                  final updated = List<Map<String, dynamic>>.from(
                                    widget.configNotifier.value,
                                  );

                                  updated.add({
                                    'pin': selectedPin,
                                    'sensor': selectedSensor,
                                    'type': requiredType,
                                  });

                                  widget.configNotifier.value = updated;
                                  Navigator.pop(ctx);
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
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StitchScaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppTheme.ctaGradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: AppTheme.cyanGlowShadow,
          ),
          child: FloatingActionButton.extended(
            onPressed: _isDeploying ? null : _deployToNode,
            backgroundColor: Colors.transparent,
            elevation: 0,
            label: Text(_isDeploying ? 'DEPLOYING...' : 'DEPLOY TO NODE'),
            icon: _isDeploying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: StitchColors.onSecondaryContainer,
                    ),
                  )
                : const Icon(Icons.rocket_launch_rounded),
          ),
        ),
      ),
      body: Column(
        children: [
          const StitchTopBar(section: 'Architect'),
          Expanded(
            child: ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: widget.configNotifier,
              builder: (context, config, _) {
                return RefreshIndicator(
                  onRefresh: _loadFromNode,
                  color: StitchColors.secondaryContainer,
                  backgroundColor: StitchColors.surfaceHigh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 220),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Architect',
                                    style: Theme.of(context).textTheme.displayMedium,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Build and deploy your node layout directly from this panel.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _saveSnapshot,
                            icon: const Icon(
                              Icons.bookmark_add_outlined,
                              color: StitchColors.primaryContainer,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
Column(
  children: [
    SizedBox(
      width: double.infinity,
      child: StitchGhostButton(
        onPressed: _isLoadingNode ? null : _loadFromNode,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoadingNode)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.cloud_download_outlined, size: 18),
            const SizedBox(width: 8),
            Text(_isLoadingNode ? 'LOADING...' : 'LOAD FROM NODE'),
          ],
        ),
      ),
    ),
    const SizedBox(height: 10),
    SizedBox(
      width: double.infinity,
      child: StitchGhostButton(
        onPressed: _showAddNodeSheet,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline_rounded, size: 18),
            SizedBox(width: 8),
            Text('ADD SENSOR NODE'),
          ],
        ),
      ),
    ),
  ],
),
const SizedBox(height: 24),

                      StitchPanel(
                        color: StitchColors.surfaceContainer,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const StitchSectionLabel('Security Key'),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _keyController,
                              obscureText: !_isKeyVisible,
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
                                  onPressed: () => setState(
                                    () => _isKeyVisible = !_isKeyVisible,
                                  ),
                                  icon: Icon(
                                    _isKeyVisible
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Stored with your local draft. ESP32 deploy sends config JSON to 192.168.4.1.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontSize: 12,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      StitchPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.settings_input_component_outlined,
                                  color: StitchColors.primaryContainer,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'PIN CONFIGURATION',
                                    style: TextStyle(
                                      color: StitchColors.primary,
                                      fontFamily: 'SpaceGrotesk',
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final wide = constraints.maxWidth > 640;
                                return GridView.count(
                                  crossAxisCount: wide ? 4 : 2,
                                  childAspectRatio: wide ? 2.0 : 1.3,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                  children: const [
                                    _InfoTile('ADC1 RANGE', '32, 33, 34, 35, 36, 39'),
                                    _InfoTile('DAC CHANNELS', '25, 26'),
                                    _InfoTile('DIGITAL OUT', '16, 17, 21, 22, 25, 26, 27, 32, 33'),
                                    _InfoTile('DIGITAL IN', '16, 17, 21, 22, 25, 26, 27, 32, 33, 34, 35, 36, 39'),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (config.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: StitchEmptyState(
                            title: 'No Nodes Defined',
                            subtitle:
                                'Tap "Add Sensor Node" or "Load From Node" to start building your ESP32 configuration.',
                            icon: Icons.hub_outlined,
                          ),
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth > 720;
                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: config.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: wide ? 2 : 1,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: wide ? 1.45 : 2.4,
                              ),
                              itemBuilder: (context, index) =>
                                  _buildBentoCard(context, config[index], index),
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBentoCard(
    BuildContext context,
    Map<String, dynamic> item,
    int index,
  ) {
    final icons = [
      Icons.science_outlined,
      Icons.water_drop_outlined,
      Icons.opacity_outlined,
      Icons.thermostat_rounded,
      Icons.device_thermostat_outlined,
    ];

    return StitchPanel(
      color: StitchColors.surfaceLow,
      glow: true,
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: StitchColors.primaryContainer.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'P${item['pin']}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const Spacer(),
              Icon(
                icons[index % icons.length],
                color: StitchColors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _removeNode(index),
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: StitchColors.error,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            (item['sensor']?.toString() ?? 'NODE').toUpperCase(),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 18,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'GPIO ${item['pin']}  -  ${item['type']}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: StitchColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 13,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
