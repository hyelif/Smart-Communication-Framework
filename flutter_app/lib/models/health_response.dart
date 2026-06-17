class HealthResponse {
  final String status;
  final String? version;
  final int? uptime;
  final String? ip;
  final String? ssid;
  final int? rssi;

  const HealthResponse({
    required this.status,
    this.version,
    this.uptime,
    this.ip,
    this.ssid,
    this.rssi,
  });

  factory HealthResponse.fromMap(Map<String, dynamic> map) {
    return HealthResponse(
      status: map['status'] as String? ?? 'unknown',
      version: map['version'] as String?,
      uptime: _toInt(map['uptime']),
      ip: map['ip'] as String?,
      ssid: map['ssid'] as String?,
      rssi: _toInt(map['rssi']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'status': status,
      if (version != null) 'version': version,
      if (uptime != null) 'uptime': uptime,
      if (ip != null) 'ip': ip,
      if (ssid != null) 'ssid': ssid,
      if (rssi != null) 'rssi': rssi,
    };
  }

  HealthResponse copyWith({
    String? status,
    String? version,
    int? uptime,
    String? ip,
    String? ssid,
    int? rssi,
  }) {
    return HealthResponse(
      status: status ?? this.status,
      version: version ?? this.version,
      uptime: uptime ?? this.uptime,
      ip: ip ?? this.ip,
      ssid: ssid ?? this.ssid,
      rssi: rssi ?? this.rssi,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HealthResponse &&
        other.status == status &&
        other.version == version &&
        other.uptime == uptime &&
        other.ip == ip &&
        other.ssid == ssid &&
        other.rssi == rssi;
  }

  @override
  int get hashCode => Object.hash(status, version, uptime, ip, ssid, rssi);

  @override
  String toString() {
    return 'HealthResponse(status: $status, version: $version, '
        'uptime: $uptime, ip: $ip, ssid: $ssid, rssi: $rssi)';
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
