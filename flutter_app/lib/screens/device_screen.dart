import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/custom_ui.dart';
import '../widgets/sensor_matrix.dart';

class DeviceScreen extends StatefulWidget {
  final void Function(List<Map<String, dynamic>>) onLoadToConfig;
  final ValueListenable<int> activeTabListenable;
  final int tabIndex;

  const DeviceScreen({
    super.key,
    required this.onLoadToConfig,
    required this.activeTabListenable,
    required this.tabIndex,
  });

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  List<Map<String, dynamic>> deviceConfig = [];
  Map<String, dynamic>? _nodeHealth;
  String? _healthMessage;
  bool loading = true;
  bool _isRefreshing = false;
  bool _hasLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    widget.activeTabListenable.addListener(_handleActiveTabChanged);
    if (widget.activeTabListenable.value == widget.tabIndex) {
      _loadCurrentConfig(showLoader: true);
    } else {
      loading = false;
    }
  }

  @override
  void dispose() {
    widget.activeTabListenable.removeListener(_handleActiveTabChanged);
    super.dispose();
  }

  void _handleActiveTabChanged() {
    if (widget.activeTabListenable.value == widget.tabIndex) {
      _loadCurrentConfig(showLoader: !_hasLoadedOnce);
    }
  }

  Future<void> _loadCurrentConfig({bool showLoader = false}) async {
    if (_isRefreshing) return;
    if (showLoader && mounted) {
      setState(() => loading = true);
    }

    _isRefreshing = true;
    try {
      final configFuture = StorageService.loadConfig();
      final healthFuture = ApiService.fetchHealth();

      final data = await configFuture;
      final raw = data['config'] as String?;
      final parsed = raw == null
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(jsonDecode(raw));
      Map<String, dynamic>? nextHealth;
      String? nextHealthMessage;

      try {
        final healthResult = await healthFuture;
        if (healthResult['ok'] == true &&
            healthResult['data'] is Map<String, dynamic>) {
          nextHealth = Map<String, dynamic>.from(
            healthResult['data'] as Map<String, dynamic>,
          );
        } else {
          nextHealthMessage = ApiService.friendlyApiMessage(healthResult);
        }
      } catch (e) {
        nextHealthMessage = ApiService.friendlyConnectionMessage(e);
      }

      if (!mounted) return;
      final changed = !_sameConfig(parsed, deviceConfig);
      final healthChanged = !mapEquals(nextHealth, _nodeHealth) ||
          nextHealthMessage != _healthMessage;
      if (changed || healthChanged || loading) {
        setState(() {
          deviceConfig = parsed;
          _nodeHealth = nextHealth;
          _healthMessage = nextHealthMessage;
          loading = false;
        });
      }
      _hasLoadedOnce = true;
    } finally {
      _isRefreshing = false;
      if (mounted && loading) {
        setState(() => loading = false);
      }
    }
  }

  bool get _nodeOnline => _nodeHealth?['status'] == 'ok';

  String _healthString(String key, String fallback) {
    final value = _nodeHealth?[key];
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  bool _healthBool(String key) {
    return _nodeHealth?[key] == true;
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

  Future<void> _saveCurrent() async {
    if (deviceConfig.isEmpty) return;

    final nameCtrl = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: StitchColors.surfaceContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Save Live Profile'),
          content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Profile Name',
              prefixIcon: Icon(Icons.bookmark_add_outlined),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL'),
            ),
            StitchPrimaryButton(
              onPressed: () async {
                final name = nameCtrl.text.trim().isEmpty
                    ? 'Live Node Snapshot'
                    : nameCtrl.text.trim();
                await StorageService.saveProfile(name, deviceConfig);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
                  showStitchMessage(context, 'Live node saved to Vault.');
                }
              },
              child: const Text(
                'SAVE',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      );
    } finally {
      nameCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = [
      {
        'label': 'CPU TEMP',
        'value': deviceConfig.isEmpty ? '--' : '${38 + deviceConfig.length} C',
      },
      {
        'label': 'HEAP',
        'value': deviceConfig.isEmpty
            ? '--'
            : '${160 + (deviceConfig.length * 6)} KB',
      },
    ];

    return StitchScaffold(
      floatingActionButton: deviceConfig.isEmpty
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppTheme.ctaGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: AppTheme.cyanGlowShadow,
              ),
              child: FloatingActionButton.extended(
                onPressed: _saveCurrent,
                backgroundColor: Colors.transparent,
                elevation: 0,
                label: const Text('SAVE TO VAULT'),
                icon: const Icon(Icons.save_alt_rounded),
              ),
            ),
      body: Column(
        children: [
          StitchTopBar(
            section: 'Live Node',
            trailing: IconButton(
              onPressed: _isRefreshing ? null : _loadCurrentConfig,
              icon: _isRefreshing && !loading
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
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: StitchColors.secondaryContainer,
                    ),
                  )
                : RefreshIndicator(
                    color: StitchColors.secondaryContainer,
                    backgroundColor: StitchColors.surfaceHigh,
                    onRefresh: _loadCurrentConfig,
                    child: ListView(
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      cacheExtent: 600,
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 380;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    StitchStatusDot(
                                      color: _nodeOnline
                                          ? StitchColors.primaryContainer
                                          : StitchColors.error,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _nodeOnline ? 'SYSTEM ONLINE' : 'NODE OFFLINE',
                                      style: TextStyle(
                                        color: _nodeOnline
                                            ? StitchColors.primaryContainer
                                            : StitchColors.error,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 2.0,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (compact)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          'ESP32-S3-WROOM-1',
                                          maxLines: 1,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineLarge
                                              ?.copyWith(fontSize: 24),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        deviceConfig.isEmpty
                                            ? 'No active live config loaded'
                                            : 'Pinned sensors: ${deviceConfig.length}  -  Live layout ready',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: stats
                                            .map(
                                              (item) => Expanded(
                                                child: Padding(
                                                  padding: EdgeInsets.only(
                                                    right: item == stats.first ? 10 : 0,
                                                  ),
                                                  child: StitchPanel(
                                                    padding: const EdgeInsets.all(16),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          item['label']!,
                                                          style: Theme.of(context)
                                                              .textTheme
                                                              .labelMedium,
                                                        ),
                                                        const SizedBox(height: 8),
                                                        Text(
                                                          item['value']!,
                                                          style: Theme.of(context)
                                                              .textTheme
                                                              .titleLarge
                                                              ?.copyWith(fontSize: 20),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ],
                                  )
                                else
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                'ESP32-S3-WROOM-1',
                                                maxLines: 1,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .headlineLarge
                                                    ?.copyWith(fontSize: 26),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              deviceConfig.isEmpty
                                                  ? 'No active live config loaded'
                                                  : 'Pinned sensors: ${deviceConfig.length}  -  Live layout ready',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Row(
                                        children: stats
                                            .map(
                                              (item) => Padding(
                                                padding: EdgeInsets.only(
                                                  left: item == stats.first ? 0 : 10,
                                                ),
                                                child: SizedBox(
                                                  width: 118,
                                                  child: StitchPanel(
                                                    padding: const EdgeInsets.all(16),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          item['label']!,
                                                          style: Theme.of(context)
                                                              .textTheme
                                                              .labelMedium,
                                                        ),
                                                        const SizedBox(height: 8),
                                                        Text(
                                                          item['value']!,
                                                          style: Theme.of(context)
                                                              .textTheme
                                                              .titleLarge
                                                              ?.copyWith(fontSize: 20),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ],
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        _buildConnectivityPanel(context),
                        const SizedBox(height: 16),
                        _buildDiagnosticsPanel(context),
                        const SizedBox(height: 16),
                        RepaintBoundary(
                          child: SensorMatrix(
                            deviceConfig: deviceConfig,
                            onLoad: widget.onLoadToConfig,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectivityPanel(BuildContext context) {
    final ssid = _healthString('ssid', 'NOT CONNECTED');
    final accessPointIp = _healthString('ip', '--');
    final clients = _healthString('clients', '0');
    final configCount = _healthString('configCount', deviceConfig.length.toString());
    final lockStatus = _nodeOnline
        ? (_healthBool('locked') ? 'LOCKED' : 'OPEN')
        : '--';

    return StitchPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StitchSectionLabel('Connectivity', icon: Icons.wifi_rounded),
          const SizedBox(height: 18),
          _metaRow('Node Status', _nodeOnline ? 'ONLINE' : 'OFFLINE'),
          _metaRow('SSID', ssid),
          _metaRow('AP IP', accessPointIp),
          _metaRow('Clients', clients),
          _metaRow('Saved Nodes', configCount),
          _metaRow('Security', lockStatus),
          if (_healthMessage != null) _metaRow('Note', _healthMessage!),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsPanel(BuildContext context) {
    final lines = _nodeOnline
        ? [
            '[wifi] Node AP reachable at ${_healthString('ip', '192.168.4.1')}',
            '[ap] SSID ${_healthString('ssid', 'AQUA_NODE')} with ${_healthString('clients', '0')} client(s)',
            '[node] Security ${_healthBool('locked') ? 'locked' : 'open'} and ${_healthString('configCount', deviceConfig.length.toString())} config slot(s) loaded',
          ]
        : [
            '[wifi] ESP32 health endpoint is not reachable.',
            '[hint] Connect this phone to the node Wi-Fi AP and pull to refresh.',
            '[local] Cached layout has ${deviceConfig.length} configured sensor node(s).',
          ];

    return StitchPanel(
      color: StitchColors.surfaceLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StitchSectionLabel('Diagnostics'),
          const SizedBox(height: 14),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                line,
                style: const TextStyle(
                  color: StitchColors.onSurfaceVariant,
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: StitchColors.onSurfaceVariant),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: StitchColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
