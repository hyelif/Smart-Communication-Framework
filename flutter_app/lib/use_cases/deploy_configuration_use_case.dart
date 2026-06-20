import '../models/deploy_result.dart';
import '../services/api_service.dart';

/// Deploys a node configuration to an ESP32 device.
///
/// Takes a normalized config list and security key, sends it to the
/// ESP32 node API, and returns a [DeployResult].
class DeployConfigurationUseCase {
  /// Deploy [configWithMetadata] to the node secured by [securityKey].
  ///
  /// Returns a [DeployResult] indicating success or failure.
  Future<DeployResult> call(
    Map<String, dynamic> configWithMetadata,
    String securityKey,
  ) async {
    try {
      final result = await ApiService.sendConfigWithMetadata(
        configWithMetadata,
        securityKey,
      );

      if (result['ok'] == true) {
        return DeployResult.ok(
          message: 'Config deployed to ESP32 successfully.',
          statusCode: result['statusCode'] as int?,
        );
      }

      return DeployResult.fail(
        message: ApiService.friendlyApiMessage(result),
        statusCode: result['statusCode'] as int?,
      );
    } catch (e) {
      return DeployResult.fail(
        message: ApiService.friendlyConnectionMessage(e),
      );
    }
  }
}
