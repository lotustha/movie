import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app_theme.dart';
import '../../../model/subject_list.dart';
import '../../../widgets/tv_focusable.dart';
import '../../home_screen/views/video_thumbnail.dart';
import '../controllers/search_controller.dart';

/// Android TV search: an on-screen keyboard driven by the D-pad on the left,
/// suggestions / recent searches under it, and live results on the right.
///
/// The system IME is never opened — it would cover the results — so the
/// query lives in [SearchViewController.searchController] and is edited
/// through [SearchViewController.onTvKeyTapped]. From the keyboard, RIGHT
/// moves into the results, UP from the results reaches the filter chips.
class SearchTvLayout extends StatefulWidget {
  const SearchTvLayout({super.key, required this.controller});

  final SearchViewController controller;

  @override
  State<SearchTvLayout> createState() => _SearchTvLayoutState();
}

class _SearchTvLayoutState extends State<SearchTvLayout> {
  // Where focus returns when the row that held it disappears.
  final FocusNode _firstKey = FocusNode();

  SearchViewController get c => widget.controller;

  @override
  void dispose() {
    _firstKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 0, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 284,
              child: FocusTraversalGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _QueryDisplay(controller: c),
                    const SizedBox(height: 12),
                    _Keyboard(controller: c, firstKey: _firstKey),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _SidePanel(
                        controller: c,
                        onHistoryCleared: _firstKey.requestFocus,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 28),
            Expanded(child: FocusTraversalGroup(child: _Results(controller: c))),
          ],
        ),
      ),
    );
  }
}

// ─── Query ─────────────────────────────────────────────────────────────────────

