import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../routes/app_pages.dart';
import '../../../services/auth_service.dart';
import '../../../services/device.dart';
import '../../account/tv_sign_in_view.dart';
import '../../../widgets/app_logo.dart';

/// Pro animated splash: the brand tile springs in, the wordmark reveals, a
/// glow pulses, then it hands off to the home screen.
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with TickerProviderStateMixin {
  late final AnimationController _c;
  late final AnimationController _glow;

  late final Animation<double> _tileScale;
  late final Animation<double> _tileFade;
  late final Animation<double> _wordFade;
  late final Animation<Offset> _wordSlide;
  late final Animation<double> _taglineFade;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));
    _glow = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);

    _tileScale = CurvedAnimation(
        parent: _c, curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack));
    _tileFade = CurvedAnimation(
        parent: _c, curve: const Interval(0.0, 0.30, curve: Curves.easeOut));
    _wordFade = CurvedAnimation(
        parent: _c, curve: const Interval(0.35, 0.7, curve: Curves.easeOut));
    _wordSlide = Tween(begin: const Offset(-0.25, 0), end: Offset.zero).animate(
        CurvedAnimation(
            parent: _c,
            curve: const Interval(0.35, 0.75, curve: Curves.easeOutCubic)));
    _taglineFade = CurvedAnimation(
        parent: _c, curve: const Interval(0.7, 1.0, curve: Curves.easeOut));

    _c.forward();

    // Hand off to home once the intro has played + a short hold.
    Future.delayed(const Duration(milliseconds: 2300), () {
      if (!mounted) return;
      // No account, no TV: the TV opens on sign-in and continues from there.
      if (Device.isTv && !AuthService.to.isSignedIn) {
        Get.offAll(() => const TvSignInView(required: true), transition: Transition.fadeIn);
        return;
      }
      Get.offAllNamed(Routes.HOME_SCREEN);
      final link = AppPages.pendingDetailArgs;
      AppPages.pendingDetailArgs = null;
      if (link != null) Get.toNamed(Routes.SUBJECT_DETAIL, arguments: link);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0F),
      body: Stack(
        children: [
          // Soft ambient glow behind the logo.
          Center(
            child: AnimatedBuilder(
              animation: _glow,
              builder: (_, __) => Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFB026FF)
                          .withValues(alpha: 0.10 + _glow.value * 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeTransition(
                        opacity: _tileFade,
                        child: ScaleTransition(
                          scale: _tileScale,
                          child: const AppLogo(size: 64, showWordmark: false),
                        ),
                      ),
                      const SizedBox(width: 18),
                      FadeTransition(
                        opacity: _wordFade,
                        child: SlideTransition(
                          position: _wordSlide,
                          child: const _Wordmark(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FadeTransition(
                  opacity: _taglineFade,
                  child: const Text(
                    'Movies & TV — free, anywhere',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Thin progress bar at the bottom.
          Positioned(
            left: 0,
            right: 0,
            bottom: 60,
            child: Center(
              child: SizedBox(
                width: 140,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: _c.value,
                      minHeight: 3,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFFB026FF)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Noon'),
          TextSpan(
            text: 'Flix',
            style: TextStyle(
              foreground: Paint()
                ..shader = const LinearGradient(
                  colors: [Color(0xFFB026FF), Color(0xFFE50914)],
                ).createShader(const Rect.fromLTWH(0, 0, 180, 60)),
            ),
          ),
        ],
        style: const TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w900,
          letterSpacing: -1,
          color: Colors.white,
        ),
      ),
    );
  }
}
