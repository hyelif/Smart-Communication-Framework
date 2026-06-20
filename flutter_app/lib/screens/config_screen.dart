import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/config/config_controller.dart';
import '../features/config/widgets/action_buttons.dart';
import '../features/config/widgets/add_node_sheet.dart';
import '../features/config/widgets/config_list_section.dart';
import '../features/config/widgets/gps_location_panel.dart';
import '../features/config/widgets/pin_info_panel.dart';
import '../features/config/widgets/security_key_panel.dart';
import '../features/config/widgets/variant_selector.dart';
import '../features/nfc/nfc_onboarding_sheet.dart';
import '../utils/config_validator.dart';
import '../widgets/app_theme.dart';
import '../widgets/custom_ui.dart';

class ConfigScreen extends ConsumerStatefulWidget {
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
  ConsumerState<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends ConsumerState<ConfigScreen> {
  @override
  void initState() {
    super.initState();
    // Sync the Riverpod state with the external ValueNotifier on first load
    final state = ref.read(configControllerProvider);
    if (state.config.isNotEmpty) {
      widget.configNotifier.value = state.config;
    }
  }

  void _showFeedback(String message, {bool isError = false}) {
    showStitchMessage(context, message, isError: isError);
  }

  Future<void> _showAddNodeSheet() async {
    final state = ref.read(configControllerProvider);
    if (state.config.length >= ConfigValidator.maxFirmwareConfigSlots) {
      _showFeedback(
        'ESP32 firmware supports only ${ConfigValidator.maxFirmwareConfigSlots} GPIO config slots.',
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
      builder: (_) => AddNodeSheet(existingConfig: state.config),
    );

    if (!mounted || item == null) return;
    ref.read(configControllerProvider.notifier).addNode(item);
    widget.configNotifier.value = ref.read(configControllerProvider).config;
  }

  Future<void> _prepareDirectNfcTap() async {
    final controller = ref.read(configControllerProvider.notifier);
    await controller.prepareDirectNfcTap();

    if (!mounted) return;
    final state = ref.read(configControllerProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NfcOnboardingSheet(
        configNotifier: widget.configNotifier,
        securityKey: state.securityKey,
        aesKey: state.aesKey,
        onComplete: () {
          Navigator.pop(context);
          _showFeedback('NFC configuration deployed successfully!');
        },
        onError: (error) {
          Navigator.pop(context);
          _showFeedback(error, isError: true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(configControllerProvider);
    final controller = ref.read(configControllerProvider.notifier);

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
            onPressed: state.isDeploying
                ? null
                : (state.is30Pin
                    ? () => controller.deployToNode().then((_) {
                          final s = ref.read(configControllerProvider);
                          if (s.feedbackMessage != null) {
                            _showFeedback(s.feedbackMessage!,
                                isError: s.feedbackIsError);
                            controller.clearFeedback();
                          }
                        })
                    : _prepareDirectNfcTap),
            backgroundColor: Colors.transparent,
            elevation: 0,
            label: AutoSizeText(
              state.isDeploying
                  ? 'DEPLOYING...'
                  : (state.is30Pin ? 'DEPLOY TO NODE' : 'PREPARE NFC TAP'),
              maxLines: 1,
              minFontSize: 10,
            ),
            icon: state.isDeploying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: StitchColors.onSecondaryContainer,
                    ),
                  )
                : Icon(state.is30Pin
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
              onPressed: state.isRefreshingPage
                  ? null
                  : () => controller.saveSnapshot().then((_) {
                        final s = ref.read(configControllerProvider);
                        if (s.feedbackMessage != null) {
                          _showFeedback(s.feedbackMessage!,
                              isError: s.feedbackIsError);
                          controller.clearFeedback();
                        }
                      }),
              icon: state.isRefreshingPage
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.bookmark_add_outlined,
                      color: StitchColors.primaryContainer,
                    ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => controller.loadFromNode().then((_) {
                final s = ref.read(configControllerProvider);
                if (s.feedbackMessage != null) {
                  _showFeedback(s.feedbackMessage!, isError: s.feedbackIsError);
                  controller.clearFeedback();
                }
              }),
              color: StitchColors.secondaryContainer,
              backgroundColor: StitchColors.surfaceHigh,
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                cacheExtent: 700,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 220),
                children: [
                  // Title row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AutoSizeText(
                              'Architect',
                              style: Theme.of(context).textTheme.displayMedium,
                              maxLines: 1,
                              minFontSize: 20,
                            ),
                            const SizedBox(height: 8),
                            AutoSizeText(
                              'Build and deploy your node layout directly from this panel.',
                              style: Theme.of(context).textTheme.bodyMedium,
                              maxLines: 2,
                              minFontSize: 11,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => controller.saveSnapshot().then((_) {
                          final s = ref.read(configControllerProvider);
                          if (s.feedbackMessage != null) {
                            _showFeedback(s.feedbackMessage!,
                                isError: s.feedbackIsError);
                            controller.clearFeedback();
                          }
                        }),
                        icon: const Icon(
                          Icons.bookmark_add_outlined,
                          color: StitchColors.primaryContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Variant selector
                  VariantSelector(
                    selected: state.selectedVariant,
                    onChanged: controller.setVariant,
                  ),
                  const SizedBox(height: 24),

                  // Security key panel
                  SecurityKeyPanel(
                    securityKey: state.securityKey,
                    aesKey: state.aesKey,
                    isKeyVisible: state.isKeyVisible,
                    onSecurityKeyChanged: controller.setSecurityKey,
                    onAesKeyChanged: controller.setAesKey,
                    onToggleVisibility: controller.toggleKeyVisibility,
                  ),
                  const SizedBox(height: 16),

                  // GPS location panel
                  GpsLocationPanel(
                    latitude: state.latitude,
                    longitude: state.longitude,
                    isFetchingLocation: state.isFetchingLocation,
                    onLatitudeChanged: controller.setLatitude,
                    onLongitudeChanged: controller.setLongitude,
                    onCapture: controller.fetchCurrentLocation,
                  ),
                  const SizedBox(height: 16),

                  // Pin info panel
                  const PinInfoPanel(),
                  const SizedBox(height: 20),

                  // Action buttons
                  ActionButtons(
                    isDeploying: state.isDeploying,
                    isLoadingNode: state.isLoadingNode,
                    isImportingFile: state.isImportingFile,
                    isExportingFile: state.isExportingFile,
                    isWritingNfc: state.isWritingNfc,
                    selectedVariant: state.selectedVariant,
                    onDeploy: () => controller.deployToNode().then((_) {
                      final s = ref.read(configControllerProvider);
                      if (s.feedbackMessage != null) {
                        _showFeedback(s.feedbackMessage!,
                            isError: s.feedbackIsError);
                        controller.clearFeedback();
                      }
                    }),
                    onLoadFromNode: () => controller.loadFromNode().then((_) {
                      final s = ref.read(configControllerProvider);
                      if (s.feedbackMessage != null) {
                        _showFeedback(s.feedbackMessage!,
                            isError: s.feedbackIsError);
                        controller.clearFeedback();
                      }
                    }),
                    onWriteNfc: () => controller.writeNfcTag().then((_) {
                      final s = ref.read(configControllerProvider);
                      if (s.feedbackMessage != null) {
                        _showFeedback(s.feedbackMessage!,
                            isError: s.feedbackIsError);
                        controller.clearFeedback();
                      }
                    }),
                    onImport: () => controller.importFromFile().then((_) {
                      final s = ref.read(configControllerProvider);
                      if (s.feedbackMessage != null) {
                        _showFeedback(s.feedbackMessage!,
                            isError: s.feedbackIsError);
                        controller.clearFeedback();
                      }
                    }),
                    onExport: () => controller.exportToFile().then((_) {
                      final s = ref.read(configControllerProvider);
                      if (s.feedbackMessage != null) {
                        _showFeedback(s.feedbackMessage!,
                            isError: s.feedbackIsError);
                        controller.clearFeedback();
                      }
                    }),
                    onAddNode: _showAddNodeSheet,
                  ),
                  const SizedBox(height: 20),

                  // Config list
                  ConfigListSection(
                    config: state.config,
                    onRemoveNode: (index) {
                      controller.removeNode(index);
                      widget.configNotifier.value =
                          ref.read(configControllerProvider).config;
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
