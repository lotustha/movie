import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../../app_theme.dart';
import '../../../../data/trending_list.dart';
import '../../../../data/user_data.dart';
import '../../../../model/subject_list.dart';
import '../../../../widgets/app_logo.dart';
import '../../controllers/home_screen_controller.dart';
import '../../../../services/prefs.dart';
import '../../../settings/adult_gate.dart';
import '../../../../widgets/skeleton.dart';
import '../../../vip/vip_unlock.dart';
import 'category_view.dart';
import 'mobile_common.dart';

/// Phone Home, laid out like Netflix's: a top bar with TV Shows / Movies /
/// Categories chips, a swipeable poster hero card, then rails — Continue
/// Watching, My List, Top 10, the home feed's rows, then the ranking
/// categories. The chips narrow the hero and every rail to shows or movies.
class MobileHome extends StatefulWidget {
  const MobileHome({super.key});

  @override
  State<MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<MobileHome> {
  final HomeScreenController c = Get.find<HomeScreenController>();
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _barOpacity = ValueNotifier(0);
  MediaFilter _filter = MediaFilter.all;
  // Showing the 18+ ("Midnight") feed instead of the regular one.
  bool _adult = false;

  @override
  void dispose() {
    _scroll.dispose();
    _barOpacity.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    c.refreshUserRows();
    await Future.wait([c.fetchHomeFeed(), c.refresh()]);
  }

  void _setFilter(MediaFilter f) {
    setState(() {
      _filter = f;
      _adult = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _openAdult() async {
    if (!await requireAdultAccess()) return;
    c.fetchAdultFeed();
    setState(() {
      _adult = true;
      _filter = MediaFilter.all;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _refresh,
          color: kBrandPurple,
          edgeOffset: top + 100,
          child: NotificationListener<ScrollNotification>(
            // The page's own vertical scroll (depth 0; the rails are deeper).
            onNotification: (n) {
              if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
                final v = (n.metrics.pixels / 120).clamp(0.0, 1.0);
                if (v != _barOpacity.value) _barOpacity.value = v;
              }
              return false;
            },
            child: Obx(() {
              // Turned off (or locked) in Settings while showing it.
              if (_adult && !AppPrefs.to.adultVisible) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _adult = false);
                });
              }
              final rails = _adult ? _buildAdultRails() : _buildRails();
              return CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                      child: _HeroCard(filter: _filter, adult: _adult, topInset: top + 104)),
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 24),
                    sliver: SliverList.builder(
                      itemCount: rails.length,
                      itemBuilder: (_, i) => rails[i],
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
        _TopBar(
          opacity: _barOpacity,
          filter: _filter,
          adult: _adult,
          onFilter: _setFilter,
          onAdult: _openAdult,
        ),
      ],
    );
  }

  List<Widget> _buildAdultRails() {
    if (c.adultRows.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: c.isAdultLoading.value
                ? const CircularProgressIndicator()
                : Column(
                    children: [
                      const Text('Midnight is unavailable right now.',
                          style: TextStyle(color: Colors.white54)),
                      TextButton(
                          onPressed: () => c.fetchAdultFeed(force: true), child: const Text('Retry')),
                    ],
                  ),
          ),
        ),
      ];
    }
    return [
      if (c.adultContinue.isNotEmpty) _ContinueRail(subjects: c.adultContinue.toList()),
      if (c.adultMyList.isNotEmpty) _Rail(title: 'My List', subjects: c.adultMyList.toList()),
      for (final row in c.adultRows) _Rail(title: row.title, subjects: row.subjects),
    ];
  }

  List<Widget> _buildRails() {
    final f = _filter;
    final rails = <Widget>[];
    final continuing = c.continueWatching.where(f.matches).toList();
    if (continuing.isNotEmpty) rails.add(_ContinueRail(subjects: continuing));
    final mine = c.myList.where(f.matches).toList();
    if (mine.isNotEmpty) rails.add(_Rail(title: 'My List', subjects: mine));

    final popular = TrendingList.trendingList.first;
    final top10 = dedupeTitles(c.subjectsList.where(f.matches)).take(10).toList();
    rails.add(_Top10Rail(
      title: switch (f) {
        MediaFilter.all => 'Top 10 ${popular.name ?? ''}',
        MediaFilter.shows => 'Top 10 Shows',
        MediaFilter.movies => 'Top 10 Movies',
      },
      subjects: top10,
      loading: c.isLoading.value && top10.isEmpty,
    ));

    for (final row in c.homeRows) {
      if (row.type == 'APPOINTMENT_LIST') continue; // "Coming Soon" lives in New & Hot
      final subjects = row.subjects.where(f.matches).toList();
      if (subjects.isNotEmpty) rails.add(_Rail(title: row.title, subjects: subjects));
    }
    for (final cat in TrendingList.trendingList.skip(1)) {
      if (cat.id == null) continue;
      rails.add(_RankingRail(
        id: cat.id!,
        name: (cat.name ?? '').replaceAll(RegExp(r'[\[\]]'), ''),
        filter: f,
      ));
    }
    return rails;
  }
}

