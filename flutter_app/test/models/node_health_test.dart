import 'package:flutter_test/flutter_test.dart';
import 'package:smartponic_v2/models/node_health.dart';

void main() {
  group('NodeHealth', () {
    test('fromMap creates NodeHealth with all fields', () {
      final map = <String, dynamic>{
        'status': 'ok',
        'board': 'ESP32_DEV',
        'chipModel': 'ESP32',
        'chipRevision': 3,
        'ssid': 'AQUA_NODE',
        'ip': '192.168.4.1',
        'clients': 2,
        'heapKb': 240,
        'uptimeSec': 3600,
        'locked': true,
        'configCount': 5,
        'priority': 'LOW',
        'reportMode': 'NORMAL',
        'pendingQueue': 0,
        'nodeId': '1',
        'distance': '10.5',
      };

      final health = NodeHealth.fromMap(map);
      expect(health.online, isTrue);
      expect(health.board, 'ESP32_DEV');
      expect(health.chipModel, 'ESP32');
      expect(health.chipRevision, 3);
      expect(health.ssid, 'AQUA_NODE');
      expect(health.ip, '192.168.4.1');
      expect(health.clients, 2);
      expect(health.heapKb, 240);
      expect(health.uptimeSec, 3600);
      expect(health.locked, isTrue);
      expect(health.configCount, 5);
      expect(health.priority, 'LOW');
      expect(health.reportMode, 'NORMAL');
      expect(health.pendingQueue, 0);
      expect(health.nodeId, '1');
      expect(health.distance, '10.5');
    });

    test('fromMap handles offline node', () {
      final map = <String, dynamic>{
        'status': 'error',
      };

      final health = NodeHealth.fromMap(map);
      expect(health.online, isFalse);
      expect(health.board, isNull);
    });

    test('fromMap handles empty map', () {
      final health = NodeHealth.fromMap(<String, dynamic>{});
      expect(health.online, isFalse);
    });

    test('fromMap handles null values', () {
      final map = <String, dynamic>{
        'status': 'ok',
        'board': null,
        'chipModel': null,
        'heapKb': null,
        'uptimeSec': null,
      };

      final health = NodeHealth.fromMap(map);
      expect(health.online, isTrue);
      expect(health.board, isNull);
      expect(health.heapKb, isNull);
    });
  });
}
