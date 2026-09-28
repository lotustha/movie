import 'package:flutter/material.dart';

import '../../../../../app_theme.dart';
import 'mobile_home.dart';
import 'mobile_common.dart';
import 'my_noonflix_tab.dart';
import 'new_hot_tab.dart';

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
            _visited.contains(2) ? const MyNoonFlixTab() : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: const Color(0xFF121217),
            indicatorColor: kBrandPurple.withValues(alpha: 0.22),
            height: 64,
            labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                  fontSize: 11,
                  fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
                  color: states.contains(WidgetState.selected) ? Colors.white : Colors.white60,
                )),
            iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                  color: states.contains(WidgetState.selected) ? Colors.white : Colors.white60,
                  size: 24,
                )),
          ),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _select,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.video_library_outlined),
                selectedIcon: Icon(Icons.video_library_rounded),
                label: 'New & Hot',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'My NoonFlix',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
