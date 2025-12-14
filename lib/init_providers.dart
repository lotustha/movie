import 'package:get/get.dart';

import 'app/data/api_provider.dart';

void intiProviders(){
  Get.lazyPut<ApiProvider>(()=>ApiProvider());
}