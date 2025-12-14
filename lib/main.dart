// Import dart:io to check the platform.
import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
// Import window_manager for Windows-specific code.
import 'package:window_manager/window_manager.dart';

import 'app/routes/app_pages.dart';
import 'app_theme.dart';
import 'init_providers.dart';

void main() async {
  // Always required on startup.
  WidgetsFlutterBinding.ensureInitialized();

  // --- PLATFORM-SPECIFIC INITIALIZATION ---
  if (!kIsWeb) {
    // --- Windows-Specific Setup ---
    if (Platform.isWindows) {
      await windowManager.ensureInitialized();
      WindowOptions windowOptions = const WindowOptions(
        titleBarStyle: TitleBarStyle.hidden,
        center: true,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setFullScreen(true);
        await windowManager.show();
        await windowManager.focus();
      });
    }
    // --- Android-Specific Setup ---
    else if (Platform.isAndroid) {
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

  // --- Common Initialization for All Platforms ---
  intiProviders();
  runApp(const MyApp());
}

// MODIFIED: Converted to a StatefulWidget to manage the deep link listener's lifecycle.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // --- NEW: Deep Link Handling Logic from the Guide ---
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

  /// Initializes the listener for incoming app links.
  Future<void> initDeepLinks() async {
    _appLinks = AppLinks();

    // Listen for incoming deep links while the app is running.
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      debugPrint('Received deep link: $uri');
      _handleDeepLink(uri);
    });
  }

  /// Parses the deep link URI and navigates to the correct screen.
  void _handleDeepLink(Uri uri) {
    // Example URI from Google TV: flutter-tv-app://com.lynoon.movie/details/12345
    if (uri.scheme == 'flutter-tv-app' && uri.host == 'com.lynoon.movie') {
      final pathSegments = uri.pathSegments;
      // Ensure the link is for a details page, e.g., /details/some_id
      if (pathSegments.length == 2 && pathSegments.first == 'details') {
        final subjectId = pathSegments.last;
        // Use GetX to navigate, passing the movie's ID as an argument.
        // This assumes a '/details' route is defined in your AppPages.
        Get.toNamed(Routes.SUBJECT_DETAIL, arguments: subjectId);
      }
    }
  }
  // --- END: Deep Link Handling Logic ---

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(), // Required to capture key events.
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent) {
          if (!kIsWeb &&
              Platform.isWindows &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            windowManager.setFullScreen(false);
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
        ),
      ),
    );
  }
}
