import '../../../../utils/config_validator.dart';

/// Complete state for the Config (Architect) screen.
///
/// Encapsulates all form fields, loading flags, and the config list
/// into a single immutable object managed by [ConfigController].
class ConfigState {
  final List<Map<String, dynamic>> config;
  final String securityKey;
  final String aesKey;
  final String latitude;
  final String longitude;
  final Esp32Variant selectedVariant;
  final bool isKeyVisible;
  final bool isDeploying;
  final bool isLoadingNode;
  final bool isRefreshingPage;
  final bool isImportingFile;
  final bool isExportingFile;
  final bool isFetchingLocation;
  final bool isWritingNfc;
  final String? feedbackMessage;
  final bool feedbackIsError;

  const ConfigState({
    this.config = const [],
    this.securityKey = '',
    this.aesKey = 'SmartPonic123456',
    this.latitude = '',
    this.longitude = '',
    this.selectedVariant = Esp32Variant.esp32Node30Pin,
    this.isKeyVisible = false,
    this.isDeploying = false,
    this.isLoadingNode = false,
    this.isRefreshingPage = false,
    this.isImportingFile = false,
    this.isExportingFile = false,
    this.isFetchingLocation = false,
    this.isWritingNfc = false,
    this.feedbackMessage,
    this.feedbackIsError = false,
  });

  ConfigState copyWith({
    List<Map<String, dynamic>>? config,
    String? securityKey,
    String? aesKey,
    String? latitude,
    String? longitude,
    Esp32Variant? selectedVariant,
    bool? isKeyVisible,
    bool? isDeploying,
    bool? isLoadingNode,
    bool? isRefreshingPage,
    bool? isImportingFile,
    bool? isExportingFile,
    bool? isFetchingLocation,
    bool? isWritingNfc,
    String? feedbackMessage,
    bool? feedbackIsError,
    bool clearFeedback = false,
  }) {
    return ConfigState(
      config: config ?? this.config,
      securityKey: securityKey ?? this.securityKey,
      aesKey: aesKey ?? this.aesKey,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      selectedVariant: selectedVariant ?? this.selectedVariant,
      isKeyVisible: isKeyVisible ?? this.isKeyVisible,
      isDeploying: isDeploying ?? this.isDeploying,
      isLoadingNode: isLoadingNode ?? this.isLoadingNode,
      isRefreshingPage: isRefreshingPage ?? this.isRefreshingPage,
      isImportingFile: isImportingFile ?? this.isImportingFile,
      isExportingFile: isExportingFile ?? this.isExportingFile,
      isFetchingLocation: isFetchingLocation ?? this.isFetchingLocation,
      isWritingNfc: isWritingNfc ?? this.isWritingNfc,
      feedbackMessage: clearFeedback ? null : (feedbackMessage ?? this.feedbackMessage),
      feedbackIsError: clearFeedback ? false : (feedbackIsError ?? this.feedbackIsError),
    );
  }

  bool get hasConfig => config.isNotEmpty;
  bool get is30Pin => selectedVariant == Esp32Variant.esp32Node30Pin;
  bool get is38Pin => selectedVariant == Esp32Variant.esp32Node38Pin;
}
