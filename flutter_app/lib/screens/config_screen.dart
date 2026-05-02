import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';

import '../services/api_service.dart';
import '../services/file_exchange_service.dart';
import '../services/nfc_payload_service.dart';
import '../services/nfc_service.dart';
import '../services/storage_service.dart';
import '../services/location_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/custom_ui.dart';

class ConfigScreen extends StatefulWidget {
  final ValueNotifier<List<Map<String, dynamic>>> configNotifier;
  final ValueListenable<int> activeTabListenable;
  final int tabIndex;

  const ConfigScreen({
    super.key,
    required this.configNotifier,
    required this.activeTabListenable,
    required this.tabIndex,
  });

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

enum Esp32Variant { esp32Node30Pin, esp32Node38Pin }

class _ConfigScreenState extends State<ConfigScreen> {
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _nfcAesKeyController = TextEditingController(
    text: NfcPayloadService.defaultAesKey,
  );
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  bool _isKeyVisible = false;
  bool _isDeploying = false;
  bool _isLoadingNode = false;
  bool _isRefreshingPage = false;
  bool _isImportingFile = false;
  bool _isExportingFile = false;
  bool _isFetchingLocation = false;
  bool _isWritingNfc = false;
  bool _isPreparingDirectNfc = false;
  Esp32Variant _selectedVariant = Esp32Variant.esp32Node30Pin;

  static const int maxFirmwareConfigSlots = 24;

  // 30-pin variant safe pins (LoRa + WiFi I2C)
  static const List<int> firmwareSafePins30Pin = [
    4, 13, 16, 17, 21, 22, 25, 26,
    32, 33, 34, 35, 36, 39,
  ];

  // 38-pin variant: Reserved for LoRa(5,14,18,19,23) + SD Card(shared) + NFC(21,22,27)
  // Only ADC1 (32-39) is reliable when WiFi is on
  // ADC2 pins fail when WiFi is active
  static const List<int> firmwareSafePins38Pin = [
    // ADC1 only (safe with WiFi): 32, 33, 34, 35, 36, 37, 38, 39
    // DI/DO compatible: 0, 2, 4, 12, 13, 15, 16, 17, 25, 26, 32, 33
    0, 2, 4, 12, 13, 15, 16, 17,
    25, 26, 32, 33, 34, 35, 36, 37, 38, 39,
  ];

  // Reserved pins for hardware modules
  // LoRa RA-02: SCK=18, MISO=19, MOSI=23, CS=5, RST=14
  // SD Card: SCK=18, MISO=19, MOSI=23, CS=5 (shared with LoRa)
  // PN532 NFC: SDA=21, SCL=22, IRQ=27
  static const List<int> reservedNodePins = [5, 14, 18, 19, 21, 22, 23, 27];

  // Pin groups by function (ADC-only pins cannot be used as DI/DO)
  // AI: ADC1 pins only (32-39) - safe when WiFi is on
  // DI: Digital input (input-only pins 34-39 supported)
  // DO: Digital output (cannot use input-only pins 34-39)
  static const Map<String, List<int>> pinGroups = {
    // ADC1 pins (32-39) - only these work reliably with WiFi
    'AI': [32, 33, 34, 35, 36, 37, 38, 39],
    // Digital input: all usable pins except reserved
    'DI': [0, 2, 4, 12, 13, 15, 25, 26, 32, 33, 34, 35, 36, 37, 38, 39],
    // Digital output: cannot use input-only pins 34-39
    'DO': [0, 2, 4, 12, 13, 15, 16, 17, 25, 26, 32, 33],
  };

  static const Map<String, int> defaultSensorPins = {
    'Turbidity': 36,
    'Rain': 39,
    'TDS': 34,
    'pH': 35,
    'DHT22': 32,
    'WaterTemp': 33,
    'Relay': 16,
  };

  static const Map<String, String> sensorRequirements = {
    'pH': 'AI',
    'TDS': 'AI',
    'Turbidity': 'AI',
    'Rain': 'DI',
    'DHT22': 'DI',
    'WaterTemp': 'DI',
    'Relay': 'DO',
  };

