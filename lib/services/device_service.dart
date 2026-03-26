class DeviceService {
  Future<List<Map<String, dynamic>>> fetchLiveSensors() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return [];
  }
}
