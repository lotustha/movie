import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'config.dart';

/// A newer build listed on the download page.
class AppUpdate {
  const AppUpdate({required this.version, required this.apkUrl});
  final String version;
  final String apkUrl;
}

enum UpdateStage { idle, downloading, ready, failed }

/// Updates for the sideloaded Android app. The download page
/// (mugenstream.fun/apps/noonflix) is the source of truth: when the version
/// it lists is newer than this build, the app offers it, downloads the APK
/// and hands it to Android's installer. Android asks the viewer to confirm
/// every install of a sideloaded app, so that last tap can't be skipped.
///
/// To ship an update: upload the new APK there and set its version (it must
/// be higher than the installed one, e.g. 1.2.0 -> 1.2.1).
class UpdateService extends GetxService {
  static UpdateService get to => Get.find<UpdateService>();

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static const _channel = MethodChannel('com.lynoon.movie/tv_channel');
  static const _kSnoozed = 'update_snoozed'; // {version, at}
  static const _snoozeFor = Duration(hours: 24);

  final GetStorage _s = GetStorage();
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  final Rxn<AppUpdate> available = Rxn<AppUpdate>();
  final Rx<UpdateStage> stage = UpdateStage.idle.obs;

  /// 0..1 while downloading; null when the size isn't known.
  final RxnDouble progress = RxnDouble();
  final RxString error = ''.obs;

  CancelToken? _cancel;
  File? _apk;

  /// Asks the download page for its version. Returns the update when it is
  /// newer than this build, else null (also when the page can't be reached).
  Future<AppUpdate?> check() async {
    if (!supported) return null;
    try {
      final r = await _dio.get('${AppConfig.nexusApi}/api/apps/${AppConfig.appSlug}');
      final update = parseListing(r.data, (await PackageInfo.fromPlatform()).version);
      available.value = update;
      if (update == null) _clearDownloads();
      return update;
    } catch (e) {
      debugPrint('update check: $e');
      return null;
    }
  }

  /// The update a listing offers to a build at [installed], or null.
  @visibleForTesting
  static AppUpdate? parseListing(dynamic listing, String installed) {
    if (listing is! Map) return null;
    final version = '${listing['version'] ?? ''}'.trim();
    if (version.isEmpty || !isNewer(version, installed)) return null;
    String? url;
    for (final link in listing['links'] as List? ?? const []) {
      if (link is! Map) continue;
      final u = '${link['url'] ?? ''}';
      final isApk = '${link['platform']}'.toUpperCase() == 'APK' || u.toLowerCase().endsWith('.apk');
      if (isApk && u.startsWith('https://')) {
        url = u;
        break;
      }
    }
    return url == null ? null : AppUpdate(version: version, apkUrl: url);
  }

  /// Whether version [a] is higher than [b], comparing the dotted numbers
  /// ("1.10.0" > "1.9.3"); a build suffix ("+3", "-beta") is ignored.
  static bool isNewer(String a, String b) {
    List<int> parts(String v) => v
        .split(RegExp(r'[+\-]'))
        .first
        .split('.')
        .map((p) => int.tryParse(RegExp(r'\d+').stringMatch(p) ?? '') ?? 0)
        .toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < x.length || i < y.length; i++) {
      final l = i < x.length ? x[i] : 0, r = i < y.length ? y[i] : 0;
      if (l != r) return l > r;
    }
    return false;
  }

  /// "Later" on [update]: it isn't offered again by itself for a day.
  void snooze(AppUpdate update) =>
      _s.write(_kSnoozed, {'version': update.version, 'at': DateTime.now().millisecondsSinceEpoch});

  bool isSnoozed(AppUpdate update) {
    final raw = _s.read(_kSnoozed);
    if (raw is! Map || raw['version'] != update.version) return false;
    final at = DateTime.fromMillisecondsSinceEpoch((raw['at'] as num?)?.toInt() ?? 0);
    return DateTime.now().difference(at) < _snoozeFor;
  }

  Future<Directory> _dir() async =>
      Directory('${(await getTemporaryDirectory()).path}/updates').create(recursive: true);

  /// Installed builds don't need their installers any more.
  Future<void> _clearDownloads() async {
    try {
      final dir = await _dir();
      await for (final f in dir.list()) {
        await f.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// Downloads [update] (unless it is already here) and opens the installer.
  Future<void> downloadAndInstall(AppUpdate update) async {
    if (stage.value == UpdateStage.downloading) return;
    error.value = '';
    try {
      final dir = await _dir();
      final file = File('${dir.path}/noonflix-${update.version}.apk');
      if (!await file.exists()) {
        stage.value = UpdateStage.downloading;
        progress.value = null;
        await for (final old in dir.list()) {
          await old.delete(recursive: true); // older or unfinished downloads
        }
        final part = File('${file.path}.part');
        _cancel = CancelToken();
        var expected = -1;
        await _dio.download(
          update.apkUrl,
          part.path,
          cancelToken: _cancel,
          options: Options(receiveTimeout: const Duration(minutes: 30)),
          onReceiveProgress: (got, total) {
            expected = total;
            progress.value = total > 0 ? got / total : null;
          },
        );
        if (expected > 0 && await part.length() != expected) {
          throw const FileSystemException('The download was cut short.');
        }
        await part.rename(file.path);
      }
      _apk = file;
      stage.value = UpdateStage.ready;
      await install();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        stage.value = UpdateStage.idle;
        return;
      }
      _fail("The update couldn't be downloaded. Check your connection and try again.");
    } catch (e) {
      debugPrint('update download: $e');
      _fail("The update couldn't be downloaded. Try again.");
    }
  }

  void _fail(String message) {
    error.value = message;
    stage.value = UpdateStage.failed;
  }

  void cancelDownload() => _cancel?.cancel();

  /// Opens Android's installer on the downloaded APK.
  Future<void> install() async {
    final apk = _apk;
    if (apk == null) return;
    try {
      await _channel.invokeMethod('installApk', {'path': apk.path});
    } on PlatformException catch (e) {
      debugPrint('installApk: ${e.message}');
      _fail("The installer couldn't be opened. Download the update from mugenstream.fun/apps/noonflix.");
    }
  }
}
