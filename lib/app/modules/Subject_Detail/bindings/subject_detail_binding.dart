import 'package:get/get.dart';

import '../controllers/subject_detail_controller.dart';

class SubjectDetailBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SubjectDetailController>(
      () => SubjectDetailController(),
    );
  }
}
