import 'package:get/get.dart';

class WindowTitleBarController extends GetxController {
  // Observable boolean: true = show bar, false = hide bar
  final isVisible = true.obs;

  void hide() => isVisible.value = false;
  void show() => isVisible.value = true;
  void toggle() => isVisible.value = !isVisible.value;
}