import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/custom_ui.dart';

class ProfilesScreen extends StatefulWidget {
  final Function(List<Map<String, dynamic>>) onSelectProfile;

  const ProfilesScreen({super.key, required this.onSelectProfile});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  List<Map<String, dynamic>> profiles = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
    void didChangeDependencies() {
      super.didChangeDependencies();
      _refresh();
}

  Future<void> _refresh() async {
    final data = await StorageService.getProfiles();
    if (!mounted) return;
    setState(() => profiles = data);
  }

  @override
  Widget build(BuildContext context) {
    return StitchScaffold(
      body: Column(
        children: [
          const StitchTopBar(section: 'Vault'),
          Expanded(
            child: RefreshIndicator(
              color: StitchColors.secondaryContainer,
              backgroundColor: StitchColors.surfaceHigh,
              onRefresh: _refresh,
              child: ListView(
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
                      final crossAxisCount = constraints.maxWidth > 760 ? 3 : 1;
                      return GridView.count(
                        crossAxisCount: crossAxisCount,
                        shrinkWrap: true,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: crossAxisCount == 1 ? 2.8 : 1.45,
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
                                  await StorageService.deleteProfile(index);
                                  _refresh();
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
      glow: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 10),
          if (showPulse)
            const Row(
              children: [
                StitchStatusDot(size: 8),
                SizedBox(width: 8),
                Text(
                  'LIVE',
                  style: TextStyle(
                    color: StitchColors.primaryContainer,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          if (showPulse) const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 20,
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
