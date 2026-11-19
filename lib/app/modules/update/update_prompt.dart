import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app_theme.dart';
import '../../routes/app_pages.dart';
import '../../services/update_service.dart';
import '../../widgets/tv_focusable.dart';

/// At start-up, once Home is showing: offers a newer build if the download
/// page lists one. Quiet when there is none, when it was put off today, or
/// when the viewer has already moved on to another screen.
Future<void> offerUpdateOnStart() async {
  if (!UpdateService.supported) return;
  final update = await UpdateService.to.check();
  if (update == null || UpdateService.to.isSnoozed(update)) return;
  if (Get.currentRoute != Routes.HOME_SCREEN || Get.isDialogOpen == true || Get.isBottomSheetOpen == true) return;
  await Get.dialog(_UpdateDialog(update));
}

/// Settings → version row: checks now and says so either way.
Future<void> checkForUpdateManually() async {
  if (!UpdateService.supported) return;
  final update = await UpdateService.to.check();
  if (update != null) {
    await Get.dialog(_UpdateDialog(update));
    return;
  }
  final info = await PackageInfo.fromPlatform();
  Get.snackbar('Noon Flix is up to date', 'Version ${info.version} is the latest.',
      snackPosition: SnackPosition.BOTTOM, colorText: Colors.white);
}

/// Works with a remote (D-pad focus) and with touch.
class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog(this.update);
  final AppUpdate update;

  @override
  Widget build(BuildContext context) {
    final svc = UpdateService.to;

    Widget button(String label, VoidCallback onSelect, {bool primary = false}) => TvFocusable(
          autofocus: primary,
          onSelect: onSelect,
          builder: (context, focused) => AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white
                  : primary
                      ? kBrandPurple
                      : Colors.white12,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: TextStyle(
                    color: focused ? Colors.black : Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        );

    return PopScope(
      // Leaving mid-download stops it; nothing half-finished is ever installed.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) svc.cancelDownload();
      },
      child: Dialog(
        backgroundColor: const Color(0xFF1F1F27),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Obx(() {
              final stage = svc.stage.value;
              final fraction = svc.progress.value;
              final downloading = stage == UpdateStage.downloading;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(gradient: kBrandGradient, shape: BoxShape.circle),
                    child: const Icon(Icons.system_update_rounded, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 16),
                  Text('Noon Flix ${update.version} is here',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    switch (stage) {
                      UpdateStage.downloading => fraction == null
                          ? 'Downloading…'
                          : 'Downloading… ${(fraction * 100).round()}%',
                      UpdateStage.ready => 'Downloaded. Choose Install when Android asks.',
                      _ => 'Update to get the latest fixes and features.',
                    },
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                  ),
                  if (downloading) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 5,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation(kBrandPurple),
                      ),
                    ),
                  ],
                  if (svc.error.value.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(svc.error.value,
                        textAlign: TextAlign.center, style: const TextStyle(color: kBrandRed, fontSize: 13)),
                  ],
                  const SizedBox(height: 22),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      if (downloading)
                        button('Cancel', () => Get.back(), primary: true)
                      else ...[
                        button(
                          switch (stage) {
                            UpdateStage.ready => 'Install',
                            UpdateStage.failed => 'Try again',
                            _ => 'Update now',
                          },
                          () => stage == UpdateStage.ready ? svc.install() : svc.downloadAndInstall(update),
                          primary: true,
                        ),
                        button('Later', () {
                          svc.snooze(update);
                          Get.back();
                        }),
                      ],
                    ],
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
