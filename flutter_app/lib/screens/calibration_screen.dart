import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/custom_ui.dart';

// ---------------------------------------------------------------------------
// Named constants for calibration field keys
// ---------------------------------------------------------------------------

/// Map key for the sensor key field within a calibration profile.
const String _fieldSensorKey = 'sensor_key';

/// Map key for the minimum threshold field.
const String _fieldThresholdMin = 'threshold_min';

/// Map key for the maximum threshold field.
const String _fieldThresholdMax = 'threshold_max';

/// Map key for calibration coefficient A.
const String _fieldCalibrationA = 'calibration_a';

/// Map key for calibration coefficient B.
const String _fieldCalibrationB = 'calibration_b';

/// Map key for calibration coefficient C.
const String _fieldCalibrationC = 'calibration_c';

// ---------------------------------------------------------------------------
// Other named constants
// ---------------------------------------------------------------------------

/// Cache extent for the calibration list.
const double _calibrationCacheExtent = 600;

/// Error icon size.
const double _errorIconSize = 56;

/// Sensor card icon container size.
const double _sensorCardIconSize = 36;

/// Number of decimal places for double formatting.
const int _formatDecimalPlaces = 4;

// ---------------------------------------------------------------------------
// CalibrationScreen
// ---------------------------------------------------------------------------

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
        _fieldSensorKey: key,
        _fieldThresholdMin: null,
        _fieldThresholdMax: null,
        _fieldCalibrationA: 1.0,
        _fieldCalibrationB: 0.0,
        _fieldCalibrationC: 0.0,
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
              size: _errorIconSize,
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


  Widget _buildProfileList() {
    return RefreshIndicator(
      color: StitchColors.secondaryContainer,
      backgroundColor: StitchColors.surfaceHigh,
      onRefresh: _loadProfiles,
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        cacheExtent: _calibrationCacheExtent,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 200),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AutoSizeText(
                      'Sensor Calibration',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      minFontSize: 16,
                    ),
                    SizedBox(height: 6),
                    AutoSizeText(
                      'Threshold ranges and calibration coefficients are saved locally and deployed to the node when you deploy config.',
                      style: TextStyle(
                        color: StitchColors.onSurfaceVariant,
                        fontSize: 13,
                      ),
                      maxLines: 3,
                      minFontSize: 10,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: StitchColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: AutoSizeText(
                  '${_profiles.length} SENSORS',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: StitchColors.primaryContainer,
                    letterSpacing: 1,
                  ),
                  maxLines: 1,
                  minFontSize: 8,
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
    final tMin = profile?[_fieldThresholdMin];
    final tMax = profile?[_fieldThresholdMax];
    final calA = profile?[_fieldCalibrationA] ?? 1.0;
    final calB = profile?[_fieldCalibrationB] ?? 0.0;
    final calC = profile?[_fieldCalibrationC] ?? 0.0;

    final isCalActive = calA != 1.0 || calB != 0.0 || calC != 0.0;
    final isLimitsSet = tMin != null || tMax != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: StitchPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: _sensorCardIconSize,
                  height: _sensorCardIconSize,
                  decoration: BoxDecoration(
                    color: StitchColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: StitchColors.outlineVariant.withValues(alpha: 0.5),
                    ),
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
                      AutoSizeText(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        minFontSize: 12,
                      ),
                      if (unit.isNotEmpty)
                        AutoSizeText(
                          'Unit: $unit',
                          style: const TextStyle(
                            color: StitchColors.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          minFontSize: 9,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isCalActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: StitchColors.primaryContainer.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: StitchColors.primaryContainer.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Text(
                      'CAL ACTIVE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: StitchColors.primaryContainer,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                if (isLimitsSet) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: StitchColors.secondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: StitchColors.secondary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Text(
                      'LIMITS SET',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: StitchColors.secondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
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
                    field: _fieldThresholdMin,
                    label: 'Min',
                    value: tMin,
                    hint: unit.isNotEmpty ? unit : 'min',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildNumberField(
                    key: key,
                    field: _fieldThresholdMax,
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
                Expanded(child: _buildNumberField(key: key, field: _fieldCalibrationA, label: 'A', value: calA)),
                const SizedBox(width: 10),
                Expanded(child: _buildNumberField(key: key, field: _fieldCalibrationB, label: 'B', value: calB)),
                const SizedBox(width: 10),
                Expanded(child: _buildNumberField(key: key, field: _fieldCalibrationC, label: 'C', value: calC)),
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
            fontWeight: FontWeight.w700,
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
            fillColor: StitchColors.surfaceLowest,
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
    return v.toStringAsFixed(_formatDecimalPlaces)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}
