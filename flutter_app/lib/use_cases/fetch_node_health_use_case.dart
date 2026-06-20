import '../models/node_health.dart';
import '../services/api_service.dart';

/// Fetches health status from an ESP32 node.
///
/// Calls the node's /health endpoint and returns a [NodeHealth]
/// object, or null if the node is unreachable.
class FetchNodeHealthUseCase {
  /// Fetch health from the node.
  ///
  /// Returns [NodeHealth] on success, or null if the node is
  /// unreachable or returns an error.
  Future<NodeHealth?> call() async {
    try {
      final result = await ApiService.fetchHealth();
      if (result['ok'] == true && result['data'] is Map<String, dynamic>) {
        return NodeHealth.fromMap(
          result['data'] as Map<String, dynamic>,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
