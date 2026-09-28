import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../app_theme.dart';
import '../../../data/trending_list.dart';
import '../controllers/home_screen_controller.dart';

/// The moviebox-style horizontal ranking selector: a scrollable row of
/// category chips. On TV, D-pad focus only highlights a chip (it does not
/// reload the grid); pressing OK/Enter — or a tap on touch — commits the
/// selection so the grid isn't wiped while you scrub across 20 chips.
class RankingChipBar extends StatefulWidget {
  const RankingChipBar({super.key, required this.isTv});

  final bool isTv;

  @override
  State<RankingChipBar> createState() => _RankingChipBarState();
}

class _RankingChipBarState extends State<RankingChipBar> {
  // Always opens at the start (Popular). keepScrollOffset: false stops the
  // row restoring an old offset when home is rebuilt, e.g. after the
  // landscape player closes, which left it scrolled past Popular.
  final ScrollController _scroll = ScrollController(keepScrollOffset: false);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<HomeScreenController>();
    final categories = TrendingList.trendingList;
    return SizedBox(
      height: 56,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: widget.isTv ? 24 : 16, vertical: 8),
        physics: const BouncingScrollPhysics(),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final cat = categories[i];
          return _RankingChip(
            label: cat.name ?? '',
            id: cat.id ?? '',
            // The first category is loaded on init, so it holds initial focus.
            autofocus: widget.isTv && i == 0,
            onSelect: () =>
                controller.updateSelectedSubject(cat.id ?? '', cat.name ?? ''),
          );
        },
      ),
    );
  }
}

class _RankingChip extends StatefulWidget {
  const _RankingChip({
    required this.label,
    required this.id,
    required this.autofocus,
    required this.onSelect,
  });

  final String label;
  final String id;
  final bool autofocus;
  final VoidCallback onSelect;

  @override
  State<_RankingChip> createState() => _RankingChipState();
}

class _RankingChipState extends State<_RankingChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final HomeScreenController controller = Get.find<HomeScreenController>();
    return Obx(() {
      final bool selected = controller.selectedSubjectId.value == widget.id;
      return Focus(
        autofocus: widget.autofocus,
        onFocusChange: (hasFocus) {
          setState(() => _focused = hasFocus);
          // Keep the focused chip on-screen as the D-pad walks the row. Only
          // for key navigation: on touch the row stays where the finger left it.
          if (hasFocus &&
              FocusManager.instance.highlightMode == FocusHighlightMode.traditional) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        },
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onSelect,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              gradient: selected ? kBrandGradient : null,
              color: selected
                  ? null
                  : Colors.white.withValues(alpha: _focused ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _focused && !selected
                    ? Colors.white
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: selected || _focused ? Colors.white : Colors.white70,
                fontSize: 14,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    });
  }
}
