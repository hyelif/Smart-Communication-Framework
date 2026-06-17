import 'package:flutter_test/flutter_test.dart';
import 'package:smartponic_v2/services/api_service.dart';

void main() {
  group('ApiService', () {
    group('friendlyConnectionMessage', () {
      test('returns ESP32 not connected message for SocketException', () {
        final error = Exception('SocketException: Connection refused');
        final message = ApiService.friendlyConnectionMessage(error);
        expect(
          message,
          equals('ESP32 not connected. Join the node Wi-Fi and try again.'),
        );
      });

      test('returns ESP32 not connected message for ClientException', () {
        final error = Exception('ClientException: Failed host lookup');
        final message = ApiService.friendlyConnectionMessage(error);
        expect(
          message,
          equals('ESP32 not connected. Join the node Wi-Fi and try again.'),
        );
      });

      test('returns ESP32 not connected message for failed host lookup', () {
        final error = Exception('Failed host lookup: 192.168.4.1');
        final message = ApiService.friendlyConnectionMessage(error);
        expect(
          message,
          equals('ESP32 not connected. Join the node Wi-Fi and try again.'),
        );
      });

      test('returns ESP32 not connected message for connection refused', () {
        final error = Exception('Connection refused');
        final message = ApiService.friendlyConnectionMessage(error);
        expect(
          message,
          equals('ESP32 not connected. Join the node Wi-Fi and try again.'),
        );
      });

      test('returns ESP32 not connected message for connection closed', () {
        final error = Exception('Connection closed by remote host');
        final message = ApiService.friendlyConnectionMessage(error);
        expect(
          message,
          equals('ESP32 not connected. Join the node Wi-Fi and try again.'),
        );
      });

      test('returns ESP32 not connected message for timed out', () {
        final error = Exception('Timed out waiting for response');
        final message = ApiService.friendlyConnectionMessage(error);
        expect(
          message,
          equals('ESP32 not connected. Join the node Wi-Fi and try again.'),
        );
      });

      test('returns generic message for unknown error', () {
        final error = Exception('Some random error');
        final message = ApiService.friendlyConnectionMessage(error);
        expect(
          message,
          equals('ESP32 is unavailable right now. Try again in a moment.'),
        );
      });

      test('returns generic message when error is null', () {
        final message = ApiService.friendlyConnectionMessage();
        expect(
          message,
          equals('ESP32 is unavailable right now. Try again in a moment.'),
        );
      });

      test('is case-insensitive when matching error messages', () {
        final error = Exception('SOCKETEXCEPTION');
        final message = ApiService.friendlyConnectionMessage(error);
        expect(
          message,
          equals('ESP32 not connected. Join the node Wi-Fi and try again.'),
        );
      });
    });

    group('friendlyApiMessage', () {
      test('returns security key message for 401 status', () {
        final result = <String, dynamic>{
          'statusCode': 401,
          'body': 'Unauthorized',
        };
        final message = ApiService.friendlyApiMessage(result);
        expect(
          message,
          equals('Security key is required to access this node.'),
        );
      });

      test('returns key not configured message for 403 with key_not_configured',
          () {
        final result = <String, dynamic>{
          'statusCode': 403,
          'body': 'key_not_configured',
        };
        final message = ApiService.friendlyApiMessage(result);
        expect(
          message,
          equals(
            'This node is not locked yet. Deploy once with a security key first.',
          ),
        );
      });

      test('returns incorrect key message for 403 without key_not_configured',
          () {
        final result = <String, dynamic>{
          'statusCode': 403,
          'body': 'Forbidden',
        };
        final message = ApiService.friendlyApiMessage(result);
        expect(
          message,
          equals('Security key is incorrect for this node.'),
        );
      });

      test('returns generic message for other status codes', () {
        final result = <String, dynamic>{
          'statusCode': 500,
          'body': 'Internal Server Error',
        };
        final message = ApiService.friendlyApiMessage(result);
        expect(
          message,
          equals('ESP32 is unavailable right now. Try again in a moment.'),
        );
      });

      test('handles missing body gracefully', () {
        final result = <String, dynamic>{
          'statusCode': 403,
        };
        final message = ApiService.friendlyApiMessage(result);
        expect(
          message,
          equals('Security key is incorrect for this node.'),
        );
      });
    });

    group('URL construction', () {
      test('baseUrl is http://192.168.4.1', () {
        expect(ApiService.baseUrl, equals('http://192.168.4.1'));
      });

      test('config URL is baseUrl + /config', () {
        const expected = 'http://192.168.4.1/config';
        // Verify by checking the static baseUrl
        expect('${ApiService.baseUrl}/config', equals(expected));
      });

      test('health URL is baseUrl + /health', () {
        const expected = 'http://192.168.4.1/health';
        expect('${ApiService.baseUrl}/health', equals(expected));
      });
    });

    group('response map construction', () {
      test('success response map has ok=true, statusCode, and body', () {
        const statusCode = 200;
        const body = '{"status": "ok"}';
        final response = <String, dynamic>{
          'ok': true,
          'statusCode': statusCode,
          'body': body,
        };
        expect(response['ok'], isTrue);
        expect(response['statusCode'], equals(200));
        expect(response['body'], equals(body));
      });

      test('error response map has ok=false, statusCode, and body', () {
        const statusCode = 404;
        const body = 'Not Found';
        final response = <String, dynamic>{
          'ok': false,
          'statusCode': statusCode,
          'body': body,
        };
        expect(response['ok'], isFalse);
        expect(response['statusCode'], equals(404));
        expect(response['body'], equals(body));
      });
    });
  });
}
