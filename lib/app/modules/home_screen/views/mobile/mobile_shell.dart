import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';

import '../../../../../app_theme.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/download_service.dart';
import 'mobile_home.dart';
import 'mobile_common.dart';
import 'my_noonflix_tab.dart';
import 'new_hot_tab.dart';
import 'search_tab.dart';

/// Phone layout: Netflix-style bottom navigation over three tabs. Tabs are
/// kept alive in an IndexedStack so switching back keeps each scroll position.
/// Search lives in each tab's top bar, as on Netflix.
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _tab = 0;
  final _visited = <int>{0};

  @override
  void initState() {
    super.initState();
    mobileTabRequest.addListener(_onTabRequest);
  }

  @override
  void dispose() {
    mobileTabRequest.removeListener(_onTabRequest);
    super.dispose();
  }

  void _onTabRequest() {
    final t = mobileTabRequest.value;
    if (t == null) return;
    mobileTabRequest.value = null;
    _select(t);
  }

  void _select(int i) => setState(() {
        if (i != _tab) stopInlineMedia();
        _tab = i;
        _visited.add(i);
      });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back from another tab returns to Home before leaving the app.
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: IndexedStack(
          index: _tab,
          children: [
            const MobileHome(),
            // Built on first visit so their requests don't compete with Home's.
            _visited.contains(1) ? const NewHotTab() : const SizedBox.shrink(),
            _visited.contains(2) ? const SearchTab() : const SizedBox.shrink(),
            _visited.contains(3) ? const MyNoonFlixTab() : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: _NetflixTabBar(index: _tab, onSelect: _select),
      ),
    );
  }
}

/// Netflix's phone tab bar: flat near-black, no selection pill — the icon
/// fills in and turns white, labels stay small, and the last tab is your
/// profile picture (framed when selected).
class _NetflixTabBar extends StatelessWidget {
  const _NetflixTabBar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF2000000),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              _TabItem(
                label: 'Home',
                selected: index == 0,
                onTap: () => onSelect(0),
                icon: Icon(index == 0 ? Icons.home_rounded : Icons.home_outlined),
              ),
              _TabItem(
                label: 'New & Hot',
                selected: index == 1,
                onTap: () => onSelect(1),
                icon: Icon(index == 1 ? Icons.smart_display_rounded : Icons.smart_display_outlined),
              ),
              _TabItem(
                label: 'Search',
                selected: index == 2,
                onTap: () => onSelect(2),
                icon: Icon(index == 2 ? Icons.manage_search_rounded : Icons.search_rounded),
              ),
              _TabItem(
                label: 'My NoonFlix',
                selected: index == 3,
                onTap: () => onSelect(3),
                icon: _ProfileIcon(selected: index == 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : const Color(0xFF9A9A9A);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconTheme(data: IconThemeData(color: color, size: 26), child: icon),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    letterSpacing: 0.1,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// The account's picture (or initial) as a small rounded square, like
/// Netflix's profile icon; a badge shows while downloads are running.
class _ProfileIcon extends StatelessWidget {
  const _ProfileIcon({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final user = AuthService.to.user.value;
      final img = user?.image;
      final active = DownloadService.supported ? DownloadService.to.activeCount : 0;
      final face = img != null && img.isNotEmpty
          ? CachedNetworkImage(imageUrl: img, fit: BoxFit.cover, errorWidget: (_, _, _) => const SizedBox())
          : DecoratedBox(
              decoration: const BoxDecoration(gradient: kBrandGradient),
              child: Center(
                child: user == null
                    ? const Icon(Icons.sentiment_satisfied_alt_rounded, color: Colors.white, size: 18)
                    : Text(user.displayName.characters.first.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
              ),
            );
      return SizedBox(
        width: 30,
        height: 26,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 25,
              height: 25,
              padding: EdgeInsets.all(selected ? 1.5 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: selected ? Border.all(color: Colors.white, width: 1.5) : null,
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(3.5), child: face),
            ),
            if (active > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    color: kBrandRed,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 9),
                ),
              ),
          ],
        ),
      );
    });
  }
}
