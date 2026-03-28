import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/file_exchange_service.dart';
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
  bool _isRefreshingPage = false;
  bool _isImportingFile = false;
  bool _isExportingFile = false;
  Timer? _refreshTimer;

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
    _refreshPage();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        _refreshPage();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _refreshPage({bool showFeedback = false}) async {
    if (_isRefreshingPage) return;
    setState(() => _isRefreshingPage = true);
    try {
      final stored = await StorageService.loadConfig();
      final key = stored['key'] as String?;
      final raw = stored['config'] as String?;
      final parsed = raw == null || raw.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(jsonDecode(raw));

      if (!mounted) return;

      if (key != null && _keyController.text != key) {
        _keyController.text = key;
      }

      if (!_sameConfig(parsed, widget.configNotifier.value)) {
        widget.configNotifier.value = parsed;
      }

      if (showFeedback) {
        showStitchMessage(context, 'Architect page refreshed.');
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshingPage = false);
      }
    }
  }

  bool _sameConfig(
    List<Map<String, dynamic>> left,
    List<Map<String, dynamic>> right,
  ) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!mapEquals(left[i], right[i])) return false;
    }
    return true;
  }

  Future<void> _saveSnapshot() async {
    await StorageService.saveConfig(
      widget.configNotifier.value,
      _keyController.text.trim(),
    );
    if (!mounted) return;
    showStitchMessage(context, 'Architect draft saved locally.');
  }

  Future<void> _loadFromNode() async {
    setState(() => _isLoadingNode = true);

    try {
      final result = await ApiService.fetchConfig();

      if (!mounted) return;

      if (result['ok'] == true) {
        final data = result['data'];
        if (data is Map<String, dynamic> && data['config'] is List) {
          final loaded = (data['config'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          widget.configNotifier.value = loaded;

          showStitchMessage(context, 'Loaded config from ESP32.');
        } else {
          showStitchMessage(
            context,
            'ESP32 returned invalid config format.',
            isError: true,
          );
        }
      } else {
        showStitchMessage(
          context,
          'ESP32 not connected. Join the node Wi-Fi and try again.',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      showStitchMessage(
        context,
        ApiService.friendlyConnectionMessage(e),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingNode = false);
      }
    }
  }

  Future<void> _deployToNode() async {
    if (widget.configNotifier.value.isEmpty) {
      showStitchMessage(
        context,
        'Add at least one sensor node first.',
        isError: true,
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
        showStitchMessage(context, 'Config deployed to ESP32 successfully.');
      } else {
        showStitchMessage(
          context,
          'ESP32 not connected. Join the node Wi-Fi and try again.',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      showStitchMessage(
        context,
        ApiService.friendlyConnectionMessage(e),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isDeploying = false);
      }
    }
  }

  Future<void> _importFromFile() async {
    if (_isImportingFile) return;
    setState(() => _isImportingFile = true);

    try {
      final loaded = await FileExchangeService.importConfigFromFile();
      widget.configNotifier.value = loaded;
      await StorageService.saveConfig(
        loaded,
        _keyController.text.trim(),
      );

      if (!mounted) return;
      showStitchMessage(
        context,
        'Imported ${loaded.length} node(s) from phone storage.',
      );
    } catch (e) {
      if (!mounted) return;
      showStitchMessage(context, 'Import failed: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isImportingFile = false);
      }
    }
  }

  Future<void> _exportToFile() async {
    if (_isExportingFile) return;
    setState(() => _isExportingFile = true);

    try {
      await FileExchangeService.exportAndShareConfig(widget.configNotifier.value);
      if (!mounted) return;
      showStitchMessage(context, 'Config file prepared for sharing.');
    } catch (e) {
      if (!mounted) return;
      showStitchMessage(context, 'Export failed: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isExportingFile = false);
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
                  const SizedBox(height: 16),
                  const StitchSectionLabel('Add Node'),
                  const SizedBox(height: 6),
                  Text(
                    'Choose the sensor type first, then map it to a valid GPIO pin.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  _SelectionField<String>(
                    label: 'Sensor Type',
                    icon: Icons.sensors_outlined,
                    valueLabel: selectedSensor,
                    enabled: true,
                    onTap: () async {
                      final value = await _showPickerSheet<String>(
                        context: ctx,
                        title: 'Select Sensor Type',
                        values: sensorRequirements.keys.toList(),
                        selectedValue: selectedSensor,
                        labelBuilder: (sensor) => sensor,
                        iconBuilder: (sensor) => Icons.sensors_outlined,
                      );
                      if (value == null) return;
                      setModalState(() {
                        selectedSensor = value;
                        selectedPin = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _SelectionField<int>(
                    label: 'GPIO Pin ($requiredType)',
                    icon: Icons.settings_input_component,
                    valueLabel: selectedPin == null ? 'Select a GPIO pin' : 'GPIO $selectedPin',
                    enabled: availablePins.isNotEmpty,
                    onTap: availablePins.isEmpty
                        ? null
                        : () async {
                            final value = await _showPickerSheet<int>(
                              context: ctx,
                              title: 'Select GPIO Pin',
                              values: availablePins,
                              selectedValue: selectedPin,
                              labelBuilder: (pin) => 'GPIO $pin',
                              iconBuilder: (pin) => Icons.memory_rounded,
                            );
                            if (value == null) return;
                            setModalState(() {
                              selectedPin = value;
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: StitchColors.surfaceLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: availablePins.isEmpty
                            ? StitchColors.error.withValues(alpha: 0.28)
                            : StitchColors.outlineVariant.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Text(
                      availablePins.isEmpty
                          ? 'No available pins left for $requiredType.'
                          : 'Required signal type: $requiredType  •  ${availablePins.length} pin(s) available',
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
          StitchTopBar(
            section: 'Architect',
            trailing: IconButton(
              onPressed: _isRefreshingPage
                  ? null
                  : () => _refreshPage(showFeedback: true),
              icon: _isRefreshingPage
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.refresh_rounded,
                      color: StitchColors.primaryContainer,
                    ),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: widget.configNotifier,
              builder: (context, config, _) {
                return RefreshIndicator(
                  onRefresh: _loadFromNode,
                  color: StitchColors.secondaryContainer,
                  backgroundColor: StitchColors.surfaceHigh,
                  child: ListView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    cacheExtent: 700,
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
                                final tileWidth = wide
                                    ? (constraints.maxWidth - 30) / 4
                                    : (constraints.maxWidth - 10) / 2;
                                return Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: const [
                                    _InfoTile('ADC1 RANGE', '32, 33, 34, 35, 36, 39'),
                                    _InfoTile('DAC CHANNELS', '25, 26'),
                                    _InfoTile('DIGITAL OUT', '16, 17, 21, 22, 25, 26, 27, 32, 33'),
                                    _InfoTile('DIGITAL IN', '16, 17, 21, 22, 25, 26, 27, 32, 33, 34, 35, 36, 39'),
                                  ].map((tile) {
                                    return SizedBox(
                                      width: tileWidth,
                                      child: tile,
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
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
                          Row(
                            children: [
                              Expanded(
                                child: StitchGhostButton(
                                  onPressed: _isImportingFile ? null : _importFromFile,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_isImportingFile)
                                        const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      else
                                        const Icon(
                                          Icons.file_open_rounded,
                                          size: 18,
                                        ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _isImportingFile
                                            ? 'IMPORTING...'
                                            : 'IMPORT FILE',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: StitchGhostButton(
                                  onPressed: _isExportingFile ? null : _exportToFile,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_isExportingFile)
                                        const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      else
                                        const Icon(
                                          Icons.ios_share_rounded,
                                          size: 18,
                                        ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _isExportingFile
                                            ? 'EXPORTING...'
                                            : 'EXPORT FILE',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
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
                            return RepaintBoundary(
                              child: GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: config.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: wide ? 2 : 1,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: wide ? 1.7 : 2.9,
                                ),
                                itemBuilder: (context, index) =>
                                    _buildBentoCard(context, config[index], index),
                              ),
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  fontSize: 16,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'GPIO ${item['pin']}  -  ${item['type']}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                ),
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
      constraints: const BoxConstraints(minHeight: 104),
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
          Align(
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
        ],
      ),
    );
  }
}

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
              Text(
                title,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
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
                                      ?.copyWith(
                                        color: StitchColors.primary,
                                      ),
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
            color: enabled
                ? StitchColors.surfaceLowest
                : StitchColors.surfaceLowest.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: StitchColors.outlineVariant.withValues(alpha: 0.24),
            ),
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
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        valueLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: enabled
                                  ? StitchColors.primary
                                  : StitchColors.onSurfaceVariant,
                            ),
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
