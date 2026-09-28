// Import dart:io to check the platform.
import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:movie/windowTitleBarController.dart';
import 'package:window_manager/window_manager.dart';

import 'app/routes/app_pages.dart';
import 'app_theme.dart';
import 'init_providers.dart';

// -----------------------------------------------------------
// CONTROLLER: Manages Window Bar Visibility
// -----------------------------------------------------------

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 100;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20;

  if (!kIsWeb) {
    if (Platform.isWindows) {
      await windowManager.ensureInitialized();

      const windowOptions = WindowOptions(
        titleBarStyle: TitleBarStyle.hidden, // 👈 hide native bar
        center: true,
      );

      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } else if (Platform.isAndroid) {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final double shortestSide =
          view.physicalSize.shortestSide / view.devicePixelRatio;

      const double tabletBreakpoint = 600.0;

      if (shortestSide >= tabletBreakpoint) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    }
  }

  // Load saved data (Continue Watching, My List, progress, caches) before any
  // screen reads it; otherwise the first reads see an empty store.
  await GetStorage.init();

  intiProviders();
  await initAsyncServices();
  runApp(const MyApp());
}

// -----------------------------------------------------------
// CUSTOM WINDOW BAR FOR WINDOWS
// -----------------------------------------------------------

// -----------------------------------------------------------
// APP
// -----------------------------------------------------------
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> initDeepLinks() async {
    _appLinks = AppLinks();

    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      debugPrint('Received deep link: $uri');
      _handleDeepLink(uri);
    });
  }

  // Launcher rows link to flutter-tv-app://com.lynoon.movie/details/<id>
  // (Trending) and /resume/<id> (Play Next).
  void _handleDeepLink(Uri uri) {
    if (uri.host != 'com.lynoon.movie') return;
    if (uri.scheme != 'flutter-tv-app' && uri.scheme != 'noon-tv-app') return;
    final segments = uri.pathSegments;
    if (segments.length != 2) return;
    final action = segments.first;
    if (action != 'details' && action != 'resume') return;
    final args = {'id': segments.last, 'resume': action == 'resume'};

    // A cold start lands here during the splash, which replaces the whole
    // stack when it finishes; it opens the pending link after that.
    if (Get.currentRoute.isEmpty || Get.currentRoute == AppPages.splash) {
      AppPages.pendingDetailArgs = args;
      return;
    }
    // A launcher link starts over from Home: whatever was open (a detail
    // page, the player) is closed first, so nothing keeps playing underneath
    // and the new title is the only one on the stack.
    Get.until((route) => route.settings.name == Routes.HOME_SCREEN || route.isFirst);
    Get.toNamed(Routes.SUBJECT_DETAIL, arguments: args, preventDuplicates: false);
  }

  @override
  Widget build(BuildContext context) {
    // 1. Initialize the controller here so it is available globally
    final titleBarController = Get.put(WindowTitleBarController());

    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent) {
          if (!kIsWeb &&
              Platform.isWindows &&
              event.logicalKey == LogicalKeyboardKey.escape) {

            // If exiting full screen via ESC, also ensure the bar comes back
            windowManager.setFullScreen(false);
            titleBarController.show();
          }
        }
      },
      child: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
        },
        child: GetMaterialApp(
          title: 'NoonFlix',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          initialRoute: AppPages.INITIAL,
          getPages: AppPages.routes,
          builder: (context, child) {
            return Scaffold(
              body: Column(
                children: [
                  // 2. Logic to show/hide the custom bar
                  if (!kIsWeb && Platform.isWindows)
                    Obx(() => titleBarController.isVisible.value
                        ? const CustomWindowBar()
                        : const SizedBox.shrink()),

                  Expanded(child: child ?? const SizedBox()),
                ],
              ),
            );
          },
        ),
      ),
    );

  }

}class CustomWindowBar extends StatelessWidget {
  const CustomWindowBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: Colors.black.withOpacity(0.9),
      child: Row(
        children: [
          // Drag area
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "NoonFlix",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
              ),
            ),
          ),

          // Minimize
          IconButton(
            icon: const Icon(Icons.remove, color: Colors.white),
            onPressed: () => windowManager.minimize(),
            iconSize: 20,
            splashRadius: 20,
          ),

          // Maximize / Restore
          IconButton(
            icon: const Icon(Icons.crop_square, color: Colors.white),
            onPressed: () async {
              bool isMax = await windowManager.isMaximized();
              isMax ? windowManager.unmaximize() : windowManager.maximize();
            },
            iconSize: 20,
            splashRadius: 20,
          ),

          // Close
          IconButton(
            icon: const Icon(Icons.close, color: Colors.redAccent),
            onPressed: () => windowManager.close(),
            iconSize: 20,
            splashRadius: 20,
          ),
        ],
      ),
    );
  }
}
