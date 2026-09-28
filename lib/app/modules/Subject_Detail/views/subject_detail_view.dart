import 'dart:math' as math;
import '../../../services/download_service.dart';
import '../../downloads/downloads_view.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import '../../../../app_theme.dart';
import '../../../model/subject_list.dart';
import '../../../widgets/tv_focusable.dart';
import '../controllers/subject_detail_controller.dart';

/// Title detail.
///
/// TV (≥ 900 wide): the title's wide art (stills / trailer frame, then the
/// muted trailer itself) feathered into the top-right of a page lit by one
/// ambient glow in the poster's hue — the same light as the TV home, with no
/// panel or edge anywhere. Text and calm focus-driven buttons sit on the
/// left; seasons, episodes and cast follow below.
///
/// Phone: feathered art header, full-width Play, icon actions, episode list.
class SubjectDetailView extends GetView<SubjectDetailController> {
  const SubjectDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: LayoutBuilder(builder: (context, constraints) {
        final tv = constraints.maxWidth >= 900;
        return Obx(() {
          final id = controller.subject.value?.subjectId ?? '';
          final Widget child = controller.isLoading.value
              ? _Skeleton(key: const ValueKey('loading'), tv: tv)
              : (tv
                  ? _TvDetail(key: ValueKey('tv-$id'))
                  : _MobileDetail(key: ValueKey('mobile-$id')));
          // Fade the page in; drop the old one at once so a quick audio
          // switch never has two pages sharing the Play focus node.
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            reverseDuration: Duration.zero,
            child: child,
          );
        });
      }),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TV
// ═════════════════════════════════════════════════════════════════════════════

const double _tvSide = 48; // ≈ 5% overscan-safe margin at 960 wide
const double _tvTop = 44;
const double _epW = 100;
const double _epH = 60;
const double _epGap = 10;
const Duration _tvMove = Duration(milliseconds: 260);
const Color _ink = Color(0xFF111114); // text on a focused (white) control

enum _Section { actions, seasons, episodes }

class _TvDetail extends StatefulWidget {
  const _TvDetail({super.key});

  @override
  State<_TvDetail> createState() => _TvDetailState();
}

/// Owns D-pad movement explicitly — UP/DOWN hop between the button row, the
/// season chips and the episode row; LEFT/RIGHT walk within a row and stop at
/// its ends — and keeps whatever is focused on screen.
class _TvDetailState extends State<_TvDetail> {
  final SubjectDetailController c = Get.find<SubjectDetailController>();
  final ScrollController _page = ScrollController();
  final ScrollController _episodeList = ScrollController();
  final GlobalKey _episodesKey = GlobalKey();

  final Map<String, FocusNode> _actionNodes = {};
  final Map<int, FocusNode> _seasonNodes = {};
  final Map<int, FocusNode> _episodeNodes = {};
  List<String> _actionIds = const [];
  int _actionIndex = 0;
  int? _episodeIndex; // last focused tile in the selected season

