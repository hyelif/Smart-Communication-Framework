import 'package:get_it/get_it.dart';

import '../services/api_service.dart';
import '../services/device_service.dart';
import '../services/encryption_service.dart';
import '../services/file_exchange_service.dart';
import '../services/location_service.dart';
import '../services/nfc_payload_service.dart';
import '../services/nfc_service.dart';
import '../services/storage_service.dart';
import '../repositories/sensor_repository.dart';
import '../repositories/device_repository.dart';
import '../repositories/settings_repository.dart';

final getIt = GetIt.instance;

Future<void> setupDependencies() async {
  // Services
  getIt.registerLazySingleton<StorageService>(() => StorageService());
  getIt.registerLazySingleton<ApiService>(() => ApiService());
  getIt.registerLazySingleton<EncryptionService>(() => EncryptionService());
  getIt.registerLazySingleton<LocationService>(() => LocationService());
  getIt.registerLazySingleton<NfcService>(() => NfcService());
  getIt.registerLazySingleton<NfcPayloadService>(() => NfcPayloadService());
  getIt.registerLazySingleton<FileExchangeService>(() => FileExchangeService());
  getIt.registerLazySingleton<DeviceService>(() => DeviceService());

  // Repositories
  getIt.registerLazySingleton<SensorRepository>(
    () => SensorRepository(),
  );
  getIt.registerLazySingleton<DeviceRepository>(
    () => DeviceRepository(
      getIt<DeviceService>(),
      getIt<EncryptionService>(),
    ),
  );
  getIt.registerLazySingleton<SettingsRepository>(
    () => SettingsRepository(getIt<EncryptionService>()),
  );
}