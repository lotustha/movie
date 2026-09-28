import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../app_theme.dart';
import '../../../data/trending_list.dart';
import '../../../data/user_data.dart';
import '../../../model/operating_list_model.dart';
import '../../../model/subject_list.dart';
import '../../../widgets/app_logo.dart';
import '../../../widgets/tv_focusable.dart';
import '../../Subject_Detail/bindings/subject_detail_binding.dart';
import '../../Subject_Detail/views/subject_detail_view.dart';
import '../controllers/home_screen_controller.dart';
import '../../../services/auth_service.dart';
import '../../../services/prefs.dart';
import '../../settings/settings_view.dart';

// Fixed geometry: every row has the same height, so the screen can pin the
// focused row to the top of the rail area with plain arithmetic instead of
// relying on ensureVisible (which never scrolled the old grid on TV).
const double _posterW = 104;
const double _posterH = 156;
const double _posterGap = 12;
const double _rowExtent = 206;
const double _sidePad = 28;
const double _headerOpen = 300; // billboard focused
const double _headerClosed = 168; // focus in the rails: compact info header
const Duration _move = Duration(milliseconds: 260);

/// Android TV home: a featured billboard over horizontal rails.
///
/// With focus on the billboard it shows wide banner art (LEFT/RIGHT flips
/// through banners, OK opens the title). Moving DOWN collapses it into an
/// info header for whichever poster is focused; the focused rail is always
/// pinned under the header and the focused poster stays at the left edge.
/// BACK from the rails returns to the billboard instead of leaving the app.
class TvHome extends StatefulWidget {
  const TvHome({super.key});

  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> {
  final HomeScreenController c = Get.find<HomeScreenController>();
  final ScrollController _rails = ScrollController();
  final FocusNode _billboardFocus = FocusNode(debugLabel: 'billboard');
  // The search icon sits inside the billboard's area, so geometric traversal
  // can't find it from there; UP/DOWN between the two are wired explicitly.
  final FocusNode _searchFocus = FocusNode(debugLabel: 'search');
  bool _inRails = false;

  // UP/DOWN are handled here rather than by geometric traversal, so they
  // always land on the left-most poster of the neighbouring rail.
  final Map<String, GlobalKey<_RailState>> _railKeys = {};
  List<String> _railTitles = const [];

  GlobalKey<_RailState> _keyFor(String title) =>
      _railKeys.putIfAbsent(title, () => GlobalKey<_RailState>());

  bool _focusRail(int index) {
    if (index < 0 || index >= _railTitles.length) return false;
    return _railKeys[_railTitles[index]]?.currentState?.focusCurrent() ?? false;
  }

  bool _onRailVertical(int row, int delta) {
    // Skip rails that are still loading or empty (a few at most).
    for (var r = row + delta, hops = 0; hops < 4; r += delta, hops++) {
      if (r < 0) {
        _billboardFocus.requestFocus();
        return true;
      }
      if (r >= _railTitles.length) return false;
      if (_focusRail(r)) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _rails.dispose();
    _billboardFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _toTop() {
    if (_inRails) setState(() => _inRails = false);
    if (_rails.hasClients) _rails.animateTo(0, duration: _move, curve: Curves.easeOutCubic);
  }

  void _onPosterFocused(int row, Subject subject) {
    c.focusedSubject.value = subject;
    if (!_inRails) setState(() => _inRails = true);
    if (!_rails.hasClients) return;
    final target = math.min(row * _rowExtent, _rails.position.maxScrollExtent);
    _rails.animateTo(target, duration: _move, curve: Curves.easeOutCubic);
  }

  Future<void> _open(Subject subject, {bool resume = false}) async {
    if (subject.subjectId == null) return;
    await Get.to(
      () => const SubjectDetailView(),
      transition: Transition.rightToLeft,
      binding: SubjectDetailBinding(),
      arguments: {'id': subject.subjectId, 'resume': resume},
    );
    // Playback / My List may have changed while away.
    c.refreshUserRows();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return PopScope(
      canPop: !_inRails,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _billboardFocus.requestFocus();
      },
      child: ColoredBox(
        color: bg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Page-wide wash in the focused poster's own hue: glows from the
            // top-left and fades into the page, so the info header has no
            // edge of its own and the rails sit in the same light.
            IgnorePointer(child: _AmbientTint(active: _inRails)),
            Column(
          children: [
            AnimatedContainer(
              duration: _move,
              curve: Curves.easeOutCubic,
              height: _inRails ? _headerClosed : _headerOpen,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedOpacity(
                    duration: _move,
                    opacity: _inRails ? 0 : 1,
                    child: _Billboard(
                      focusNode: _billboardFocus,
                      active: !_inRails,
                      onFocused: _toTop,
                      onDown: () => _focusRail(0),
                      onUp: _searchFocus.requestFocus,
                      onOpen: _open,
                    ),
                  ),
                  IgnorePointer(
                    child: AnimatedOpacity(
                      duration: _move,
                      opacity: _inRails ? 1 : 0,
                      child: const _InfoHeader(),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _TopBar(
                      searchFocus: _searchFocus,
                      onFocused: _toTop,
                      onDown: _billboardFocus.requestFocus,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Obx(() {
                final rails = _buildRails();
                // Unique per rail even if two feed rails share a title.
                final seen = <String, int>{};
                _railTitles = [
                  for (final r in rails)
                    (seen[r.title] = (seen[r.title] ?? 0) + 1) == 1
                        ? r.title
                        : '${r.title}#${seen[r.title]}',
                ];
                return ListView.builder(
                  controller: _rails,
                  itemExtent: _rowExtent,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(_rowExtent * 2),
                  // Room below the last rail so it too can pin to the top.
                  padding: const EdgeInsets.only(bottom: _rowExtent),
                  itemCount: rails.length,
                  itemBuilder: (context, i) => _Rail(
                    key: _keyFor(_railTitles[i]),
                    spec: rails[i],
                    onFocused: (s) => _onPosterFocused(i, s),
                    onVertical: (delta) => _onRailVertical(i, delta),
                    // Continue Watching resumes straight away.
                    onOpen: (s) => _open(s, resume: rails[i].showProgress),
                  ),
                );
              }),
            ),
          ],
            ),
          ],
        ),
      ),
    );
  }

  List<_RailSpec> _buildRails() {
    final rails = <_RailSpec>[];
    if (c.continueWatching.isNotEmpty) {
      rails.add(_RailSpec('Continue Watching',
          subjects: c.continueWatching.toList(), showProgress: true));
    }
    if (c.myList.isNotEmpty) {
      rails.add(_RailSpec('My List', subjects: c.myList.toList()));
    }
    // The first ranking category (Popular) is already loaded by the controller.
    final popular = TrendingList.trendingList.first;
    rails.add(_RailSpec('Top 20 ${popular.name ?? ''}',
        subjects: c.subjectsList.take(20).toList(),
        ranked: true,
        loading: c.isLoading.value));
    for (final row in c.homeRows) {
      // "Coming Soon" titles have no streams yet.
      if (row.type == 'APPOINTMENT_LIST') continue;
      rails.add(_RailSpec(row.title, subjects: row.subjects));
    }
    for (final cat in TrendingList.trendingList.skip(1)) {
      if (cat.id == null) continue;
      final name = (cat.name ?? '').replaceAll(RegExp(r'[\[\]]'), '');
      rails.add(_RailSpec('Top $name', rankingId: cat.id, ranked: true));
    }
    // 18+ rows last, only after the opt-in (Settings → Show 18+ content).
    if (AppPrefs.to.adultVisible) {
      if (c.adultRows.isEmpty && !c.isAdultLoading.value && !c.adultFailed.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) => c.fetchAdultFeed());
      }
      if (c.adultContinue.isNotEmpty) {
        rails.add(_RailSpec('🌙 Continue Watching',
            subjects: c.adultContinue.toList(), showProgress: true));
      }
      if (c.adultMyList.isNotEmpty) {
        rails.add(_RailSpec('🌙 My List', subjects: c.adultMyList.toList()));
      }
      for (final row in c.adultRows) {
        rails.add(_RailSpec('🌙 ${row.title}', subjects: row.subjects));
      }
    }
    return rails;
  }
}

// ─── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.searchFocus,
    required this.onFocused,
    required this.onDown,
  });
  final FocusNode searchFocus;
  final VoidCallback onFocused;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<HomeScreenController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(_sidePad, 14, _sidePad, 0),
      child: Row(
        children: [
          const AppLogo(size: 26),
          const Spacer(),
          Obx(() => Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(c.currentTime.value,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(c.currentDate.value,
                      style: const TextStyle(color: Colors.white60, fontSize: 11)),
                ],
              )),
          const SizedBox(width: 14),
          Semantics(
            button: true,
            label: 'Search',
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  onDown();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TopIcon(
                    focusNode: searchFocus,
                    icon: Icons.search,
                    tooltip: 'Search',
                    onSelect: () => Get.toNamed('/search'),
                    onFocused: onFocused,
                  ),
                  const SizedBox(width: 10),
                  Obx(() => _TopIcon(
                        icon: AuthService.to.isSignedIn
                            ? Icons.account_circle
                            : Icons.settings_outlined,
                        label: AuthService.to.isSignedIn ? null : 'Sign in',
                        tooltip: AuthService.to.user.value?.displayName ?? 'Settings',
                        onSelect: () =>
                            Get.to(() => const SettingsView(), transition: Transition.fadeIn),
                        onFocused: onFocused,
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A pill in the top bar (search, settings / sign in).
class _TopIcon extends StatelessWidget {
  const _TopIcon({
    required this.icon,
    required this.onSelect,
    required this.onFocused,
    this.focusNode,
    this.label,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onSelect;
  final VoidCallback onFocused;
  final FocusNode? focusNode;
  final String? label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip ?? label,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onFocusChange: (f) {
          if (f) onFocused();
        },
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 8 : 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            color: focused ? Colors.white : Colors.white.withValues(alpha: 0.12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: focused ? Colors.black : Colors.white),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(label!,
                    style: TextStyle(
                        color: focused ? Colors.black : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Billboard ─────────────────────────────────────────────────────────────────

class _Billboard extends StatefulWidget {
  const _Billboard({
    required this.focusNode,
    required this.active,
    required this.onFocused,
    required this.onDown,
    required this.onUp,
    required this.onOpen,
  });

  final FocusNode focusNode;
  final bool active; // visible (focus not in the rails)
  final VoidCallback onFocused;
  final bool Function() onDown;
  final VoidCallback onUp;
  final ValueChanged<Subject> onOpen;

  @override
  State<_Billboard> createState() => _BillboardState();
}

class _BillboardState extends State<_Billboard> {
  final HomeScreenController c = Get.find<HomeScreenController>();
  int _index = 0;
  bool _focused = false;
  Timer? _rotate;

  @override
  void initState() {
    super.initState();
    _restartRotation();
  }

  @override
  void dispose() {
    _rotate?.cancel();
    super.dispose();
  }

  void _restartRotation() {
    _rotate?.cancel();
    _rotate = Timer.periodic(const Duration(seconds: 8), (_) {
      if (widget.active && c.banners.length > 1) _step(1, fromUser: false);
    });
  }

  void _step(int delta, {bool fromUser = true}) {
    final n = c.banners.length;
    if (n == 0) return;
    setState(() => _index = (_index + delta) % n);
    if (fromUser) _restartRotation();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: true,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) widget.onFocused();
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _step(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _step(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDown()) {
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          widget.onUp();
          return KeyEventResult.handled;
        }
        if (isTvSelectKey(event)) {
          final item = _current;
          if (item?.subject != null) widget.onOpen(item!.subject!);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          final item = _current;
          if (item?.subject != null) widget.onOpen(item!.subject!);
        },
        child: Obx(() {
          final items = c.banners;
          if (items.isEmpty) {
            return _BillboardEmpty(loading: c.isFeedLoading.value);
          }
          final item = items[_index % items.length];
          return _BillboardSlide(
            key: ValueKey(item.subjectId),
            item: item,
            index: _index % items.length,
            count: items.length,
            focused: _focused,
          );
        }),
      ),
    );
  }

  BannerItem? get _current =>
      c.banners.isEmpty ? null : c.banners[_index % c.banners.length];
}

class _BillboardSlide extends StatelessWidget {
  const _BillboardSlide({
    super.key,
    required this.item,
    required this.index,
    required this.count,
    required this.focused,
  });

  final BannerItem item;
  final int index;
  final int count;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final subject = item.subject!;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Banner art is 16:9: give it exactly that box at the billboard's
        // full height, anchored right, so the whole picture (title logos
        // included) shows instead of being cropped by BoxFit.cover.
        Positioned(
          top: 0,
          right: 0,
          height: _headerOpen,
          width: _headerOpen * 16 / 9,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            child: CachedNetworkImage(
              key: ValueKey(item.image.url),
              imageUrl: '${item.image.url}?x-oss-process=image/resize%2Cw_1920/quality%2Cq_90',
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 300),
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        // Feather the art's left edge into the page (the art starts at ~44%
        // of the width) and keep the title side solid for legibility.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [bg, bg.withValues(alpha: 0.8), bg.withValues(alpha: 0)],
              stops: const [0.40, 0.50, 0.68],
            ),
          ),
        ),
        // A short bottom fade into the rails — short enough not to swallow
        // logos near the bottom of the art.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [bg, bg.withValues(alpha: 0)],
              stops: const [0.0, 0.2],
            ),
          ),
        ),
        Positioned(
          left: _sidePad,
          bottom: 18,
          width: MediaQuery.of(context).size.width * 0.46,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.title.isNotEmpty ? item.title : (subject.title ?? ''),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              _MetaLine(subject: subject),
              const SizedBox(height: 14),
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(
                      color: focused ? Colors.white : Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 18, color: focused ? Colors.black : Colors.white),
                        const SizedBox(width: 8),
                        Text('More info',
                            style: TextStyle(
                                color: focused ? Colors.black : Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (count > 1) ...[
                    Icon(Icons.chevron_left,
                        size: 20, color: focused ? Colors.white70 : Colors.transparent),
                    for (var i = 0; i < count; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: i == index ? 16 : 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          gradient: i == index ? kBrandGradient : null,
                          color: i == index ? null : Colors.white24,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    Icon(Icons.chevron_right,
                        size: 20, color: focused ? Colors.white70 : Colors.transparent),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BillboardEmpty extends StatelessWidget {
  const _BillboardEmpty({required this.loading});
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_sidePad, 0, _sidePad, 24),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: loading
            ? const SizedBox(
                width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))
            : const Text('Featured titles are unavailable right now.',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
      ),
    );
  }
}

// ─── Info header (focus in the rails) ──────────────────────────────────────────

class _InfoHeader extends StatelessWidget {
  const _InfoHeader();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<HomeScreenController>();
    return Obx(() {
      final s = c.focusedSubject.value;
      if (s == null) return const SizedBox.shrink();
      final description = (s.description ?? '').trim();
      // No background of its own — [_AmbientTint] lights the whole page.
      return Padding(
        padding: const EdgeInsets.fromLTRB(_sidePad, 64, _sidePad, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            _MetaLine(subject: s),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.6,
                child: Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.35),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}

/// Soft glow in the focused poster's dark hue (MovieBox's `avgHueDark`),
/// shown while focus is in the rails. A radial falloff from the top-left
/// means there is no edge anywhere; the colour cross-fades between posters.
class _AmbientTint extends StatelessWidget {
  const _AmbientTint({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<HomeScreenController>();
    return AnimatedOpacity(
      duration: _move,
      opacity: active ? 1 : 0,
      child: Obx(() {
        final tint = _hexColor(c.focusedSubject.value?.cover?.avgHueDark) ??
            kBrandPurple.withValues(alpha: 0.5);
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: tint),
          duration: const Duration(milliseconds: 450),
          builder: (context, color, _) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.9, -1.1),
                radius: 1.35,
                colors: [
                  (color ?? tint).withValues(alpha: 0.55),
                  (color ?? tint).withValues(alpha: 0.18),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        );
      }),
    );
  }
}

Color? _hexColor(String? hex) {
  if (hex == null || !hex.startsWith('#') || hex.length != 7) return null;
  final v = int.tryParse(hex.substring(1), radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// ★ rating · year · Movie/TV · genres · country — only the parts that exist.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.subject});
  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if ((subject.releaseDate?.length ?? 0) >= 4) subject.releaseDate!.substring(0, 4),
      if (subject.subjectType == 1) 'Movie',
      if (subject.subjectType == 2) 'TV',
      if ((subject.genre ?? '').isNotEmpty) subject.genre!.split(',').take(3).join(', '),
      if ((subject.countryName ?? '').isNotEmpty) subject.countryName!,
    ];
    final rating = subject.imdbRatingValue ?? '';
    final hasRating = (double.tryParse(rating) ?? 0) > 0; // "0" = unrated
    return Row(
      children: [
        if (hasRating) ...[
          const Icon(Icons.star_rounded, color: Color(0xFFF5C518), size: 16),
          const SizedBox(width: 3),
          Text(rating,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          if (parts.isNotEmpty) const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            parts.join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

// ─── Rails ─────────────────────────────────────────────────────────────────────

class _RailSpec {
  _RailSpec(
    this.title, {
    this.subjects = const [],
    this.rankingId,
    this.ranked = false,
    this.showProgress = false,
    this.loading = false,
  });

  final String title;
  final List<Subject> subjects;
  final String? rankingId; // lazily loaded ranking category
  final bool ranked;
  final bool showProgress;
  final bool loading;
}

class _Rail extends StatefulWidget {
  const _Rail({
    super.key,
    required this.spec,
    required this.onFocused,
    required this.onVertical,
    required this.onOpen,
  });

  final _RailSpec spec;
  final ValueChanged<Subject> onFocused;
  final bool Function(int delta) onVertical; // -1 up, +1 down; true if handled
  final ValueChanged<Subject> onOpen;

  @override
  State<_Rail> createState() => _RailState();
}

class _RailState extends State<_Rail> {
  final ScrollController _scroll = ScrollController();
  final Map<int, FocusNode> _nodes = {};
  int _count = 0;
  int _lastIndex = 0;
  bool _active = false;

  FocusNode _nodeFor(int i) => _nodes.putIfAbsent(i, () => FocusNode());

  /// Focuses the poster this rail was last on (its left-most one).
  /// False when the rail has nothing focusable yet.
  bool focusCurrent() {
    if (_count == 0) return false;
    final i = _lastIndex.clamp(0, _count - 1);
    final node = _nodes[i];
    if (node == null || node.context == null) return false;
    node.requestFocus();
    return true;
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _onItemFocused(int index, Subject subject) {
    _lastIndex = index;
    widget.onFocused(subject);
    if (!_scroll.hasClients) return;
    // Keep the focused poster at the left edge, Netflix-style.
    final target = math.min(index * (_posterW + _posterGap), _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    if (spec.rankingId == null) {
      return _body(spec.subjects, loading: spec.loading && spec.subjects.isEmpty);
    }
    final c = Get.find<HomeScreenController>();
    final list = c.rankingRow(spec.rankingId!);
    return Obx(() => _body(list.toList(),
        loading: c.rankingRowLoaded[spec.rankingId!]?.value != true));
  }

  Widget _body(List<Subject> subjects, {required bool loading}) {
    final spec = widget.spec;
    _count = subjects.length;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _active = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final delta = event.logicalKey == LogicalKeyboardKey.arrowDown
            ? 1
            : event.logicalKey == LogicalKeyboardKey.arrowUp
                ? -1
                : 0;
        if (delta != 0 && widget.onVertical(delta)) return KeyEventResult.handled;
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(_sidePad, 6, _sidePad, 0),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                color: _active ? Colors.white : Colors.white60,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              child: Text(spec.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          Expanded(
            child: subjects.isEmpty
                ? (loading
                    ? const _SkeletonRow()
                    : const Padding(
                        padding: EdgeInsets.fromLTRB(_sidePad, 16, _sidePad, 0),
                        child: Text('Nothing in this list right now.',
                            style: TextStyle(color: Colors.white38, fontSize: 13)),
                      ))
                : ListView.separated(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.fromLTRB(_sidePad, 12, _sidePad, 12),
                    itemCount: subjects.length,
                    separatorBuilder: (_, _) => const SizedBox(width: _posterGap),
                    itemBuilder: (context, i) => _Poster(
                      focusNode: _nodeFor(i),
                      subject: subjects[i],
                      rank: spec.ranked ? i + 1 : null,
                      progress: spec.showProgress
                          ? UserData.progressFraction(subjects[i].subjectId)
                          : 0,
                      onFocused: () => _onItemFocused(i, subjects[i]),
                      onOpen: () => widget.onOpen(subjects[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({
    required this.focusNode,
    required this.subject,
    required this.onFocused,
    required this.onOpen,
    this.rank,
    this.progress = 0,
  });

  final FocusNode focusNode;
  final Subject subject;
  final VoidCallback onFocused;
  final VoidCallback onOpen;
  final int? rank;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final url = subject.cover?.url;
    return Semantics(
      button: true,
      label: subject.title,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onOpen,
        onFocusChange: (f) {
          if (f) onFocused();
        },
        builder: (context, focused) => AnimatedScale(
          scale: focused ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: _posterW,
            height: _posterH,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: focused ? Colors.white : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: kBrandPurple.withValues(alpha: 0.45),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url != null && url.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: '$url?x-oss-process=image/resize%2Cw_400/quality%2Cq_90',
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const ColoredBox(color: Color(0xFF1C1C24)),
                      errorWidget: (_, _, _) => _PosterFallback(title: subject.title),
                    )
                  else
                    _PosterFallback(title: subject.title),
                  if (rank != null)
                    Positioned(top: 0, left: 0, child: _RankBadge(rank: rank!)),
                  if (progress > 0)
                    Positioned(
                      left: 6,
                      right: 6,
                      bottom: 6,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(kBrandPurple),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({this.title});
  final String? title;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF1C1C24),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            title ?? '',
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ),
    );
  }
}

/// Top three carry the brand gradient, like the phone ranking grid.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    final top = rank <= 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        gradient: top ? kBrandGradient : null,
        color: top ? null : Colors.black.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.only(bottomRight: Radius.circular(8)),
      ),
      child: Text(
        '$rank',
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, height: 1.0),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_sidePad, 12, _sidePad, 12),
      itemCount: 8,
      separatorBuilder: (_, _) => const SizedBox(width: _posterGap),
      itemBuilder: (_, _) => Container(
        width: _posterW,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