  @override
  void initState() {
    super.initState();
    // Open the episode row on the saved episode.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final saved = _savedIndex();
      if (saved != null && _episodeList.hasClients) {
        _episodeList.jumpTo(_episodeOffset(saved));
      }
    });
  }

  @override
  void dispose() {
    _page.dispose();
    _episodeList.dispose();
    for (final n in [..._actionNodes.values, ..._seasonNodes.values, ..._episodeNodes.values]) {
      n.dispose();
    }
    super.dispose();
  }

  List<SeasonResource> get _seasons => c.resource.value?.seasons ?? const [];
  List<int> get _episodes => c.episodesFor(c.selectedSeason.value);

  FocusNode _actionNode(String id) => id == 'play'
      ? c.playButtonFocusNode
      : _actionNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'action-$id'));
  FocusNode _seasonNode(int i) => _seasonNodes.putIfAbsent(i, () => FocusNode());
  FocusNode _episodeNode(int i) => _episodeNodes.putIfAbsent(i, () => FocusNode());

  List<_Section> get _sections => [
        _Section.actions,
        if (!c.isMovie && _seasons.length > 1) _Section.seasons,
        if (!c.isMovie && _episodes.isNotEmpty) _Section.episodes,
      ];

  // ── Vertical ──────────────────────────────────────────────────────────────

  void _vertical(_Section from, int delta) {
    final list = _sections;
    final i = list.indexOf(from) + delta;
    if (i < 0 || i >= list.length) return; // nothing further that way
    switch (list[i]) {
      case _Section.actions:
        _focusAction(_actionIndex);
      case _Section.seasons:
        final idx = _seasons.indexWhere((s) => s.se == c.selectedSeason.value);
        _seasonNode(idx < 0 ? 0 : idx).requestFocus();
      case _Section.episodes:
        _focusEpisode(_episodeIndex ?? _savedIndex() ?? 0);
    }
  }

  void _onSectionFocused(_Section s) {
    if (!_page.hasClients) return;
    if (s == _Section.actions) {
      _page.animateTo(0, duration: _tvMove, curve: Curves.easeOutCubic);
      return;
    }
    // Bring the episodes block near the top; whatever follows (cast) shows
    // underneath it.
    final box = _episodesKey.currentContext?.findRenderObject();
    if (box == null) return;
    final top = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
    final target = (top - 28).clamp(0.0, _page.position.maxScrollExtent);
    _page.animateTo(target, duration: _tvMove, curve: Curves.easeOutCubic);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _focusAction(int i) {
    if (_actionIds.isEmpty) return;
    _actionNode(_actionIds[i.clamp(0, _actionIds.length - 1)]).requestFocus();
  }

  // ── Seasons ───────────────────────────────────────────────────────────────

  void _onSeasonFocused(int index) {
    final se = _seasons[index].se ?? index + 1;
    if (se == c.selectedSeason.value) return;
    // Focus picks the season: the episode row follows right away.
    c.selectedSeason.value = se;
    _episodeIndex = null;
    // After the new season's row has laid out (its extent differs).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_episodeList.hasClients) return;
      final saved = _savedIndex();
      _episodeList.jumpTo(saved == null ? 0 : _episodeOffset(saved));
    });
  }

  // ── Episodes ──────────────────────────────────────────────────────────────

  /// Index of the saved "continue" episode in the selected season, if any.
  int? _savedIndex() {
    if (!c.hasSavedProgress.value || c.lastPlayedSeason.value != c.selectedSeason.value) {
      return null;
    }
    final i = _episodes.indexOf(c.lastPlayedEpisode.value ?? -1);
    return i < 0 ? null : i;
  }

  /// Scroll offset that shows tile [i] with one tile of context on its left.
  double _episodeOffset(int i) {
    final raw = math.max(0.0, (i - 1) * (_epW + _epGap));
    if (!_episodeList.hasClients) return raw;
    return raw.clamp(0.0, _episodeList.position.maxScrollExtent);
  }

  void _focusEpisode(int i) {
    final count = _episodes.length;
    if (count == 0) return;
    final node = _episodeNode(i.clamp(0, count - 1));
    if (node.context != null) {
      node.requestFocus();
      return;
    }
    // Not built yet (far down a long season): scroll there, focus next frame.
    if (_episodeList.hasClients) _episodeList.jumpTo(_episodeOffset(i));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  void _onEpisodeFocused(int i) {
    _episodeIndex = i;
    if (!_episodeList.hasClients) return;
    final pos = _episodeList.position;
    final left = i * (_epW + _epGap);
    final step = _epW + _epGap;
    double? target;
    if (left - step < pos.pixels) {
      target = left - step;
    } else if (left + _epW + step > pos.pixels + pos.viewportDimension - _tvSide) {
      target = left + _epW + step - pos.viewportDimension + _tvSide;
    }
    if (target != null) {
      _episodeList.animateTo(target.clamp(0.0, pos.maxScrollExtent),
          duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _TvBackdrop(scroll: _page),
        Obx(() {
          final s = c.subject.value!;
          return SingleChildScrollView(
            controller: _page,
            // Scrolling follows focus only.
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: _tvTop, bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _tvSide),
                  child: _TvHeadline(subject: s),
                ),
                const SizedBox(height: 18),
                _rowKeys(
                  section: _Section.actions,
                  onHorizontal: (d) => _focusAction(_actionIndex + d),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _tvSide),
                    child: _actionsRow(),
                  ),
                ),
                if (!c.isMovie && _episodes.isNotEmpty) ...[
                  const SizedBox(height: 30),
                  _episodesBlock(),
                ],
                if (c.cast.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _TvCast(cast: c.cast.toList()),
                ],
                if (c.subtitleLanguages.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _tvSide),
                    child: _SubtitleLine(languages: c.subtitleLanguages.toList()),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  /// Wraps a row: reports when focus enters it and routes the D-pad.
  Widget _rowKeys({
    required _Section section,
    required ValueChanged<int> onHorizontal,
    required Widget child,
  }) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) {
        if (f) _onSectionFocused(section);
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          _vertical(section, -1);
        } else if (key == LogicalKeyboardKey.arrowDown) {
          _vertical(section, 1);
        } else if (key == LogicalKeyboardKey.arrowLeft) {
          onHorizontal(-1);
        } else if (key == LogicalKeyboardKey.arrowRight) {
          onHorizontal(1);
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: child,
    );
  }

  Widget _actionsRow() {
    final play = _PlayInfo.of(c);
    final canRestart = c.hasSavedProgress.value && c.lastPlayedPosition.value > Duration.zero;
    final specs = <(String, Widget Function(FocusNode, bool))>[
      if (c.canPlay)
        ('play', (node, first) => _TvButton(
              focusNode: node,
              autofocus: true,
              primary: true,
              icon: Icons.play_arrow_rounded,
              busy: c.isStarting.value,
              label: play.label,
              semantics: play.caption == null ? null : '${play.label}, ${play.caption}',
              onSelect: play.action,
            )),
      if (canRestart)
        ('restart', (node, first) => _TvButton(
              focusNode: node,
              autofocus: first,
              icon: Icons.replay_rounded,
              label: c.isMovie ? 'Start over' : 'Restart episode',
              onSelect: c.restartSaved,
            )),
      ('list', (node, first) => _TvButton(
            focusNode: node,
            autofocus: first,
            icon: c.inMyList.value ? Icons.check_rounded : Icons.add_rounded,
            label: c.inMyList.value ? 'In My List' : 'My List',
            onSelect: c.toggleMyList,
          )),
      if (c.dubs.length > 1)
        ('audio', (node, first) => _TvButton(
              focusNode: node,
              autofocus: first,
              icon: Icons.graphic_eq_rounded,
              label: _dubButtonLabel(c.currentDub),
              semantics: 'Audio: ${_dubButtonLabel(c.currentDub)}. ${c.dubs.length} versions',
              onSelect: () => _showAudioPicker(c),
            )),
    ];
    _actionIds = [for (final s in specs) s.$1];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (play.progress != null && play.progress! > 0) ...[
          Row(
            children: [
              SizedBox(width: 150, child: _ProgressLine(value: play.progress!, track: Colors.white24)),
              if (play.caption != null) ...[
                const SizedBox(width: 10),
                Text(play.caption!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ],
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            for (var i = 0; i < specs.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (f) {
                  if (f) _actionIndex = i;
                },
                child: specs[i].$2(_actionNode(specs[i].$1), i == 0),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _episodesBlock() {
    final seasons = _seasons;
    final season = c.selectedSeason.value;
    final episodes = _episodes;
    final saved = _savedIndex();
    return Column(
      key: _episodesKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _tvSide),
          child: Row(
            children: [
              const Text('Episodes',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Text(
                [
                  if (seasons.length <= 1) 'Season $season',
                  '${episodes.length} episode${episodes.length == 1 ? '' : 's'}',
                ].join('  ·  '),
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
        if (seasons.length > 1) ...[
          const SizedBox(height: 12),
          _rowKeys(
            section: _Section.seasons,
            onHorizontal: (d) {
              final i = seasons.indexWhere((s) => s.se == season) + d;
              if (i >= 0 && i < seasons.length) _seasonNode(i).requestFocus();
            },
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: _tvSide, vertical: 2),
              child: Row(
                children: [
                  for (var i = 0; i < seasons.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _SeasonChip(
                      focusNode: _seasonNode(i),
                      label: 'Season ${seasons[i].se ?? i + 1}',
                      selected: (seasons[i].se ?? i + 1) == season,
                      onFocused: () => _onSeasonFocused(i),
                      // OK on a chip drops straight into its episodes.
                      onSelect: () => _vertical(_Section.seasons, 1),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        _rowKeys(
          section: _Section.episodes,
          onHorizontal: (d) {
            final i = (_episodeIndex ?? 0) + d;
            if (i >= 0 && i < episodes.length) _focusEpisode(i);
          },
          child: SizedBox(
            height: _epH + 12,
            child: ListView.separated(
              controller: _episodeList,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: _tvSide, vertical: 6),
              itemCount: episodes.length,
              separatorBuilder: (_, _) => const SizedBox(width: _epGap),
              itemBuilder: (_, i) {
                final current = i == saved;
                return _EpisodeTile(
                  focusNode: _episodeNode(i),
                  episode: episodes[i],
                  current: current,
                  resumable: current && c.lastPlayedPosition.value > Duration.zero,
                  progress: current ? c.progressFraction.value : 0,
                  onFocused: () => _onEpisodeFocused(i),
                  onSelect: () => c.playEpisode(season, episodes[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Kicker, title, meta and synopsis.
class _TvHeadline extends GetView<SubjectDetailController> {
  const _TvHeadline({required this.subject});
  final Subject subject;

  // A soft shadow keeps text crisp wherever the art bleeds under it.
  static const _lift = [Shadow(color: Color(0x99000000), blurRadius: 12)];

  @override
  Widget build(BuildContext context) {
    final description = (subject.description ?? '').trim();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GenreLine(subject: subject),
          const SizedBox(height: 8),
          Text(
            subject.title ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              height: 1.08,
              shadows: _lift,
            ),
          ),
          const SizedBox(height: 12),
          const _MetaLine(),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xDDFFFFFF),
                fontSize: 14,
                height: 1.5,
                shadows: _lift,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One light for the whole page plus the title's art, feathered on every
/// side it doesn't share with the screen edge — nothing here has an edge.
///
/// * Ambient: the same radial glow as the TV home ([avgHueDark] of the
///   poster, from the top-left, fading to nothing).
/// * Art: the wide still / trailer frame, then the muted trailer on top of
///   it, masked to transparent (not painted over with the page colour), so
///   it melts into the glow instead of stopping at a box.
/// * No wide art at all: the portrait poster floats on the right instead.
class _TvBackdrop extends StatelessWidget {
  const _TvBackdrop({required this.scroll});
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SubjectDetailController>();
    final size = MediaQuery.sizeOf(context);
    final artW = size.width * 0.68;
    final artH = artW * 9 / 16;
    return IgnorePointer(
      child: Obx(() {
        final s = c.subject.value;
        final tint = _hexColor(s?.cover?.avgHueDark) ?? kBrandPurple.withValues(alpha: 0.5);
        final wide = _wideArtUrl(s);
        final trailer = c.videoPlayerController.value;
        final hasTrailer = trailer != null && trailer.value.isInitialized;
        final playing = hasTrailer && c.showTrailer.value;
        final poster = s?.cover?.url;
        return Stack(
          fit: StackFit.expand,
          children: [
            _AmbientGlow(tint: tint),
            if (wide != null || hasTrailer)
              Positioned(
                top: 0,
                right: 0,
                width: artW,
                height: artH,
                child: _ScrollDim(
                  scroll: scroll,
                  child: _Feather(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (wide != null)
                          CachedNetworkImage(
                            imageUrl: '$wide?x-oss-process=image/resize%2Cw_1280',
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 400),
                            errorWidget: (_, _, _) => const SizedBox.shrink(),
                          ),
                        if (hasTrailer)
                          AnimatedOpacity(
                            opacity: playing ? 1 : 0,
                            duration: const Duration(milliseconds: 900),
                            child: ClipRect(
                              // A touch of zoom trims letterbox lines baked
                              // into some trailers.
                              child: Transform.scale(
                                scale: 1.08,
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: trailer.value.size.width,
                                    height: trailer.value.size.height,
                                    child: VideoPlayer(trailer),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            if (wide == null && poster != null && poster.isNotEmpty)
              Positioned(
                top: _tvTop,
                right: _tvSide + 8,
                width: 190,
                height: 285,
                child: AnimatedOpacity(
                  // Yields to the trailer once it plays.
                  opacity: playing ? 0 : 1,
                  duration: const Duration(milliseconds: 600),
                  child: _ScrollDim(scroll: scroll, child: _PosterCard(url: poster)),
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// Same glow as the TV home's ambient tint: one radial falloff, no edge.
class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({required this.tint});
  final Color tint;

  @override
  Widget build(BuildContext context) {
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
  }
}

/// Fades its child's own alpha out towards the left, the bottom and (just a
/// little) the top, with eased multi-stop ramps.
class _Feather extends StatelessWidget {
  const _Feather({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        colors: [Color(0x00000000), Color(0x1F000000), Color(0x73000000), Color(0xD9000000), Color(0xFF000000)],
        stops: [0.0, 0.18, 0.38, 0.58, 0.74],
      ).createShader(rect),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x99000000), Color(0xFF000000), Color(0xFF000000), Color(0x66000000), Color(0x00000000)],
          stops: [0.0, 0.1, 0.5, 0.78, 1.0],
        ).createShader(rect),
        child: child,
      ),
    );
  }
}

/// Dims the art as the page scrolls down to episodes / cast, so the lower
/// sections read cleanly over it.
class _ScrollDim extends StatelessWidget {
  const _ScrollDim({required this.scroll, required this.child});
  final ScrollController scroll;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scroll,
      child: child,
      builder: (context, child) {
        final off = scroll.hasClients ? scroll.offset : 0.0;
        final t = (off / 200).clamp(0.0, 1.0);
        return t == 0 ? child! : Opacity(opacity: 1 - 0.55 * t, child: child);
      },
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 32, offset: Offset(0, 14))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: '$url?x-oss-process=image/resize%2Cw_400',
          fit: BoxFit.cover,
          placeholder: (_, _) => const ColoredBox(color: Color(0xFF1C1C24)),
          errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF1C1C24)),
        ),
      ),
    );
  }
}

/// Calm TV button, same language as the home billboard: a soft translucent
/// fill that turns solid white with dark text (and grows a touch) when the
/// D-pad lands on it. No ring, no glow.
class _TvButton extends StatelessWidget {
  const _TvButton({
    required this.label,
    required this.onSelect,
    required this.icon,
    this.semantics,
    this.focusNode,
    this.autofocus = false,
    this.primary = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback onSelect;
  final IconData icon;
  final String? semantics;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantics ?? label,
      child: TvFocusable(
        focusNode: focusNode,
        autofocus: autofocus,
        onSelect: busy ? () {} : onSelect,
        builder: (context, focused) {
          final fg = focused ? _ink : Colors.white;
          return AnimatedScale(
            scale: focused ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 42,
              padding: const EdgeInsets.fromLTRB(14, 0, 18, 0),
              decoration: BoxDecoration(
                color: focused
                    ? Colors.white
                    : Colors.white.withValues(alpha: primary ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: busy
                        ? Padding(
                            padding: const EdgeInsets.all(2),
                            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                          )
                        : Icon(icon, size: 22, color: fg),
                  ),
                  const SizedBox(width: 8),
                  Text(label,
                      style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Season pill. Calm like the buttons: white when focused, a soft fill for
/// the selected season, bare text otherwise.
class _SeasonChip extends StatelessWidget {
  const _SeasonChip({
    required this.label,
    required this.selected,
    required this.onSelect,
    this.onFocused,
    this.focusNode,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onFocused;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onFocusChange: (f) {
          if (f) onFocused?.call();
        },
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 32,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: focused
                ? Colors.white
                : Colors.white.withValues(alpha: selected ? 0.16 : 0.0),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(label,
              style: TextStyle(
                color: focused ? _ink : (selected ? Colors.white : Colors.white60),
                fontSize: 13,
                fontWeight: selected || focused ? FontWeight.w700 : FontWeight.w500,
              )),
        ),
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.focusNode,
    required this.episode,
    required this.current,
    required this.resumable,
    required this.progress,
    required this.onFocused,
    required this.onSelect,
  });

  final FocusNode focusNode;
  final int episode;
  final bool current; // the saved "continue" episode
  final bool resumable; // …with a position to resume from
  final double progress;
  final VoidCallback onFocused;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final caption = current ? (resumable ? 'Resume' : 'Up next') : 'Episode';
    return Semantics(
      button: true,
      label: 'Episode $episode${current ? ', $caption' : ''}',
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        onFocusChange: (f) {
          if (f) onFocused();
        },
        builder: (context, focused) => AnimatedScale(
          scale: focused ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: _epW,
            height: _epH,
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white
                  : Colors.white.withValues(alpha: current ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 10, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(caption.toUpperCase(),
                          style: TextStyle(
                            color: focused ? Colors.black54 : (current ? Colors.white70 : Colors.white38),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          )),
                      const SizedBox(height: 1),
                      Text('$episode',
                          style: TextStyle(
                            color: focused ? _ink : Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          )),
                    ],
                  ),
                ),
                if (current && progress > 0)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 7,
                    child: _ProgressLine(
                        value: progress, track: focused ? Colors.black12 : Colors.white24),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of cast, as many as fit the width (never a clipped last face).
/// Not focusable — there's nothing to open for a person.
class _TvCast extends StatelessWidget {
  const _TvCast({required this.cast});
  final List<Star> cast;

  static const double _itemW = 82;
  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _tvSide),
      child: LayoutBuilder(builder: (context, constraints) {
        final fit = ((constraints.maxWidth + _gap) / (_itemW + _gap)).floor();
        final shown = cast.take(math.max(1, fit)).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Cast',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                if (cast.length > shown.length) ...[
                  const SizedBox(width: 10),
                  Text('${shown.length} of ${cast.length}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  SizedBox(width: _itemW, child: _CastMember(star: shown[i], avatar: 50)),
                ],
              ],
            ),
          ],
        );
      }),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Phone
// ═════════════════════════════════════════════════════════════════════════════

class _MobileDetail extends GetView<SubjectDetailController> {
  const _MobileDetail({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final top = MediaQuery.paddingOf(context).top;
    return Obx(() {
      final s = controller.subject.value!;
      final tint = _hexColor(s.cover?.avgHueDark) ?? kBrandPurple.withValues(alpha: 0.5);
      final art = _wideArtUrl(s) ?? s.cover?.url;
      final play = _PlayInfo.of(controller);
      final canRestart = controller.hasSavedProgress.value &&
          controller.lastPlayedPosition.value > Duration.zero;
      final heroH = width * 10 / 16 + top;

      return Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(child: _AmbientGlow(tint: tint)),
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: heroH,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (art != null && art.isNotEmpty)
                        // Masked, not overpainted: it fades into the glow.
                        ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF000000), Color(0xCC000000), Color(0x00000000)],
                            stops: [0.0, 0.55, 1.0],
                          ).createShader(rect),
                          child: CachedNetworkImage(
                            imageUrl: '$art?x-oss-process=image/resize%2Cw_900',
                            fit: BoxFit.cover,
                            alignment: const Alignment(0, -0.35),
                            errorWidget: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      // Keeps the status bar and back button legible.
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x73000000), Color(0x00000000)],
                            stops: [0.0, 0.35],
                          ),
                        ),
                      ),
                      Positioned(
                        top: top + 8,
                        left: 8,
                        child: IconButton(
                          tooltip: 'Back',
                          onPressed: Get.back,
                          style: IconButton.styleFrom(backgroundColor: Colors.black38),
                          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList.list(
                  children: [
                    _GenreLine(subject: s),
                    const SizedBox(height: 6),
                    Text(s.title ?? '',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            height: 1.15)),
                    const SizedBox(height: 10),
                    const _MetaLine(),
                    const SizedBox(height: 16),
                    if (controller.canPlay) ...[
                      SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: controller.isStarting.value ? null : play.action,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: _ink,
                            disabledBackgroundColor: Colors.white70,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          icon: controller.isStarting.value
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                                )
                              : const Icon(Icons.play_arrow_rounded, size: 26),
                          label: Text(play.label),
                        ),
                      ),
                      if (play.progress != null && play.progress! > 0) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _ProgressLine(value: play.progress!, track: Colors.white24)),
                            if (play.caption != null) ...[
                              const SizedBox(width: 10),
                              Text(play.caption!,
                                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
                            ],
                          ],
                        ),
                      ],
                    ],
                    if (controller.canPlay && controller.isMovie && DownloadService.supported) ...[
                      const SizedBox(height: 10),
                      const _MovieDownloadButton(),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _IconAction(
                          icon: controller.inMyList.value ? Icons.check_rounded : Icons.add_rounded,
                          label: controller.inMyList.value ? 'In My List' : 'My List',
                          onTap: controller.toggleMyList,
                        ),
                        if (canRestart)
                          _IconAction(
                            icon: Icons.replay_rounded,
                            label: 'Start over',
                            onTap: controller.restartSaved,
                          ),
                        if (controller.dubs.length > 1)
                          _IconAction(
                            icon: Icons.graphic_eq_rounded,
                            label: _dubButtonLabel(controller.currentDub),
                            onTap: () => _showAudioPicker(controller),
                          ),
                      ],
                    ),
                    if ((s.description ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _ExpandableText(s.description!.trim()),
                    ],
                    if (controller.subtitleLanguages.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _SubtitleLine(languages: controller.subtitleLanguages.toList()),
                    ],
                    if (!controller.isMovie) ...[
                      const SizedBox(height: 24),
                      const _MobileEpisodes(),
                    ],
                    if (controller.cast.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _MobileCast(cast: controller.cast.toList()),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
}

/// Netflix's grey "Download" button under Play, for a movie.
class _MovieDownloadButton extends GetView<SubjectDetailController> {
  const _MovieDownloadButton();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      DownloadService.to.items.length; // rebuild on any download change
      final item = controller.downloadFor(0, 0);
      final state = item?.state;
      final (IconData icon, String label) = switch (state) {
        null => (Icons.download_rounded, 'Download'),
        DownloadState.complete => (Icons.download_done_rounded, 'Downloaded'),
        DownloadState.running => (Icons.downloading_rounded, 'Downloading ' '${(item!.progress * 100).round()}%'),
        DownloadState.paused => (Icons.pause_rounded, 'Paused · tap to resume'),
        DownloadState.queued => (Icons.schedule_rounded, item!.waitingForWifi ? 'Waiting for Wi-Fi' : 'Queued'),
        DownloadState.failed => (Icons.refresh_rounded, 'Download failed · retry'),
      };
      return SizedBox(
        height: 46,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FilledButton.icon(
              onPressed: () {
                if (item == null || state == DownloadState.failed) {
                  controller.download(0, 0);
                } else if (state == DownloadState.paused) {
                  DownloadService.to.resume(item);
                } else if (state == DownloadState.complete) {
                  playDownload(item);
                } else {
                  Get.to(() => const DownloadsView());
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.14),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              icon: Icon(icon, size: 22),
              label: Text(label),
            ),
            if (state == DownloadState.running || state == DownloadState.paused)
              Positioned(
                left: 10,
                right: 10,
                bottom: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: item!.progress.clamp(0.0, 1.0),
                    minHeight: 2,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation(kBrandPurple),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

/// Per-episode download state: an arrow, a progress ring, or a check.
class _EpisodeDownload extends GetView<SubjectDetailController> {
  const _EpisodeDownload({required this.season, required this.episode});
  final int season;
  final int episode;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      DownloadService.to.items.length;
      final item = controller.downloadFor(season, episode);
      final state = item?.state;
      Widget icon;
      String tip;
      switch (state) {
        case null:
          icon = const Icon(Icons.download_rounded, color: Colors.white70);
          tip = 'Download episode $episode';
        case DownloadState.complete:
          icon = const Icon(Icons.download_done_rounded, color: Color(0xFF3DDC84));
          tip = 'Downloaded';
        case DownloadState.failed:
          icon = const Icon(Icons.error_outline_rounded, color: kBrandRed);
          tip = 'Retry download';
        case DownloadState.running:
        case DownloadState.paused:
        case DownloadState.queued:
          icon = SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              value: state == DownloadState.queued ? null : item!.progress.clamp(0.0, 1.0),
              strokeWidth: 2.5,
              color: kBrandPurple,
              backgroundColor: Colors.white12,
            ),
          );
          tip = 'Downloading';
      }
      return IconButton(
        tooltip: tip,
        onPressed: () {
          if (item == null || state == DownloadState.failed) {
            controller.download(season, episode);
          } else if (state == DownloadState.complete) {
            playDownload(item);
          } else {
            Get.to(() => const DownloadsView());
          }
        },
        icon: icon,
      );
    });
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 24),
                const SizedBox(height: 4),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileEpisodes extends GetView<SubjectDetailController> {
  const _MobileEpisodes();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final seasons = controller.resource.value?.seasons ?? const <SeasonResource>[];
      final season = controller.selectedSeason.value;
      final episodes = controller.episodesFor(season);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Episodes',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              if (seasons.length <= 1)
                Text('Season $season',
                    style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
          if (DownloadService.supported && episodes.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => controller.downloadSeason(season),
                style: TextButton.styleFrom(foregroundColor: Colors.white70, padding: EdgeInsets.zero),
                icon: const Icon(Icons.download_rounded, size: 20),
                label: Text('Download Season $season'),
              ),
            ),
          if (seasons.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: seasons.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final se = seasons[i].se ?? i + 1;
                  return Center(
                    child: _SeasonChip(
                      label: 'Season $se',
                      selected: se == season,
                      onSelect: () => controller.selectedSeason.value = se,
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 6),
          if (episodes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No episodes listed for this season yet.',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
            ),
          for (final ep in episodes)
            Builder(builder: (context) {
              final saved = controller.hasSavedProgress.value &&
                  controller.lastPlayedSeason.value == season &&
                  controller.lastPlayedEpisode.value == ep;
              final resumable = saved && controller.lastPlayedPosition.value > Duration.zero;
              return InkWell(
                onTap: () => controller.playEpisode(season, ep),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: saved ? 0.16 : 0.07),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.play_arrow_rounded,
                            color: saved ? Colors.white : Colors.white70),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Episode $ep',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                            if (resumable) ...[
                              const SizedBox(height: 6),
                              _ProgressLine(
                                  value: controller.progressFraction.value, track: Colors.white24),
                            ],
                          ],
                        ),
                      ),
                      if (saved)
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(resumable ? 'Resume' : 'Up next',
                              style: const TextStyle(color: Colors.white60, fontSize: 12)),
                        ),
                      if (DownloadService.supported) _EpisodeDownload(season: season, episode: ep),
                    ],
                  ),
                ),
              );
            }),
        ],
      );
    });
  }
}

class _MobileCast extends StatelessWidget {
  const _MobileCast({required this.cast});
  final List<Star> cast;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Cast',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cast.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(width: 78, child: _CastMember(star: cast[i], avatar: 58)),
          ),
        ),
      ],
    );
  }
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText(this.text);
  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: Text(
          widget.text,
          maxLines: _open ? null : 3,
          overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared
// ═════════════════════════════════════════════════════════════════════════════

/// What the primary button says and does, from the saved progress.
class _PlayInfo {
  const _PlayInfo(this.label, this.caption, this.progress, this.action);
  final String label;
  final String? caption; // e.g. "1h 12m left"
  final double? progress;
  final VoidCallback action;

  factory _PlayInfo.of(SubjectDetailController c) {
    final movie = c.isMovie;
    if (c.hasSavedProgress.value && c.lastPlayedEpisode.value != null) {
      final se = c.lastPlayedSeason.value, ep = c.lastPlayedEpisode.value;
      final where = movie ? '' : ' S$se E$ep';
      if (c.lastPlayedPosition.value == Duration.zero) {
        // Finished the previous episode: the saved one is the next, from 0:00.
        return _PlayInfo('Play$where', null, null, c.continuePlayback);
      }
      final left = c.remainingSec.value;
      return _PlayInfo(
        'Resume$where',
        left != null && left > 0
            ? '${_formatDuration(left)} left'
            : 'From ${_formatClock(c.lastPlayedPosition.value)}',
        c.progressFraction.value,
        c.continuePlayback,
      );
    }
    final first = c.resource.value?.seasons?.firstOrNull?.se ?? 0;
    return _PlayInfo(movie ? 'Play' : 'Play S$first E1', null, null, c.playFromBeginning);
  }
}

class _GenreLine extends StatelessWidget {
  const _GenreLine({required this.subject});
  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final genres = (subject.genre ?? '')
        .split(',')
        .map((g) => g.trim())
        .where((g) => g.isNotEmpty)
        .join('  ·  ');
    if (genres.isEmpty) return const SizedBox.shrink();
    return Text(
      genres.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white60,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}

/// ★ 6.1   2026 · 1h 50m · Movie · United States   [1080p] [CC]
class _MetaLine extends GetView<SubjectDetailController> {
  const _MetaLine();

  @override
  Widget build(BuildContext context) {
    final s = controller.subject.value!;
    final rating = double.tryParse(s.imdbRatingValue ?? '') ?? 0; // "0" = unrated
    final seasons = controller.resource.value?.seasons ?? const <SeasonResource>[];
    final parts = <String>[
      if ((s.releaseDate?.length ?? 0) >= 4) s.releaseDate!.substring(0, 4),
      if ((s.duration ?? 0) > 0) _formatDuration(s.duration!),
      if (controller.isMovie)
        'Movie'
      else if (seasons.length > 1)
        '${seasons.length} Seasons'
      else
        'Series',
      if ((s.countryName ?? '').isNotEmpty) s.countryName!,
    ];
    final res = controller.maxResolution;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (rating > 0)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.star_rounded, color: Color(0xFFF5C518), size: 17),
            const SizedBox(width: 3),
            Text(s.imdbRatingValue!,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        Text(parts.join('  ·  '), style: const TextStyle(color: Colors.white70, fontSize: 13)),
        if (res != null || controller.subtitleLanguages.isNotEmpty)
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (res != null) _Tag(res >= 2160 ? '4K' : '${res}p'),
            if (res != null && controller.subtitleLanguages.isNotEmpty) const SizedBox(width: 6),
            if (controller.subtitleLanguages.isNotEmpty) const _Tag('CC'),
          ]),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white38),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

class _SubtitleLine extends StatelessWidget {
  const _SubtitleLine({required this.languages});
  final List<String> languages;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'Subtitles   ', style: TextStyle(color: Colors.white38)),
        TextSpan(text: languages.join(', '), style: const TextStyle(color: Colors.white60)),
      ]),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, height: 1.5),
    );
  }
}

