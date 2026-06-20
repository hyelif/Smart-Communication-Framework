/// Health and status information from an ESP32 node.
class NodeHealth {
  final bool online;
  final String? board;
  final String? chipModel;
  final int? chipRevision;
  final String? ssid;
  final String? ip;
  final int? clients;
  final int? heapKb;
  final int? uptimeSec;
  final bool? locked;
  final int? configCount;
  final String? priority;
  final String? reportMode;
  final int? pendingQueue;
  final String? nodeId;
  final String? distance;

  const NodeHealth({
    required this.online,
    this.board,
    this.chipModel,
    this.chipRevision,
    this.ssid,
    this.ip,
    this.clients,
    this.heapKb,
    this.uptimeSec,
    this.locked,
    this.configCount,
    this.priority,
    this.reportMode,
    this.pendingQueue,
    this.nodeId,
    this.distance,
  });

  factory NodeHealth.fromMap(Map<String, dynamic> map) {
    return NodeHealth(
      online: map['status'] == 'ok',
      board: map['board']?.toString(),
      chipModel: map['chipModel']?.toString(),
      chipRevision: _parseInt(map['chipRevision']),
      ssid: map['ssid']?.toString(),
      ip: map['ip']?.toString(),
      clients: _parseInt(map['clients']),
      heapKb: _parseInt(map['heapKb']),
      uptimeSec: _parseInt(map['uptimeSec']),
      locked: map['locked'] == true,
      configCount: _parseInt(map['configCount']),
      priority: map['priority']?.toString(),
      reportMode: map['reportMode']?.toString(),
      pendingQueue: _parseInt(map['pendingQueue']),
      nodeId: map['nodeId']?.toString(),
      distance: map['distance']?.toString(),
    );
  }

  static int? _parseInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  @override
  String toString() => 'NodeHealth(online: $online, board: $board, chipModel: $chipModel)';
}