class _QueryDisplay extends StatelessWidget {
  const _QueryDisplay({required this.controller});
  final SearchViewController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.white54, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Obx(() {
              final q = controller.searchQuery.value;
              if (q.isEmpty) {
                return const Text(
                  'Search movies & TV',
                  style: TextStyle(color: Colors.white38, fontSize: 15),
                );
              }
              return Row(
                children: [
                  // Long queries keep their end — the part being typed — visible.
                  Flexible(
                    child: Text(
                      q.length > 24 ? '…${q.substring(q.length - 23)}' : q,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    width: 2,
                    height: 20,
                    margin: const EdgeInsets.only(left: 2),
                    color: kBrandPurple,
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─── Keyboard ──────────────────────────────────────────────────────────────────

class _Keyboard extends StatelessWidget {
  const _Keyboard({required this.controller, required this.firstKey});
  final SearchViewController controller;
  final FocusNode firstKey;

  static const _rows = ['abcdef', 'ghijkl', 'mnopqr', 'stuvwx', 'yz1234', '567890'];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                for (var i = 0; i < row.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: _Key(
                      label: row[i],
                      focusNode: row[i] == 'a' ? firstKey : null,
                      autofocus: row[i] == 'a',
                      onSelect: () => controller.onTvKeyTapped(row[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _Key(
                icon: Icons.space_bar,
                label: 'Space',
                onSelect: () => controller.onTvKeyTapped(' '),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: 2,
              child: _Key(
                icon: Icons.backspace_outlined,
                semanticLabel: 'Delete',
                repeat: true,
                onSelect: () => controller.onTvKeyTapped('DEL'),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: 2,
              child: _Key(
                label: 'Clear',
                onSelect: () => controller.onTvKeyTapped('CLR'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.onSelect,
    this.label,
    this.icon,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.repeat = false,
  });

  final VoidCallback onSelect;
  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool repeat;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: TvFocusable(
        focusNode: focusNode,
        autofocus: autofocus,
        repeat: repeat,
        onSelect: onSelect,
        builder: (context, focused) {
          final color = focused ? Colors.black : Colors.white70;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: focused ? Colors.white : Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) Icon(icon, size: 18, color: color),
                if (icon != null && label != null && label!.length > 1)
                  const SizedBox(width: 6),
                if (label != null && (icon == null || label!.length > 1))
                  Text(
                    label!,
                    style: TextStyle(
                      color: color,
                      fontSize: label!.length == 1 ? 16 : 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Suggestions / recent searches ─────────────────────────────────────────────

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.controller, required this.onHistoryCleared});
  final SearchViewController controller;
  final VoidCallback onHistoryCleared;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final typing = controller.searchQuery.value.isNotEmpty;
      final List<String> words = typing
          ? controller.searchSuggestions
              .map((s) => s.word ?? '')
              .where((w) => w.isNotEmpty)
              .take(8)
              .toList()
          : controller.searchHistory.toList();

      if (words.isEmpty) {
        return typing
            ? const SizedBox.shrink()
            : const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Type with the remote — results update as you go.',
                  style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.4),
                ),
              );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(typing ? 'SUGGESTIONS' : 'RECENT SEARCHES'),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                for (final w in words)
                  _WordRow(
                    icon: typing ? Icons.search : Icons.history,
                    text: w,
                    onSelect: () => controller.onTvSuggestionSelected(w),
                  ),
                if (!typing)
                  _WordRow(
                    icon: Icons.delete_outline,
                    text: 'Clear recent searches',
                    muted: true,
                    onSelect: () {
                      controller.clearSearchHistory();
                      onHistoryCleared();
                    },
                  ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _WordRow extends StatelessWidget {
  const _WordRow({
    required this.icon,
    required this.text,
    required this.onSelect,
    this.muted = false,
  });

  final IconData icon;
  final String text;
  final VoidCallback onSelect;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onSelect: onSelect,
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: focused ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: focused ? Colors.white : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: focused ? Colors.white : Colors.white38),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: focused
                      ? Colors.white
                      : (muted ? Colors.white38 : Colors.white70),
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ─── Results ───────────────────────────────────────────────────────────────────

class _Results extends StatelessWidget {
  const _Results({required this.controller});
  final SearchViewController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final query = controller.searchQuery.value.trim();

      // Nothing typed yet: what's popular right now.
      if (query.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelTitle('Popular right now'),
            const SizedBox(height: 12),
            Expanded(
              child: controller.isPopularLoading.value &&
                      controller.popularList.isEmpty
                  ? const _Loading()
                  : _PosterGrid(subjects: controller.popularList, ranked: true),
            ),
          ],
        );
      }

      final results = controller.subjectsList;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 28),
            child: Row(
              children: [
                for (final (type, label) in const [
                  (0, 'All'),
                  (1, 'Movies'),
                  (2, 'TV Shows'),
                ]) ...[
                  _FilterChip(
                    label: label,
                    selected: controller.searchType.value == type,
                    onSelect: () => controller.setSearchType(type),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                Flexible(
                  child: Text(
                    'Results for “$query”',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: controller.isLoading.value && results.isEmpty
                ? const _Loading()
                : results.isEmpty
                    ? _NoResults(query: query)
                    : _PosterGrid(
                        subjects: results,
                        onReachEnd: controller.loadMore,
                      ),
          ),
        ],
      );
    });
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelect,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    // Same look as the home ranking chips.
    return TvFocusable(
      onSelect: onSelect,
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 34,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: selected ? kBrandGradient : null,
          color: selected ? null : Colors.white.withValues(alpha: focused ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: focused ? Colors.white : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected || focused ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _PosterGrid extends StatelessWidget {
  const _PosterGrid({required this.subjects, this.ranked = false, this.onReachEnd});

  final List<Subject> subjects;
  final bool ranked;
  final VoidCallback? onReachEnd;

  static const _columns = 4;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.only(right: 28, bottom: 28),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        childAspectRatio: 0.54,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: subjects.length,
      itemBuilder: (context, index) {
        final isLastRow = index >= subjects.length - _columns;
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (hasFocus) {
            if (hasFocus && isLastRow) onReachEnd?.call();
          },
          child: VideoThumbnail(
            subject: subjects[index],
            rank: ranked ? index + 1 : null,
          ),
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment(0, -0.3),
      child: SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          Text(
            'No results for “$query”',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Try a shorter title, another spelling, or the All filter.',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