class _CastMember extends StatelessWidget {
  const _CastMember({required this.star, required this.avatar});
  final Star star;
  final double avatar;

  @override
  Widget build(BuildContext context) {
    final url = star.avatarUrl;
    return Column(
      children: [
        ClipOval(
          child: SizedBox(
            width: avatar,
            height: avatar,
            child: url != null && url.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: '$url?x-oss-process=image/resize%2Cw_160',
                    fit: BoxFit.cover,
                    placeholder: (_, _) => const _AvatarFallback(),
                    errorWidget: (_, _, _) => const _AvatarFallback(),
                  )
                : const _AvatarFallback(),
          ),
        ),
        const SizedBox(height: 6),
        Text(star.name ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        if ((star.character ?? '').isNotEmpty)
          Text(star.character!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ],
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Colors.white12, child: Icon(Icons.person, color: Colors.white54));
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.value, required this.track});
  final double value;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        // Always show a sliver, so a just-started title still reads as started.
        value: value.clamp(0.02, 1.0),
        minHeight: 3,
        backgroundColor: track,
        valueColor: const AlwaysStoppedAnimation(kBrandPurple),
      ),
    );
  }
}

// ─── Audio versions ──────────────────────────────────────────────────────────

/// A "… sub" version is the original audio with burned-in subtitles.
bool _isHardsub(DubOption d) => d.language.trim().toLowerCase().endsWith(' sub');

