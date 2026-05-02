import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/location_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/custom_ui.dart';

class CalibrationScreen extends StatefulWidget {
  final ValueListenable<int> activeTabListenable;
  final int tabIndex;

  const CalibrationScreen({
    super.key,
    required this.activeTabListenable,
    required this.tabIndex,
  });

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  Map<String, dynamic> _profiles = {};
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasLoadedOnce = false;
  String? _errorMessage;

  // Node location state
  double? _latitude;
  double? _longitude;
  double? _distanceM;
  bool _isFetchingLocation = false;

  static const List<String> _sensorOrder = [
    'temperature',
    'humidity',
    'waterTemp',
    'ph',
    'tds',
    'turbidity',
    'rain',
  ];

  static const Map<String, Map<String, String>> _sensorMeta = {
    'temperature': {'label': 'Temperature', 'unit': 'C'},
    'humidity':    {'label': 'Humidity',    'unit': '%'},
    'waterTemp':   {'label': 'Water Temp',  'unit': 'C'},
    'ph':          {'label': 'pH',           'unit': 'pH'},
    'tds':         {'label': 'TDS',          'unit': 'ppm'},
    'turbidity':   {'label': 'Turbidity',   'unit': 'NTU'},
    'rain':        {'label': 'Rain',        'unit': ''},
  };

  @override
  void initState() {
    super.initState();
    widget.activeTabListenable.addListener(_handleActiveTabChanged);
    // Important: allow the initial load to run even though we start in a "loading" state.
    // Previously `_loadProfiles()` would early-return because `_isLoading` was true,
    // leaving the page stuck on the spinner.
    _isLoading = false;
    if (widget.activeTabListenable.value == widget.tabIndex) {
      _loadProfiles(showLoader: true);
    }
  }

  @override
  void dispose() {
    widget.activeTabListenable.removeListener(_handleActiveTabChanged);
    super.dispose();
  }

  void _handleActiveTabChanged() {
    if (widget.activeTabListenable.value == widget.tabIndex) {
      _loadProfiles(showLoader: !_hasLoadedOnce);
    }
  }

