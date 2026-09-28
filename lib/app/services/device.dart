import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What kind of device this is, asked once at start-up.
class Device {
  Device._();

  /// An Android TV (the system's leanback feature, not a screen-size guess).
  static bool isTv = false;

  static Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      isTv = await const MethodChannel('com.lynoon.movie/tv_channel').invokeMethod<bool>('isTv') ?? false;
    } catch (_) {}
  }
}
