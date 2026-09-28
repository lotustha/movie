import 'package:get/get.dart';

import 'app/data/api_provider.dart';
import 'app/services/auth_service.dart';
import 'app/services/download_service.dart';
import 'app/services/prefs.dart';
import 'app/services/sync_service.dart';

void intiProviders(){
  Get.lazyPut<ApiProvider>(()=>ApiProvider());
  Get.put(AppPrefs(), permanent: true);
  Get.put(AuthService(), permanent: true);
  Get.put(SyncService(), permanent: true);
}

/// Services that need async setup before the first screen.
Future<void> initAsyncServices() async {
  await Get.putAsync(() => DownloadService().init(), permanent: true);
}