// ─── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.opacity,
    required this.filter,
    required this.adult,
    required this.onFilter,
    required this.onAdult,
  });
  final ValueNotifier<double> opacity;
  final MediaFilter filter;
  final bool adult;
  final ValueChanged<MediaFilter> onFilter;
  final VoidCallback onAdult;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final bar = Padding(
      padding: EdgeInsets.fromLTRB(16, top + 4, 4, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppLogo(size: 28),
              const Spacer(),
              const VipChip(),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Search',
                onPressed: openSearchTab,
                icon: const Icon(Icons.search_rounded, color: Colors.white, size: 27),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            // Obx: the 18+ chip appears as soon as the setting arrives (it can
            // come from the account's sync, after this bar was built).
            child: Obx(() => ListView(
              scrollDirection: Axis.horizontal,
              children: adult
                  ? [
                      _Chip(
                        icon: Icons.close_rounded,
                        semantic: 'Leave Midnight',
                        onTap: () => onFilter(MediaFilter.all),
                      ),
                      const SizedBox(width: 8),
                      const _Chip(label: '🌙 Midnight 18+', selected: true, onTap: _noop),
                    ]
                  : [
                if (filter != MediaFilter.all) ...[
                  _Chip(
                    icon: Icons.close_rounded,
                    semantic: 'Clear filter',
                    onTap: () => onFilter(MediaFilter.all),
                  ),
                  const SizedBox(width: 8),
                ],
                if (filter != MediaFilter.movies)
                  _Chip(
                    label: 'TV Shows',
                    selected: filter == MediaFilter.shows,
                    onTap: () => onFilter(
                        filter == MediaFilter.shows ? MediaFilter.all : MediaFilter.shows),
                  ),
                if (filter == MediaFilter.all) const SizedBox(width: 8),
                if (filter != MediaFilter.shows)
                  _Chip(
                    label: 'Movies',
                    selected: filter == MediaFilter.movies,
                    onTap: () => onFilter(
                        filter == MediaFilter.movies ? MediaFilter.all : MediaFilter.movies),
                  ),
                const SizedBox(width: 8),
                _Chip(
                  label: 'Categories',
                  trailing: Icons.keyboard_arrow_down_rounded,
                  onTap: () => showCategoryPicker(context),
                ),
                if (filter == MediaFilter.all && AppPrefs.to.adultEnabled.value) ...[
                  const SizedBox(width: 8),
                  _Chip(label: '18+', onTap: onAdult),
                ],
              ],
            )),
          ),
        ],
      ),
    );
    return ValueListenableBuilder<double>(
      valueListenable: opacity,
      builder: (context, v, child) => ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18 * v, sigmaY: 18 * v),
          child: DecoratedBox(
            decoration: BoxDecoration(
              // A soft scrim over the hero that becomes frosted glass on scroll.
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(Colors.black45, bg.withValues(alpha: 0.86), v)!,
                  Color.lerp(Colors.transparent, bg.withValues(alpha: 0.86), v)!,
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
      child: bar,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({this.label, this.icon, this.trailing, this.semantic, this.selected = false, required this.onTap});
  final String? label;
  final IconData? icon;
  final IconData? trailing;
  final String? semantic;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semantic ?? label,
      excludeSemantics: true,
      child: Material(
        color: selected ? Colors.white.withValues(alpha: 0.18) : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: selected ? 0.0 : 0.45))),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: label == null ? 7 : 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) Icon(icon, color: Colors.white, size: 18),
                if (label != null)
                  Text(label!,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                if (trailing != null) Icon(trailing, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _noop() {}

// ─── Hero card ─────────────────────────────────────────────────────────────────

/// A swipeable poster card for the feed's featured titles, on a glow tinted
/// from the poster.
class _HeroCard extends StatefulWidget {
  const _HeroCard({required this.filter, required this.topInset, this.adult = false});
  final MediaFilter filter;
  final bool adult;
  final double topInset;

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  final HomeScreenController c = Get.find<HomeScreenController>();
  final PageController _pages = PageController(viewportFraction: 0.86);
  int _index = 0;
  Timer? _rotate;

  @override
  void initState() {
    super.initState();
    _restartRotation();
  }

  @override
  void didUpdateWidget(covariant _HeroCard old) {
    super.didUpdateWidget(old);
    if (old.filter != widget.filter || old.adult != widget.adult) {
      _index = 0;
      if (_pages.hasClients) _pages.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _rotate?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _restartRotation() {
    _rotate?.cancel();
    _rotate = Timer.periodic(const Duration(seconds: 9), (_) {
      final n = _items().length;
      if (n > 1 && _pages.hasClients) {
        _pages.animateToPage((_index + 1) % n,
            duration: const Duration(milliseconds: 550), curve: Curves.easeOutCubic);
      }
    });
  }

  /// Featured subjects: the banner's titles, or — when a chip filters them
  /// all out — the top of the ranking list of that kind.
  List<Subject> _items() {
    final f = widget.filter;
    if (widget.adult) {
      final featured = c.adultBanners.map((b) => b.subject!).toList();
      if (featured.isNotEmpty) return featured;
      return c.adultRows.isEmpty ? const [] : dedupeTitles(c.adultRows.first.subjects).take(6).toList();
    }
    final fromBanners = c.banners.map((b) => b.subject!).where(f.matches).toList();
    if (fromBanners.isNotEmpty) return fromBanners;
    return dedupeTitles(c.subjectsList.where(f.matches)).take(6).toList();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardW = width * 0.86 - 12;
    final cardH = (cardW * 1.36).clamp(300.0, 560.0);
    return Obx(() {
      final items = _items();
      if (items.isEmpty) {
        final loading = c.isFeedLoading.value || c.isLoading.value || (widget.adult && c.isAdultLoading.value);
        return Padding(
          padding: EdgeInsets.only(top: widget.topInset, bottom: 8),
          child: loading
              ? _HeroSkeleton(cardW: cardW, cardH: cardH)
              : SizedBox(
                  height: cardH + 20,
                  child: const Center(
                    child: Text('Featured titles are unavailable right now.',
                        style: TextStyle(color: Colors.white38, fontSize: 14)),
                  ),
                ),
        );
      }
      final current = items[_index.clamp(0, items.length - 1)];
      final tint = _hex(current.cover?.avgHueDark) ?? const Color(0xFF3A1F4F);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        padding: EdgeInsets.only(top: widget.topInset, bottom: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tint, tint.withValues(alpha: 0.45), Theme.of(context).scaffoldBackgroundColor],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: cardH,
              child: NotificationListener<ScrollStartNotification>(
                // A finger swipe restarts the auto-advance timer.
                onNotification: (n) {
                  if (n.dragDetails != null) _restartRotation();
                  return false;
                },
                child: PageView.builder(
                  controller: _pages,
                  itemCount: items.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: _HeroPoster(subject: items[i]),
                  ),
                ),
              ),
            ),
            if (items.length > 1) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < items.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _index ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        gradient: i == _index ? kBrandGradient : null,
                        color: i == _index ? null : Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    });
  }
}

/// The hero card while the feed loads: the card (with the next one peeking
/// in, as the 0.86 viewport shows it), its genre line and two buttons, and the
/// page dots.
class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton({required this.cardW, required this.cardH});
  final double cardW;
  final double cardH;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final side = (width - width * 0.86) / 2 + 6; // PageView inset + card padding
    Widget card({bool content = true}) => Container(
          width: cardW,
          height: cardH,
          decoration: BoxDecoration(color: Skeleton.base, borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.all(14),
          alignment: Alignment.bottomCenter,
          child: content
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Bone.text(width: 150, fontSize: 13),
                    SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: Bone(height: 42, radius: 6)),
                      SizedBox(width: 10),
                      Expanded(child: Bone(height: 42, radius: 6)),
                    ]),
                  ],
                )
              : null,
        );
    return Skeleton(
      child: Column(
        children: [
          SizedBox(
            height: cardH,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [SizedBox(width: side), card(), const SizedBox(width: 12), card(content: false)],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Bone(width: 16, height: 6, radius: 3),
              for (var i = 0; i < 5; i++) ...[
                const SizedBox(width: 6),
                const Bone(width: 6, height: 6, radius: 3),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

Color? _hex(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
  final v = int.tryParse(hex.substring(1), radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

class _HeroPoster extends StatefulWidget {
  const _HeroPoster({required this.subject});
  final Subject subject;

  @override
  State<_HeroPoster> createState() => _HeroPosterState();
}

class _HeroPosterState extends State<_HeroPoster> {
  late bool _inList = UserData.inMyList(widget.subject.subjectId);

  @override
  Widget build(BuildContext context) {
    final s = widget.subject;
    final url = s.cover?.url;
    final genres = (s.genre ?? '').split(',').where((g) => g.trim().isNotEmpty).take(3).toList();
    final progress = UserData.progressFraction(s.subjectId);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 10))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: kCard,
        child: InkWell(
          onTap: () => openDetail(s),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url != null && url.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: posterUrl(url, width: 700),
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 250),
                  placeholder: (_, _) => const SizedBox.shrink(),
                  errorWidget: (_, _, _) => PosterFallback(title: s.title),
                )
              else
                PosterFallback(title: s.title),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xE6000000)],
                    stops: [0.5, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (genres.isNotEmpty)
                      Text(genres.map((g) => g.trim()).join('  •  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: FilledButton.icon(
                              onPressed: () => openDetail(s, resume: true),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: kInk,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              icon: const Icon(Icons.play_arrow_rounded, size: 26),
                              label: Text(progress > 0 ? 'Resume' : 'Play'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: FilledButton.icon(
                              onPressed: () {
                                setState(() => _inList = UserData.toggleMyList(s));
                                Get.find<HomeScreenController>().refreshUserRows();
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.22),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              icon: Icon(_inList ? Icons.check_rounded : Icons.add_rounded, size: 24),
                              label: const Text('My List'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Rails ─────────────────────────────────────────────────────────────────────

const double _posterW = 108;
const double _posterH = 162;

class _Rail extends StatelessWidget {
  const _Rail({required this.title, required this.subjects, this.loading = false, this.onMore});
  final String title;
  final List<Subject> subjects;
  final bool loading;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final list = dedupeTitles(subjects);
    if (list.isEmpty && !loading) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RailTitle(title, onMore: onMore),
          SizedBox(
            height: _posterH,
            child: list.isEmpty
                ? const SkeletonRow(width: _posterW)
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) =>
                        PosterTile(subject: list[i], width: _posterW, height: _posterH),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A ranking category, loaded when its row is first built.
class _RankingRail extends StatelessWidget {
  const _RankingRail({required this.id, required this.name, required this.filter});
  final String id;
  final String name;
  final MediaFilter filter;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<HomeScreenController>();
    final list = c.rankingRow(id);
    return Obx(() {
      final loaded = c.rankingRowLoaded[id]?.value == true;
      return _Rail(
        title: name,
        subjects: list.where(filter.matches).toList(),
        loading: !loaded,
        onMore: () => Get.to(() => CategoryView(id: id, name: name), transition: Transition.rightToLeft),
      );
    });
  }
}

/// Netflix's Top 10: a giant outlined rank numeral tucked behind each poster.
class _Top10Rail extends StatelessWidget {
  const _Top10Rail({required this.title, required this.subjects, required this.loading});
  final String title;
  final List<Subject> subjects;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (subjects.isEmpty && !loading) return const SizedBox.shrink();
    const itemW = 150.0;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RailTitle(title),
          SizedBox(
            height: _posterH,
            child: subjects.isEmpty
                ? Skeleton(
                    // Numeral slot on the left, poster on the right, per item.
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(left: 4, right: 16),
                      itemCount: 5,
                      itemBuilder: (_, _) => SizedBox(
                        width: itemW,
                        child: const Row(
                          children: [
                            SizedBox(width: 14),
                            Bone(width: 20, height: 96, radius: 6),
                            Spacer(),
                            Bone(width: _posterW, height: _posterH),
                            SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(left: 4, right: 16),
                    itemCount: subjects.length,
                    itemBuilder: (_, i) => SizedBox(
                      width: itemW,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 0,
                            bottom: -18,
                            child: _RankNumeral(rank: i + 1),
                          ),
                          Positioned(
                            right: 4,
                            top: 0,
                            bottom: 0,
                            child: PosterTile(subject: subjects[i], width: _posterW, height: _posterH),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RankNumeral extends StatelessWidget {
  const _RankNumeral({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: rank == 10 ? 118 : 150,
      fontWeight: FontWeight.w900,
      height: 1.0,
      letterSpacing: rank == 10 ? -14 : 0,
    );
    return ExcludeSemantics(
      child: Stack(
        children: [
          Text('$rank',
              style: style.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 3
                  ..color = Colors.white70,
              )),
          Text('$rank', style: style.copyWith(color: Theme.of(context).scaffoldBackgroundColor)),
        ],
      ),
    );
  }
}

/// Continue Watching: tap resumes; the strip under each poster shows the
/// progress and opens the preview sheet or a remove menu.
class _ContinueRail extends StatelessWidget {
  const _ContinueRail({required this.subjects});
  final List<Subject> subjects;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RailTitle('Continue Watching'),
          SizedBox(
            height: _posterH + 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: subjects.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ContinueTile(subject: subjects[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class ContinueTile extends StatelessWidget {
  const ContinueTile({super.key, required this.subject, this.width = _posterW, this.height = _posterH});
  final Subject subject;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final url = subject.cover?.url;
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Column(
          children: [
            Semantics(
              button: true,
              label: 'Resume ${subject.title ?? ''}',
              excludeSemantics: true,
              child: Material(
                color: kCard,
                child: InkWell(
                  onTap: () => openDetail(subject, resume: true),
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (url != null && url.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: posterUrl(url),
                            fit: BoxFit.cover,
                            placeholder: (_, _) => const SizedBox.shrink(),
                            errorWidget: (_, _, _) => PosterFallback(title: subject.title),
                          )
                        else
                          PosterFallback(title: subject.title),
                        Center(
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: UserData.progressFraction(subject.subjectId),
                            minHeight: 3,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation(kBrandRed),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              height: 40,
              color: const Color(0xFF1A1A21),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Info',
                    onPressed: () => showPreviewSheet(subject, resume: true),
                    icon: const Icon(Icons.info_outline_rounded, color: Colors.white70, size: 20),
                  ),
                  IconButton(
                    tooltip: 'More',
                    onPressed: () => _showContinueMenu(subject),
                    icon: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showContinueMenu(Subject s) {
  Get.bottomSheet(
    SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(s.title ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded, color: Colors.white),
            title: const Text('Episodes & Info', style: TextStyle(color: Colors.white)),
            onTap: () {
              Get.back();
              openDetail(s);
            },
          ),
          if (AppPrefs.to.adultEnabled.value)
            ListTile(
              leading: const Icon(Icons.nightlight_round, color: Colors.white),
              title: const Text('Move to Midnight (18+)', style: TextStyle(color: Colors.white)),
              onTap: () {
                Get.back();
                if (s.subjectId != null) UserData.markAdult(s.subjectId!);
                Get.find<HomeScreenController>().refreshUserRows();
              },
            ),
          ListTile(
            leading: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white),
            title: const Text('Remove from Row', style: TextStyle(color: Colors.white)),
            onTap: () {
              Get.back();
              UserData.removeContinue(s.subjectId);
              Get.find<HomeScreenController>().refreshUserRows();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
    backgroundColor: const Color(0xFF1F1F27),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
  );
}
