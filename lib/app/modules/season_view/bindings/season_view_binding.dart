import 'package:get/get.dart';

import '../controllers/season_view_controller.dart';

class SeasonViewBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SeasonViewController>(
      () => SeasonViewController(),
    );
  }
}
