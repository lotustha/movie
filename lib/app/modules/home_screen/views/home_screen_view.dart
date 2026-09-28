import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../widgets/app_logo.dart';
import '../controllers/home_screen_controller.dart';
import 'content_area.dart';
import 'ranking_chip_bar.dart';
import 'mobile/mobile_shell.dart';
import 'tv_home.dart';

/// Small focusable icon for the top bar (D-pad + tap).
class _FocusableTopIcon extends StatefulWidget {
  const _FocusableTopIcon({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;
  @override
  State<_FocusableTopIcon> createState() => _FocusableTopIconState();
}

class _FocusableTopIconState extends State<_FocusableTopIcon> {
  bool _f = false;
  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (v) => setState(() => _f = v),
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _f ? Colors.white : Colors.white.withValues(alpha: 0.10),
          ),
          child: Icon(widget.icon,
              color: _f ? Colors.black : Colors.white, size: 24),
        ),
      ),
    );
  }
}

class HomeScreenView extends GetView<HomeScreenController> {
  const HomeScreenView({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTv = constraints.maxWidth >= 768;
        return isTv ? const Scaffold(body: TvHome()) : const MobileShell();
      },
    );
  }

  // Brand + live clock, shown on the wide (desktop/TV) top bar.
  Widget _clock(HomeScreenController controller) {
    return Obx(() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            controller.currentTime.value,
            style: Get.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            controller.currentDate.value,
            style: Get.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
        ],
      );
    });
  }

  // Ranking-list home: brand + search top bar, a sticky category chip bar, and
  // the ranked poster grid below it.
  Widget _rankingScaffold({required bool isTv}) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(isTv ? 24 : 16, 10, isTv ? 24 : 16, 6),
              child: Row(
                children: [
                  const AppLogo(size: 30),
                  const Spacer(),
                  if (isTv) ...[
                    _clock(controller),
                    const SizedBox(width: 16),
                  ],
                  _FocusableTopIcon(
                    icon: Icons.search,
                    onPressed: () => Get.toNamed('/search'),
                  ),
                ],
              ),
            ),
            RankingChipBar(isTv: isTv),
            const Expanded(child: ContentArea()),
          ],
        ),
      ),
    );
  }

  Widget buildDesktopLayout() => _rankingScaffold(isTv: true);

  Widget buildMobileLayout() => _rankingScaffold(isTv: false);
}
