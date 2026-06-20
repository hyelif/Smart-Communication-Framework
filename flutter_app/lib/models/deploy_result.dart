/// Result of deploying a configuration to an ESP32 node.
class DeployResult {
  final bool success;
  final String? message;
  final int? statusCode;

  const DeployResult({
    required this.success,
    this.message,
    this.statusCode,
  });

  factory DeployResult.ok({String? message, int? statusCode}) => DeployResult(
        success: true,
        message: message,
        statusCode: statusCode,
      );

  factory DeployResult.fail({String? message, int? statusCode}) => DeployResult(
        success: false,
        message: message,
        statusCode: statusCode,
      );

  @override
  String toString() =>
      'DeployResult(success: $success, message: $message, statusCode: $statusCode)';
}