  @override
  void initState() {
    super.initState();
    _refreshPage();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _nfcAesKeyController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
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
    final normalizedConfig = _normalizedFirmwareConfig(
      widget.configNotifier.value,
    );
    if (!_sameConfig(normalizedConfig, widget.configNotifier.value)) {
      widget.configNotifier.value = normalizedConfig;
    }
    await StorageService.saveConfig(
      normalizedConfig,
      _keyController.text.trim(),
    );
    if (!mounted) return;
    showStitchMessage(context, 'Architect draft saved locally.');
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isFetchingLocation = true);
    try {
      final hasPerm = await LocationService.hasPermission();
      if (!hasPerm) {
        final status = await LocationService.requestPermission();
        if (!mounted) return;
        if (status != PermissionStatus.granted) {
          showStitchMessage(
            context,
            'Location permission denied',
            isError: true,
          );
          return;
        }
      }

      final position = await LocationService.getCurrentLocation();
      if (!mounted) return;

      if (position != null) {
        setState(() {
          _latitudeController.text = position.latitude.toStringAsFixed(6);
          _longitudeController.text = position.longitude.toStringAsFixed(6);
        });
        showStitchMessage(context, 'GPS location captured');
      } else {
        showStitchMessage(context, 'Failed to get GPS location', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      showStitchMessage(context, 'Location error: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isFetchingLocation = false);
      }
    }
  }

  String _canonicalSensorName(String sensor) {
    final normalized = sensor.trim().toUpperCase();
    if (normalized == 'PH') return 'pH';
    if (normalized == 'TDS') return 'TDS';
    if (normalized == 'TURBIDITY') return 'Turbidity';
    if (normalized == 'RAIN') return 'Rain';
    if (normalized == 'DHT22') return 'DHT22';
    if (normalized == 'WATERTEMP') return 'WaterTemp';
    if (normalized == 'RELAY') return 'Relay';
    return sensor.trim();
  }

  List<Map<String, dynamic>> _normalizedFirmwareConfig(
    List<Map<String, dynamic>> config,
  ) {
    return config.map((item) {
      final sensor = _canonicalSensorName(item['sensor']?.toString() ?? '');
      final expectedType = sensorRequirements[sensor];
      final normalized = <String, dynamic>{
        'pin': item['pin'],
        'sensor': sensor,
        'type': expectedType ?? item['type']?.toString().toUpperCase(),
      };
      final label = item['label']?.toString().trim();
      if (label != null && label.isNotEmpty) {
        normalized['label'] = label;
      }
      return normalized;
    }).toList();
  }

  List<String> _firmwareConfigErrors(List<Map<String, dynamic>> config, {Esp32Variant? variant}) {
    final errors = <String>[];
    final usedPins = <int>{};
    final safePins = variant == null
        ? firmwareSafePins30Pin // Default to 30-pin
        : (variant == Esp32Variant.esp32Node30Pin ? firmwareSafePins30Pin : firmwareSafePins38Pin);
    final maxSlots = variant == null
        ? 15
        : (variant == Esp32Variant.esp32Node30Pin ? 15 : 24);

    if (config.isEmpty) {
      errors.add('Add at least one GPIO node before deploying.');
    }

    if (config.length > maxSlots) {
      errors.add(
        'ESP32 firmware supports only $maxSlots GPIO config slots.',
      );
    }

    for (final item in config) {
      final pin = item['pin'];
      final sensor = item['sensor']?.toString() ?? '';
      final type = item['type']?.toString().toUpperCase() ?? '';

      if (pin is! int) {
        errors.add('$sensor has an invalid GPIO pin.');
        continue;
      }

      if (!safePins.contains(pin)) {
        errors.add('GPIO $pin is not accepted by the ESP32 node firmware.');
      }

      if (reservedNodePins.contains(pin)) {
        errors.add('GPIO $pin is reserved by LoRa/NFC hardware on this node.');
      }

      if (!usedPins.add(pin)) {
        errors.add('GPIO $pin is assigned more than once.');
      }

      if (!sensorRequirements.containsKey(sensor)) {
        errors.add('$sensor is not a supported firmware sensor type.');
        continue;
      }

      final expectedType = sensorRequirements[sensor]!;
      if (type != expectedType) {
        errors.add('$sensor must use $expectedType, not $type.');
      }

      final validPins = pinGroups[expectedType] ?? const <int>[];
      if (!validPins.contains(pin)) {
        errors.add('GPIO $pin cannot be used as $expectedType for $sensor.');
      }
    }

    return errors;
  }

  Future<Map<String, dynamic>?> _buildConfigWithMetadata({
    required String securityKey,
    required bool includeNfcKeys,
  }) async {
    if (securityKey.isEmpty) {
      showStitchMessage(
        context,
        'Enter the node security key before deploying config.',
        isError: true,
      );
      return null;
    }

    final latitude = double.tryParse(_latitudeController.text);
    final longitude = double.tryParse(_longitudeController.text);

    if (latitude == null || longitude == null) {
      showStitchMessage(context, 'Invalid GPS coordinates', isError: true);
      return null;
    }

    if (includeNfcKeys) {
      try {
        NfcPayloadService.validateAesKey(_nfcAesKeyController.text);
      } on FormatException catch (e) {
        showStitchMessage(context, e.message, isError: true);
        return null;
      }
    }

    final normalizedConfig = _normalizedFirmwareConfig(
      widget.configNotifier.value,
    );
    final configErrors = _firmwareConfigErrors(normalizedConfig, variant: _selectedVariant);
    if (configErrors.isNotEmpty) {
      showStitchMessage(context, configErrors.first, isError: true);
      return null;
    }

    if (!_sameConfig(normalizedConfig, widget.configNotifier.value)) {
      widget.configNotifier.value = normalizedConfig;
    }

    final configWithMetadata = <String, dynamic>{
      'config': normalizedConfig,
      'latitude': latitude,
      'longitude': longitude,
    };

    try {
      final profiles = await StorageService.loadCalibrationProfiles();
      if (profiles.isNotEmpty) {
        configWithMetadata['calibration'] = profiles;
      }
    } catch (_) {
      // Non-fatal: deploy without calibration if local load fails.
    }

    try {
      final aesKey = NfcPayloadService.validateAesKey(
        _nfcAesKeyController.text,
      );
      configWithMetadata['keys'] = {
        'aes128': aesKey,
        'auth': NfcPayloadService.defaultAuthKey,
      };
    } on FormatException {
      if (includeNfcKeys) rethrow;
    }

    return configWithMetadata;
  }

  Future<void> _deployToNode() async {
    final securityKey = _keyController.text.trim();
    final configWithMetadata = await _buildConfigWithMetadata(
      securityKey: securityKey,
      includeNfcKeys: false,
    );
    if (configWithMetadata == null) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isDeploying = true);

    try {
      await StorageService.saveConfig(widget.configNotifier.value, securityKey);

      final result = await ApiService.sendConfigWithMetadata(
        configWithMetadata,
        securityKey,
      );

      if (!mounted) return;

      if (result['ok'] == true) {
        showStitchMessage(
          context,
          'Config + GPS + calibration deployed to ESP32 successfully.',
        );
      } else {
        showStitchMessage(
          context,
          ApiService.friendlyApiMessage(result),
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

  Future<void> _writeNfcTag() async {
    final securityKey = _keyController.text.trim();
    final configWithMetadata = await _buildConfigWithMetadata(
      securityKey: securityKey,
      includeNfcKeys: true,
    );
    if (configWithMetadata == null) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isWritingNfc = true);

    try {
      await StorageService.saveConfig(widget.configNotifier.value, securityKey);

      if (!mounted) return;
      showStitchMessage(context, 'Hold the NFC tag near your phone.');

      final result = await NfcService.writeSmartPonicTag(
        configPayload: configWithMetadata,
        securityKey: securityKey,
        aesKey: _nfcAesKeyController.text,
      );

      if (!mounted) return;
      showStitchMessage(
        context,
        'NFC tag written (${result.bytesWritten} encrypted bytes). Tap it to the ESP32 node.',
      );
    } on TimeoutException {
      if (!mounted) return;
      showStitchMessage(context, 'NFC write timed out.', isError: true);
    } catch (e) {
      if (!mounted) return;
      showStitchMessage(context, 'NFC write failed: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isWritingNfc = false);
      }
    }
  }

  Future<void> _prepareDirectNfcTap() async {
    final securityKey = _keyController.text.trim();
    final configWithMetadata = await _buildConfigWithMetadata(
      securityKey: securityKey,
      includeNfcKeys: true,
    );
    if (configWithMetadata == null) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isPreparingDirectNfc = true);

    try {
      await StorageService.saveConfig(widget.configNotifier.value, securityKey);

      final result = await NfcService.prepareDirectPhoneTap(
        configPayload: configWithMetadata,
        securityKey: securityKey,
        aesKey: _nfcAesKeyController.text,
      );

      if (!mounted) return;
      showStitchMessage(
        context,
        'Phone NFC is ready (${result.bytesWritten} bytes). Tap phone to PN532 within 2 minutes.',
      );
    } catch (e) {
      if (!mounted) return;
      showStitchMessage(context, 'Direct NFC deploy failed: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isPreparingDirectNfc = false);
      }
    }
  }

  Future<void> _loadFromNode() async {
    final securityKey = _keyController.text.trim();
    if (securityKey.isEmpty) {
      showStitchMessage(
        context,
        'Enter the node security key before loading config.',
        isError: true,
      );
      return;
    }

    setState(() => _isLoadingNode = true);

    try {
      final result = await ApiService.fetchConfig(securityKey);

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
          ApiService.friendlyApiMessage(result),
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

  Future<void> _importFromFile() async {
    if (_isImportingFile) return;
    setState(() => _isImportingFile = true);

    try {
      final loaded = await FileExchangeService.importConfigFromFile();
      final normalized = _normalizedFirmwareConfig(loaded);
      final errors = _firmwareConfigErrors(normalized, variant: _selectedVariant);
      if (errors.isNotEmpty) {
        throw Exception(errors.first);
      }
      widget.configNotifier.value = normalized;
      await StorageService.saveConfig(normalized, _keyController.text.trim());

      if (!mounted) return;
      showStitchMessage(
        context,
        'Imported ${normalized.length} node(s) from phone storage.',
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
      await FileExchangeService.exportAndShareConfig(
        widget.configNotifier.value,
      );
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
    final updated = List<Map<String, dynamic>>.from(
      widget.configNotifier.value,
    );
    updated.removeAt(index);
    widget.configNotifier.value = updated;
  }

  IconData _componentIcon(String component) {
    final normalized = component.toLowerCase();
    if (normalized.contains('pump')) return Icons.water_rounded;
    if (normalized.contains('valve')) return Icons.tune_rounded;
    if (normalized.contains('relay')) return Icons.toggle_on_rounded;
    if (normalized.contains('temp')) return Icons.thermostat_rounded;
    if (normalized.contains('ph')) return Icons.science_outlined;
    if (normalized.contains('tds')) return Icons.opacity_rounded;
    if (normalized.contains('turbidity')) return Icons.water_drop_outlined;
    return Icons.sensors_outlined;
  }

  String _componentDisplayName(Map<String, dynamic> item) {
    final sensor = item['sensor']?.toString().trim() ?? 'Node';
    final label = item['label']?.toString().trim() ?? '';
    if (sensor == 'Relay' && label.isNotEmpty) {
      return '$label Relay';
    }
    return sensor;
  }

  Future<void> _showAddNodeSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (widget.configNotifier.value.length >= maxFirmwareConfigSlots) {
      showStitchMessage(
        context,
        'ESP32 firmware supports only $maxFirmwareConfigSlots GPIO config slots.',
        isError: true,
      );
      return;
    }

    final item = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: StitchColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) =>
          _AddNodeSheet(existingConfig: widget.configNotifier.value),
    );

    if (!mounted || item == null) return;

    final updated = List<Map<String, dynamic>>.from(widget.configNotifier.value)
      ..add(item);
    widget.configNotifier.value = updated;
  }

  Widget _buildConfigListSection() {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: widget.configNotifier,
      builder: (context, config, _) {
        if (config.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 8),
            child: StitchEmptyState(
              title: 'No Nodes Defined',
              subtitle:
                  'Tap "Add Sensor Node" or "Load From Node" to start building your ESP32 configuration.',
              icon: Icons.hub_outlined,
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 720;
            return RepaintBoundary(
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: config.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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
            onPressed: _isDeploying
                ? null
                : (_selectedVariant == Esp32Variant.esp32Node30Pin
                    ? _deployToNode
                    : _prepareDirectNfcTap),
            backgroundColor: Colors.transparent,
            elevation: 0,
            label: Text(
              _isDeploying
                  ? 'DEPLOYING...'
                  : (_selectedVariant == Esp32Variant.esp32Node30Pin
                      ? 'DEPLOY TO NODE'
                      : 'PREPARE NFC TAP'),
            ),
            icon: _isDeploying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: StitchColors.onSecondaryContainer,
                    ),
                  )
                : Icon(_selectedVariant == Esp32Variant.esp32Node30Pin
                    ? Icons.rocket_launch_rounded
                    : Icons.nfc_rounded),
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
            child: RefreshIndicator(
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
                                style: Theme.of(
                                  context,
                                ).textTheme.displayMedium,
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
                        const StitchSectionLabel('ESP32 Variant'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _VariantButton(
                                label: '30-Pin (WiFi)',
                                icon: Icons.wifi_rounded,
                                isSelected: _selectedVariant ==
                                    Esp32Variant.esp32Node30Pin,
                                onTap: () => setState(() {
                                  _selectedVariant = Esp32Variant.esp32Node30Pin;
                                }),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _VariantButton(
                                label: '38-Pin (NFC)',
                                icon: Icons.nfc_rounded,
                                isSelected: _selectedVariant ==
                                    Esp32Variant.esp32Node38Pin,
                                onTap: () => setState(() {
                                  _selectedVariant = Esp32Variant.esp32Node38Pin;
                                }),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedVariant == Esp32Variant.esp32Node30Pin
                              ? 'Uses WiFi AP for configuration'
                              : 'Uses NFC tag for configuration',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: StitchColors.secondaryContainer,
                              ),
                        ),
                      ],
                    ),
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
                          'Required for node load/deploy. The ESP32 now checks this key before exposing config access.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _nfcAesKeyController,
                          obscureText: !_isKeyVisible,
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
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  StitchPanel(
                    color: StitchColors.surfaceContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.pin_drop_outlined,
                              color: StitchColors.primaryContainer,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'NODE LOCATION (GPS)',
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
                        Text(
                          'Capture your phone GPS location. Node sends this to HQ when config is deployed.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _latitudeController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Latitude',
                                  prefixIcon: Icon(
                                    Icons.location_on_outlined,
                                    size: 20,
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _longitudeController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Longitude',
                                  prefixIcon: Icon(
                                    Icons.location_on_outlined,
                                    size: 20,
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: StitchPrimaryButton(
                            onPressed: _isFetchingLocation
                                ? null
                                : _fetchCurrentLocation,
                            child: _isFetchingLocation
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.my_location, size: 18),
                                      SizedBox(width: 8),
                                      Text('CAPTURE GPS LOCATION'),
                                    ],
                                  ),
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
                              children:
                                  const [
                                    _InfoTile(
                                      'ANALOG INPUT',
                                      '32, 33, 34, 35, 36, 39',
                                    ),
                                    _InfoTile(
                                      'DIGITAL INPUT',
                                      '4, 13, 25, 26, 32, 33, 34, 35, 36, 39',
                                    ),
                                    _InfoTile(
                                      'DIGITAL OUTPUT',
                                      '4, 13, 16, 17, 25, 26, 32, 33',
                                    ),
                                    _InfoTile(
                                      'RESERVED',
                                      '5, 14, 18, 19, 21, 22, 23, 27',
                                    ),
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
                      // Variant-specific deploy options
                      if (_selectedVariant == Esp32Variant.esp32Node30Pin) ...[
                        // WiFi deploy options for 30-pin variant
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
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.cloud_download_outlined,
                                    size: 18,
                                  ),
                                const SizedBox(width: 8),
                                Text(
                                  _isLoadingNode
                                      ? 'LOADING...'
                                      : 'LOAD FROM NODE',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ] else ...[
                        // NFC deploy options for 38-pin variant
                        SizedBox(
                          width: double.infinity,
                          child: StitchGhostButton(
                            onPressed: _isPreparingDirectNfc
                                ? null
                                : _prepareDirectNfcTap,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_isPreparingDirectNfc)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  const Icon(Icons.nfc_rounded, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  _isPreparingDirectNfc
                                      ? 'PREPARING NFC...'
                                      : 'TAP PHONE TO PN532',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: StitchGhostButton(
                            onPressed: _isWritingNfc ? null : _writeNfcTag,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_isWritingNfc)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  const Icon(Icons.style_rounded, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  _isWritingNfc
                                      ? 'WRITING TAG...'
                                      : 'WRITE NFC TAG',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      // File operations (available for both variants)
                      Row(
                        children: [
                          Expanded(
                            child: StitchGhostButton(
                              onPressed: _isImportingFile
                                  ? null
                                  : _importFromFile,
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
                              onPressed: _isExportingFile
                                  ? null
                                  : _exportToFile,
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
                  _buildConfigListSection(),
                ],
              ),
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
                _componentIcon(_componentDisplayName(item)),
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
            _componentDisplayName(item).toUpperCase(),
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'GPIO ${item['pin']}  -  ${item['type']}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontSize: 13),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? StitchColors.primary.withValues(alpha: 0.15)
                : StitchColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? StitchColors.primary
                  : StitchColors.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? StitchColors.primary
                    : StitchColors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? StitchColors.primary
                      : StitchColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddNodeSheet extends StatefulWidget {
  final List<Map<String, dynamic>> existingConfig;

  const _AddNodeSheet({required this.existingConfig});

  @override
  State<_AddNodeSheet> createState() => _AddNodeSheetState();
}

class _AddNodeSheetState extends State<_AddNodeSheet> {
  final TextEditingController _relayLabelController = TextEditingController();
  String _selectedSensor = 'pH';
  int? _selectedPin;

  @override
  void dispose() {
    _relayLabelController.dispose();
    super.dispose();
  }

  String get _requiredType {
    return _ConfigScreenState.sensorRequirements[_selectedSensor]!;
  }

  bool get _isRelay => _selectedSensor == 'Relay';

  List<int> get _availablePins {
    final usedPins = widget.existingConfig.map((e) => e['pin'] as int).toSet();

    return _ConfigScreenState.pinGroups[_requiredType]!
        .where((pin) => !usedPins.contains(pin))
        .toList();
  }

  IconData _componentIcon(String component) {
    final normalized = component.toLowerCase();
    if (normalized.contains('pump')) return Icons.water_rounded;
    if (normalized.contains('valve')) return Icons.tune_rounded;
    if (normalized.contains('relay')) return Icons.toggle_on_rounded;
    if (normalized.contains('temp')) return Icons.thermostat_rounded;
    if (normalized.contains('ph')) return Icons.science_outlined;
    if (normalized.contains('tds')) return Icons.opacity_rounded;
    if (normalized.contains('turbidity')) return Icons.water_drop_outlined;
    return Icons.sensors_outlined;
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
                      color: StitchColors.outlineVariant.withValues(
                        alpha: 0.55,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
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
                            ? StitchColors.primaryContainer.withValues(
                                alpha: 0.10,
                              )
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
                  color: StitchColors.outlineVariant.withValues(alpha: 0.55),
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
                  values: _ConfigScreenState.sensorRequirements.keys.toList(),
                  selectedValue: _selectedSensor,
                  labelBuilder: (sensor) => sensor,
                  iconBuilder: _componentIcon,
                );
                if (value == null || !mounted) return;
                final defaultPin = _ConfigScreenState.defaultSensorPins[value];
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
                  if (mounted) {
                    setState(() {});
                  }
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
                      ? StitchColors.error.withValues(alpha: 0.28)
                      : StitchColors.outlineVariant.withValues(alpha: 0.28),
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontSize: 13),
            ),
          ),
        ],
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
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
