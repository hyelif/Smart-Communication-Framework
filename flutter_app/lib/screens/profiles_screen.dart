import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/custom_ui.dart';

class ProfilesScreen extends StatefulWidget {
  final Function(List<Map<String, dynamic>>) onSelectProfile;
  final ValueListenable<int> activeTabListenable;
  final int tabIndex;

  const ProfilesScreen({
    super.key,
    required this.onSelectProfile,
    required this.activeTabListenable,
    required this.tabIndex,
  });

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  List<Map<String, dynamic>> profiles = [];
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    widget.activeTabListenable.addListener(_handleActiveTabChanged);
    if (widget.activeTabListenable.value == widget.tabIndex) {
      _refresh();
    }
  }

  @override
  void dispose() {
    widget.activeTabListenable.removeListener(_handleActiveTabChanged);
    super.dispose();
  }

  void _handleActiveTabChanged() {
    if (widget.activeTabListenable.value == widget.tabIndex) {
      _refresh();
    }
  }

  bool _sameProfiles(
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

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final data = await StorageService.getProfiles();
      if (!mounted) return;
      if (!_sameProfiles(data, profiles)) {
        setState(() => profiles = data);
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StitchScaffold(
      body: Column(
        children: [
          StitchTopBar(
            section: 'Vault',
            trailing: IconButton(
              onPressed: _isRefreshing ? null : _refresh,
              icon: _isRefreshing
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
              color: StitchColors.secondaryContainer,
              backgroundColor: StitchColors.surfaceHigh,
              onRefresh: _refresh,
              child: ListView(
                cacheExtent: 500,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
                children: [
                  Wrap(
                    runSpacing: 12,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      SizedBox(
                        width: MediaQuery.of(context).size.width - 120,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Vault',
                                style: Theme.of(context).textTheme.displayMedium,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Secure profile storage for your node snapshots.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'STORAGE UNIT 01',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: 56,
                    height: 4,
                    decoration: BoxDecoration(
                      color: StitchColors.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  const SizedBox(height: 22),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = 3;
                      return GridView.count(
                        crossAxisCount: crossAxisCount,
                        shrinkWrap: true,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: constraints.maxWidth > 760 ? 1.9 : 1.15,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildStatTile(
                            context,
                            'TOTAL NODES',
                            profiles.length.toString(),
                          ),
                          _buildStatTile(
                            context,
                            'CLOUD SYNC',
                            profiles.isEmpty ? 'IDLE' : 'ACTIVE',
                            showPulse: profiles.isNotEmpty,
                          ),
                          _buildStatTile(context, 'ENCRYPTION', 'AES-256'),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(
                        child: StitchSectionLabel(
                          'Saved Configurations',
                          icon: Icons.inventory_2_outlined,
                        ),
                      ),
                      Text(
                        'SORT BY: RECENT',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (profiles.isEmpty)
                    const StitchEmptyState(
                      title: 'Vault Is Empty',
                      subtitle:
                          'Save a live node snapshot and it will appear here for fast reloads.',
                      icon: Icons.inventory_2_outlined,
                    )
                  else
                    ...profiles.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final cfg = List<Map<String, dynamic>>.from(
                        item['config'] as List,
                      );

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: StitchPanel(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name']?.toString() ??
                                          'Unnamed Profile',
                                      style:
                                          Theme.of(context).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        Text(
                                          '${cfg.length} SENSORS',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge,
                                        ),
                                        Text(
                                          _formatTime(item['time']?.toString()),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              StitchPrimaryButton(
                                onPressed: () => widget.onSelectProfile(cfg),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: const Text(
                                  'LOAD',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: StitchColors.onSecondaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () async {
                                  final updated = List<Map<String, dynamic>>.from(
                                    profiles,
                                  )..removeAt(index);
                                  setState(() => profiles = updated);
                                  await StorageService.deleteProfile(index);
                                },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: StitchColors.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile(
    BuildContext context,
    String label,
    String value, {
    bool showPulse = false,
  }) {
    return StitchPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          if (showPulse)
            const Row(
              children: [
                StitchStatusDot(size: 6),
                SizedBox(width: 6),
                Text(
                  'LIVE',
                  style: TextStyle(
                    color: StitchColors.primaryContainer,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          if (showPulse) const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 17,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String? raw) {
    if (raw == null || raw.isEmpty) return 'RECENT';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return 'RECENT';
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }
}