/// "Arabic dub" → "Arabic"; "ptbr dub" → "Portuguese (Brazil)".
String _dubLanguage(DubOption d) {
  var name = d.language.trim();
  final lower = name.toLowerCase();
  if (lower.endsWith(' dub') || lower.endsWith(' sub')) {
    name = name.substring(0, name.length - 4).trim();
  }
  const codes = {
    'esla': 'Spanish (Latin America)',
    'ptbr': 'Portuguese (Brazil)',
  };
  name = codes[name.toLowerCase()] ?? name;
  if (name.isEmpty) return d.original ? 'Original' : 'Unknown';
  return name[0].toUpperCase() + name.substring(1);
}

String _dubButtonLabel(DubOption? d) {
  if (d == null) return 'Audio';
  if (d.original) return 'Original audio';
  final name = _dubLanguage(d);
  return _isHardsub(d) ? '$name subtitles' : '$name audio';
}

/// Audio versions (dubs). Each one is its own MovieBox title, so picking one
/// reloads the page for it. TV: a panel sliding in from the right. Phone: a
/// bottom sheet. BACK / tapping outside closes it.
void _showAudioPicker(SubjectDetailController c) {
  final audio = c.dubs.where((d) => !_isHardsub(d)).toList();
  final burned = c.dubs.where(_isHardsub).toList();
  Get.generalDialog(
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => _AudioPanel(controller: c, audio: audio, burned: burned),
    transitionBuilder: (context, anim, _, child) {
      final tv = MediaQuery.sizeOf(context).width >= 900;
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: tv ? const Offset(0.08, 0) : const Offset(0, 0.08), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _AudioPanel extends StatelessWidget {
  const _AudioPanel({required this.controller, required this.audio, required this.burned});
  final SubjectDetailController controller;
  final List<DubOption> audio;
  final List<DubOption> burned;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final tv = size.width >= 900;
    final currentId = controller.subject.value?.subjectId;
    // Focus lands on the version being shown.
    final hasCurrent = controller.dubs.any((d) => d.subjectId == currentId);

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
          child: Text(text.toUpperCase(),
              style: const TextStyle(
                  color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        );

    Widget item(DubOption d, bool first) {
      final current = d.subjectId == currentId;
      final label = _dubLanguage(d);
      return Semantics(
        button: true,
        selected: current,
        label: '$label${d.original ? ', original' : ''}${current ? ', playing' : ''}',
        excludeSemantics: true,
        child: TvFocusable(
          autofocus: current || (!hasCurrent && first),
          onSelect: () {
            Get.back();
            controller.selectDub(d);
          },
          builder: (context, focused) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.only(bottom: 2),
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white
                  : (current ? Colors.white.withValues(alpha: 0.08) : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: focused ? _ink : Colors.white,
                        fontSize: 15,
                        fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                      )),
                ),
                if (d.original && _dubLanguage(d).toLowerCase() != 'original audio')
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text('Original',
                        style: TextStyle(color: focused ? Colors.black54 : Colors.white38, fontSize: 12)),
                  ),
                if (current)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Icon(Icons.check_rounded, size: 20, color: focused ? _ink : Colors.white),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final list = ListView(
      shrinkWrap: !tv,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      children: [
        if (burned.isNotEmpty) header('Audio'),
        for (var i = 0; i < audio.length; i++) item(audio[i], i == 0),
        if (burned.isNotEmpty) ...[
          header('Burned-in subtitles'),
          for (var i = 0; i < burned.length; i++) item(burned[i], audio.isEmpty && i == 0),
        ],
      ],
    );

    final title = Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Audio',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('${controller.dubs.length} versions of this title',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );

    if (tv) {
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: const Color(0xFF16161D),
          child: SizedBox(
            width: 340,
            height: size.height,
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, Expanded(child: list)],
              ),
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: const Color(0xFF16161D),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: size.height * 0.7, minWidth: size.width),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, Flexible(child: list)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Loading ─────────────────────────────────────────────────────────────────

class _Skeleton extends StatelessWidget {
  const _Skeleton({super.key, required this.tv});
  final bool tv;

  @override
  Widget build(BuildContext context) {
    Widget box(double w, double h, {double r = 6}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(r),
          ),
        );
    if (!tv) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          box(double.infinity, MediaQuery.sizeOf(context).width * 10 / 16, r: 0),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                box(120, 10),
                const SizedBox(height: 10),
                box(220, 26),
                const SizedBox(height: 10),
                box(160, 14),
                const SizedBox(height: 18),
                box(double.infinity, 48, r: 10),
              ],
            ),
          ),
        ],
      );
    }
    // Mirrors the TV layout: headline block, then the button row.
    return Padding(
      padding: const EdgeInsets.fromLTRB(_tvSide, _tvTop, _tvSide, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          box(130, 10),
          const SizedBox(height: 12),
          box(380, 34),
          const SizedBox(height: 14),
          box(280, 14),
          const SizedBox(height: 16),
          box(520, 12),
          const SizedBox(height: 9),
          box(500, 12),
          const SizedBox(height: 9),
          box(360, 12),
          const SizedBox(height: 24),
          Row(children: [
            box(120, 42, r: 8),
            const SizedBox(width: 10),
            box(116, 42, r: 8),
            const SizedBox(width: 10),
            box(140, 42, r: 8),
          ]),
        ],
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Landscape art for the backdrop: the stills image, else the trailer's
/// cover frame. Null when the title has neither.
String? _wideArtUrl(Subject? s) {
  final stills = s?.stills;
  if (stills?.url != null &&
      stills!.url!.isNotEmpty &&
      (stills.width == null || stills.height == null || stills.width! > stills.height!)) {
    return stills.url;
  }
  final frame = s?.trailer?.cover?.url;
  return frame != null && frame.isNotEmpty ? frame : null;
}

Color? _hexColor(String? hex) {
  if (hex == null || !hex.startsWith('#') || hex.length != 7) return null;
  final v = int.tryParse(hex.substring(1), radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// 6600 → "1h 50m"; 540 → "9m".
String _formatDuration(int seconds) {
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
  if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
  return '${m < 1 ? 1 : m}m';
}

/// 1:02:05 / 12:34
String _formatClock(Duration d) {
  final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}
