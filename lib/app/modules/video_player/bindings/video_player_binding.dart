import 'package:get/get.dart';

import '../controllers/video_player_controller.dart';

class VideoPlayerBinding extends Bindings {
  @override
  void dependencies() {
    // Always a fresh player. A player left underneath another route (e.g. a
    // launcher link opened while one was playing) would otherwise be found
    // again by lazyPut and replay its old title for every new one.
    if (Get.isRegistered<CustomVideoPlayerController>()) {
      Get.delete<CustomVideoPlayerController>(force: true);
    }
    Get.lazyPut<CustomVideoPlayerController>(
      () => CustomVideoPlayerController(),
    );
  }
}