  Future<void> _loadProfiles({bool showLoader = false}) async {
    if (_isLoading && !showLoader) return;
    if (showLoader) setState(() => _isLoading = true);

    try {
      final result = await StorageService.loadCalibrationProfiles();
      if (!mounted) return;

      setState(() {
        _profiles = Map<String, dynamic>.from(result);
        _errorMessage = null;
        _hasLoadedOnce = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to load local calibration: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isFetchingLocation = true);
    try {
      final hasPerm = await LocationService.hasPermission();
      if (!hasPerm) {
        final status = await LocationService.requestPermission();
        if (!mounted) return;
        if (status != PermissionStatus.granted) {
          showStitchMessage(context, 'Location permission denied', isError: true);
          return;
        }
      }

      final position = await LocationService.getCurrentLocation();
      if (!mounted) return;

      if (position != null) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
        showStitchMessage(context, 'GPS location captured');
      } else {
        showStitchMessage(context, 'Failed to get GPS location', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isFetchingLocation = false);
    }
  }

  Future<void> _saveAll() async {
    setState(() => _isSaving = true);
    try {
      await StorageService.saveCalibrationProfiles(_profiles);
      if (!mounted) return;

      showStitchMessage(context, 'Calibration saved locally on this device.');
    } catch (e) {
      if (mounted) {
        showStitchMessage(context, 'Save error: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _updateProfile(String key, String field, dynamic value) {
    final updated = Map<String, dynamic>.from(_profiles);
    if (!updated.containsKey(key)) {
      updated[key] = {
        'sensor_key': key,
        'threshold_min': null,
        'threshold_max': null,
        'calibration_a': 1.0,
        'calibration_b': 0.0,
        'calibration_c': 0.0,
      };
    }
    updated[key] = Map<String, dynamic>.from(updated[key]);
    updated[key][field] = value;
    setState(() => _profiles = updated);
  }

  @override
  Widget build(BuildContext context) {
    return StitchScaffold(
      floatingActionButton: !_isLoading && _profiles.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppTheme.ctaGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: AppTheme.cyanGlowShadow,
                ),
                child: FloatingActionButton.extended(
                  onPressed: _isSaving ? null : _saveAll,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  label: Text(_isSaving ? 'SAVING...' : 'SAVE CALIBRATION'),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: StitchColors.onSecondaryContainer,
                          ),
                        )
                      : const Icon(Icons.cloud_sync_rounded),
                ),
              ),
            )
          : null,
      body: Column(
        children: [
          StitchTopBar(
            section: 'Calibration',
            trailing: IconButton(
              onPressed: _isLoading ? null : _loadProfiles,
              icon: _isLoading
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
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: StitchColors.secondaryContainer,
                    ),
                  )
                : _errorMessage != null
                    ? _buildError()
                    : _buildProfileList(),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: StitchColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: StitchColors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            StitchPrimaryButton(
              onPressed: _loadProfiles,
              child: const Text('RETRY'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard() {
    return StitchPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: StitchColors.primaryContainer.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.pin_drop_rounded,
                  color: StitchColors.primaryContainer,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Node Location (GPS)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      'Captured from phone GPS',
                      style: TextStyle(
                        color: StitchColors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Latitude',
                      style: TextStyle(
                        fontSize: 11,
                        color: StitchColors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      style: const TextStyle(
                        color: StitchColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Auto or manual',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: StitchColors.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: StitchColors.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: StitchColors.primaryContainer, width: 1.5),
                        ),
                        filled: true,
                        fillColor: StitchColors.surfaceLow,
                        suffixIcon: const Icon(Icons.location_on_outlined, size: 18),
                      ),
                      controller: TextEditingController(
                        text: _latitude?.toStringAsFixed(6) ?? '',
                      ),
                      onChanged: (v) {
                        setState(() {
                          _latitude = double.tryParse(v);
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Longitude',
                      style: TextStyle(
                        fontSize: 11,
                        color: StitchColors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      style: const TextStyle(
                        color: StitchColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Auto or manual',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: StitchColors.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: StitchColors.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: StitchColors.primaryContainer, width: 1.5),
                        ),
                        filled: true,
                        fillColor: StitchColors.surfaceLow,
                        suffixIcon: const Icon(Icons.location_on_outlined, size: 18),
                      ),
                      controller: TextEditingController(
                        text: _longitude?.toStringAsFixed(6) ?? '',
                      ),
                      onChanged: (v) {
                        setState(() {
                          _longitude = double.tryParse(v);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Distance (m)',
                      style: TextStyle(
                        fontSize: 11,
                        color: StitchColors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(
                        color: StitchColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Optional',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: StitchColors.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: StitchColors.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: StitchColors.primaryContainer, width: 1.5),
                        ),
                        filled: true,
                        fillColor: StitchColors.surfaceLow,
                        suffixIcon: const Icon(Icons.straighten_outlined, size: 18),
                      ),
                      controller: TextEditingController(
                        text: _distanceM?.toStringAsFixed(1) ?? '',
                      ),
                      onChanged: (v) {
                        setState(() {
                          _distanceM = double.tryParse(v);
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: StitchPrimaryButton(
                    onPressed: _isFetchingLocation ? null : _fetchCurrentLocation,
                    child: _isFetchingLocation
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: StitchColors.onSecondaryContainer,
                            ),
                          )
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.my_location_rounded, size: 16),
                              SizedBox(width: 6),
                              Text('CAPTURE GPS'),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileList() {
    return RefreshIndicator(
      color: StitchColors.secondaryContainer,
      backgroundColor: StitchColors.surfaceHigh,
      onRefresh: _loadProfiles,
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        cacheExtent: 600,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 200),
        children: [
          // Node Location GPS Card - at the very top
          _buildLocationCard(),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sensor Calibration',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Threshold ranges and calibration coefficients are saved locally and deployed to the node when you deploy config.',
                      style: TextStyle(
                        color: StitchColors.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: StitchColors.primaryContainer.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_profiles.length} SENSORS',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: StitchColors.primaryContainer,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ..._sensorOrder.map((key) {
            final meta = _sensorMeta[key]!;
            final profile = _profiles[key] as Map<String, dynamic>?;

            return _buildSensorCard(key, meta['label']!, meta['unit']!, profile);
          }),
        ],
      ),
    );
  }

  Widget _buildSensorCard(String key, String label, String unit, Map<String, dynamic>? profile) {
    final tMin = profile?['threshold_min'];
    final tMax = profile?['threshold_max'];
    final calA = profile?['calibration_a'] ?? 1.0;
    final calB = profile?['calibration_b'] ?? 0.0;
    final calC = profile?['calibration_c'] ?? 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: StitchPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: StitchColors.primaryContainer.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: StitchColors.primaryContainer,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (unit.isNotEmpty)
                        Text(
                          'Unit: $unit',
                          style: const TextStyle(
                            color: StitchColors.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'THRESHOLD RANGE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: StitchColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildNumberField(
                    key: key,
                    field: 'threshold_min',
                    label: 'Min',
                    value: tMin,
                    hint: unit.isNotEmpty ? unit : 'min',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildNumberField(
                    key: key,
                    field: 'threshold_max',
                    label: 'Max',
                    value: tMax,
                    hint: unit.isNotEmpty ? unit : 'max',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'CALIBRATION COEFFICIENTS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: StitchColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildNumberField(key: key, field: 'calibration_a', label: 'A', value: calA)),
                const SizedBox(width: 10),
                Expanded(child: _buildNumberField(key: key, field: 'calibration_b', label: 'B', value: calB)),
                const SizedBox(width: 10),
                Expanded(child: _buildNumberField(key: key, field: 'calibration_c', label: 'C', value: calC)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberField({
    required String key,
    required String field,
    required String label,
    required dynamic value,
    String? hint,
  }) {
    final controller = TextEditingController(
      text: value != null ? (value is double ? _formatDouble(value) : value.toString()) : '',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: StitchColors.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          style: const TextStyle(
            color: StitchColors.primary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint ?? '',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: StitchColors.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: StitchColors.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: StitchColors.primaryContainer, width: 1.5),
            ),
            filled: true,
            fillColor: StitchColors.surfaceLow,
          ),
          onChanged: (v) {
            final parsed = double.tryParse(v);
            if (parsed != null) {
              _updateProfile(key, field, parsed);
            } else if (v.isEmpty) {
              _updateProfile(key, field, null);
            }
          },
        ),
      ],
    );
  }

  String _formatDouble(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}
