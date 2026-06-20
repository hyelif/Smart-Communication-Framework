import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../utils/config_validator.dart';
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

class _DeviceScreenState extends State<DeviceScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> deviceConfig = [];
  Map<String, dynamic>? _nodeHealth;
  String? _healthMessage;
  bool loading = true;
  bool _isRefreshing = false;
  bool _hasLoadedOnce = false;

  late final AnimationController _entranceController;
  late final Animation<double> _entranceAnimation;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _entranceAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );
    widget.activeTabListenable.addListener(_handleActiveTabChanged);
    if (widget.activeTabListenable.value == widget.tabIndex) {
      _loadCurrentConfig(showLoader: true);
    } else {
      loading = false;
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    widget.activeTabListenable.removeListener(_handleActiveTabChanged);
    super.dispose();
  }

  void _handleActiveTabChanged() {
    if (widget.activeTabListenable.value == widget.tabIndex) {
      _loadCurrentConfig(showLoader: !_hasLoadedOnce);
    } else {
      // Stop entrance animation when not visible to save resources
      _entranceController.reset();
    }
  }

  Future<void> _loadCurrentConfig({bool showLoader = false}) async {
    if (_isRefreshing) return;
    if (showLoader && mounted) {
      setState(() => loading = true);
    }

    _isRefreshing = true;
    try {
      HapticFeedback.mediumImpact();

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
      final changed = !ConfigValidator.sameConfig(parsed, deviceConfig);
      final healthChanged = !mapEquals(nextHealth, _nodeHealth) ||
          nextHealthMessage != _healthMessage;
      if (changed || healthChanged || loading) {
        setState(() {
          deviceConfig = parsed;
          _nodeHealth = nextHealth;
          _healthMessage = nextHealthMessage;
          loading = false;
        });
        _entranceController.forward(from: 0.0);
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

  bool get _isOffline => !_nodeOnline && _hasLoadedOnce;

  String _healthString(String key, String fallback) {
    final value = _nodeHealth?[key];
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  bool _healthBool(String key) {
    return _nodeHealth?[key] == true;
  }

  int? _healthInt(String key) {
    final value = _nodeHealth?[key];
    if (value is num) return value.toInt();
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  String get _nodeTitle {
    return _healthString(
      'board',
      _healthString('chipModel', 'ESP32 Device'),
    );
  }

  String get _nodeSubtitle {
    if (_nodeOnline) {
      final chip = _healthString('chipModel', 'ESP32');
      final revision = _healthInt('chipRevision');
      final ssid = _healthString('ssid', 'AQUA_NODE');
      final chipLabel = revision == null ? chip : '$chip rev $revision';
      return '$chipLabel  |  AP $ssid';
    }

    return deviceConfig.isEmpty
        ? 'No active live config loaded'
        : 'Pinned sensors: ${deviceConfig.length}  -  Live layout ready';
  }

  String get _nodeStatusLabel {
    if (!_nodeOnline) {
      return 'NODE OFFLINE';
    }

    return '${_nodeTitle.toUpperCase()} ONLINE';
  }

  String _formatUptime(int? totalSeconds) {
    if (totalSeconds == null) return '--';

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
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
          title: const AutoSizeText(
            'Save Live Profile',
            maxLines: 1,
            minFontSize: 16,
          ),
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
              child: const AutoSizeText(
                'CANCEL',
                maxLines: 1,
                minFontSize: 10,
              ),
            ),
            StitchPrimaryButton(
              onPressed: () async {
                final name = nameCtrl.text.trim().isEmpty
                    ? 'Live Node Snapshot'
                    : nameCtrl.text.trim();
                await StorageService.saveProfile(name, deviceConfig);
                HapticFeedback.lightImpact();
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
                  showStitchMessage(context, 'Live node saved to Vault.');
                }
              },
              child: const AutoSizeText(
                'SAVE',
                style: TextStyle(fontWeight: FontWeight.w900),
                maxLines: 1,
                minFontSize: 10,
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
                label: const AutoSizeText(
                  'SAVE TO VAULT',
                  maxLines: 1,
                  minFontSize: 10,
                ),
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
                ? _buildSkeleton()
                : _buildContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
      children: [
        const StitchShimmer(width: 100, height: 11, borderRadius: 4),
        const SizedBox(height: 12),
        const StitchSkeletonPanel(height: 100, lineCount: 3, showIcon: false),
        const SizedBox(height: 24),
        const StitchSkeletonPanel(height: 200, lineCount: 5, showIcon: false),
        const SizedBox(height: 16),
        const StitchSkeletonPanel(height: 100, lineCount: 3, showIcon: false),
        const SizedBox(height: 16),
        ...List.generate(2, (i) => Padding(
          padding: EdgeInsets.only(bottom: i < 1 ? 12 : 0),
          child: const StitchSkeletonPanel(height: 80, lineCount: 2),
        )),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 380;

    return RefreshIndicator(
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
          Row(
            children: [
              if (_nodeOnline)
                const StitchPulseDot(
                  color: StitchColors.primaryContainer,
                  size: 10,
                )
              else
                const StitchStatusDot(
                  color: StitchColors.error,
                  size: 10,
                ),
              const SizedBox(width: 8),
              AutoSizeText(
                _nodeStatusLabel,
                style: TextStyle(
                  color: _nodeOnline
                      ? StitchColors.primaryContainer
                      : StitchColors.error,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.0,
                ),
                maxLines: 1,
                minFontSize: 9,
              ),
            ],
          ),
          const SizedBox(height: 12),
          FadeTransition(
            opacity: _entranceAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(_entranceAnimation),
              child: AnimatedOpacity(
                opacity: _isOffline ? 0.5 : 1.0,
                duration: const Duration(milliseconds: 400),
                child: Column(
                  children: [
                    _buildNodeInfo(context, compact),
                    const SizedBox(height: 24),
                    Container(
                      height: 1,
                      color: StitchColors.outlineVariant.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 24),
                    _buildConnectivityPanel(context),
                    const SizedBox(height: 16),
                    _buildSmartCommPanel(context),
                    const SizedBox(height: 16),
                    _buildDiagnosticsPanel(context),
                    const SizedBox(height: 16),
                    RepaintBoundary(
                      child: SensorMatrix(
                        deviceConfig: deviceConfig,
                        onLoad: widget.onLoadToConfig,
                        loading: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isOffline) ...[
            const SizedBox(height: 16),
            const StitchPanel.glass(
              child: Row(
                children: [
                  Icon(Icons.wifi_off_rounded, size: 18, color: StitchColors.error),
                  SizedBox(width: 10),
                  Expanded(
                    child: AutoSizeText(
                      'Node offline -- showing cached data. Pull to refresh.',
                      style: TextStyle(
                        color: StitchColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      minFontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNodeInfo(BuildContext context, bool compact) {
    final heapValue = _nodeOnline ? '${_healthString('heapKb', '--')} KB' : '--';
    final uptimeValue = _nodeOnline ? _formatUptime(_healthInt('uptimeSec')) : '--';

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AutoSizeText(
              _nodeTitle,
              maxLines: 1,
              style: Theme.of(context)
                  .textTheme
                  .headlineLarge
                  ?.copyWith(fontSize: 24),
              minFontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          AutoSizeText(
            _nodeSubtitle,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
            minFontSize: 11,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: StitchPanel(
                    padding: const EdgeInsets.all(16),
                    child: _buildMetricColumn('HEAP', heapValue, Icons.memory_rounded),
                  ),
                ),
              ),
              Expanded(
                child: StitchPanel(
                  padding: const EdgeInsets.all(16),
                  child: _buildMetricColumn('UPTIME', uptimeValue, Icons.timer_outlined),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AutoSizeText(
                  _nodeTitle,
                  maxLines: 1,
                  style: Theme.of(context)
                      .textTheme
                      .headlineLarge
                      ?.copyWith(fontSize: 26),
                  minFontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              AutoSizeText(
                _nodeSubtitle,
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 2,
                minFontSize: 11,
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Row(
          children: [
            StitchPanel(
              padding: const EdgeInsets.all(16),
              child: _buildMetricColumn('HEAP', heapValue, Icons.memory_rounded),
            ),
            const SizedBox(width: 10),
            StitchPanel(
              padding: const EdgeInsets.all(16),
              child: _buildMetricColumn('UPTIME', uptimeValue, Icons.timer_outlined),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricColumn(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: StitchColors.primaryContainer),
            const SizedBox(width: 4),
            AutoSizeText(
              label,
              style: Theme.of(context).textTheme.labelMedium,
              maxLines: 1,
              minFontSize: 9,
            ),
          ],
        ),
        const SizedBox(height: 8),
        AutoSizeText(
          value,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontSize: 20),
          maxLines: 1,
          minFontSize: 14,
        ),
      ],
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
      child: IntrinsicHeight(
        child: Row(
          children: [
            _leftAccent(StitchColors.primaryContainer),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const StitchSectionLabel('Connectivity', icon: Icons.wifi_rounded),
                  const SizedBox(height: 18),
                  _metaRow('Node Status', _nodeOnline ? 'ONLINE' : 'OFFLINE'),
                  _metaRow('Board', _healthString('board', '--')),
                  _metaRow('Chip', _healthString('chipModel', '--')),
                  _metaRow('SSID', ssid),
                  _metaRow('AP IP', accessPointIp),
                  _metaRow('Clients', clients),
                  _metaRow('Saved Nodes', configCount),
                  _metaRow('Security', lockStatus),
                  if (_healthMessage != null)
                    _metaRow('Note', _healthMessage!, multiline: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartCommPanel(BuildContext context) {
    final priority = _healthString('priority', '--');
    final reportMode = _healthString('reportMode', '--');
    final pendingQueue = _healthString('pendingQueue', '0');
    final nodeId = _healthString('nodeId', '1');
    final distance = _healthString('distance', '--');

    Color priorityColor;
    switch (priority.toUpperCase()) {
      case 'HIGH':
        priorityColor = StitchColors.error;
        break;
      case 'MEDIUM':
        priorityColor = const Color(0xFFFFA94D);
        break;
      default:
        priorityColor = StitchColors.primaryContainer;
    }

    return StitchPanel.glass(
      child: IntrinsicHeight(
        child: Row(
          children: [
            _leftAccent(StitchColors.secondary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const StitchSectionLabel('Smart Communication', icon: Icons.radar_rounded),
                  const SizedBox(height: 18),
                  _metaRow('Node ID', nodeId),
                  _metaRow('Distance', distance != '--' ? '$distance m' : '--'),
                  _metaRow(
                    'Priority',
                    priority != '--'
                        ? priority.toUpperCase()
                        : '--',
                    valueColor: priority != '--' ? priorityColor : null,
                  ),
                  _metaRow('Report Mode', reportMode != '--' ? reportMode.toUpperCase() : '--'),
                  _metaRow('Retry Queue', '$pendingQueue / 12'),
                  if (_healthMessage != null)
                    _metaRow('Note', _healthMessage!, multiline: true),
                ],
              ),
            ),
          ],
        ),
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

    return StitchPanel.glass(
      child: IntrinsicHeight(
        child: Row(
          children: [
            _leftAccent(StitchColors.tertiaryFixed),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const StitchSectionLabel('Diagnostics'),
                  const SizedBox(height: 14),
                  ...lines.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AutoSizeText(
                        line,
                        style: const TextStyle(
                          color: StitchColors.onSurfaceVariant,
                          fontFamily: 'monospace',
                          fontSize: 11,
                          height: 1.45,
                        ),
                        maxLines: 2,
                        minFontSize: 9,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _leftAccent(Color color) {
    return Container(
      width: 3,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.6),
            color.withValues(alpha: 0.0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _metaRow(
    String label,
    String value, {
    bool multiline = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment:
            multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 96,
            child: AutoSizeText(
              label,
              style: const TextStyle(color: StitchColors.onSurfaceVariant),
              maxLines: 1,
              minFontSize: 9,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AutoSizeText(
              value,
              textAlign: TextAlign.right,
              softWrap: multiline,
              maxLines: multiline ? 3 : 1,
              overflow: multiline ? TextOverflow.visible : TextOverflow.ellipsis,
              style: TextStyle(
                color: valueColor ?? StitchColors.primary,
                fontWeight: FontWeight.w600,
              ),
              minFontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
