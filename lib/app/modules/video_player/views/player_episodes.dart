part of 'video_player_view.dart';

// ─── Episodes panel ────────────────────────────────────────────────────────────

/// Seasons and episodes, sliding in from the right. Season chips only change
/// which season is listed; OK on an episode plays it. The switch at the
/// bottom is the saved "play the next episode automatically" preference.
class _EpisodesSheet extends StatefulWidget {
  const _EpisodesSheet({required this.open});
  final bool open;

  @override
  State<_EpisodesSheet> createState() => _EpisodesSheetState();
}

class _EpisodesSheetState extends State<_EpisodesSheet> {
  final CustomVideoPlayerController c = Get.find();
  int? _browse; // season being listed; null = the playing one

  // UP from the first episode lands on the listed season's chip and DOWN from
  // a chip returns to the list (geometric traversal picked whichever chip was
  // nearest, often the wrong season).
  final Map<int, FocusNode> _chipNodes = {};
  final Map<int, FocusNode> _rowNodes = {};
  FocusNode _chipNode(int season) => _chipNodes.putIfAbsent(season, () => FocusNode());
  FocusNode _rowNode(int index) => _rowNodes.putIfAbsent(index, () => FocusNode());

  @override
  void dispose() {
    for (final n in [..._chipNodes.values, ..._rowNodes.values]) {
      n.dispose();
    }
    super.dispose();
  }

  bool _isKey(KeyEvent e, LogicalKeyboardKey k) =>
      (e is KeyDownEvent || e is KeyRepeatEvent) && e.logicalKey == k;

  @override
  void didUpdateWidget(covariant _EpisodesSheet old) {
    super.didUpdateWidget(old);
    if (widget.open && !old.open) _browse = null; // reopen on the playing season
  }

  @override
  Widget build(BuildContext context) {
    final tv = _isTvLayout(context);
    final screenW = MediaQuery.of(context).size.width;
    final width = tv ? 440.0 : (screenW * 0.9).clamp(0.0, 420.0);
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      top: 0,
      bottom: 0,
      right: widget.open ? 0 : -width - 40,
      width: width,
      child: IgnorePointer(
        ignoring: !widget.open,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x000B0B0F), Color(0xEB0B0B0F), Color(0xF50B0B0F)],
              stops: [0.0, 0.1, 1.0],
            ),
          ),
          child: !widget.open
              ? const SizedBox.expand()
              : SafeArea(
                  left: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(tv ? 44 : 28, tv ? 32 : 16, tv ? 36 : 16, 16),
                    child: FocusTraversalGroup(child: Obx(_content)),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _content() {
    final seasons = [
      for (final s in c.resource.value?.seasons ?? const <SeasonResource>[])
        if ((s.se ?? 0) > 0) s.se!,
    ];
    final playingSeason = c.selectedSeason.value;
    final season = _browse ?? playingSeason;
    final episodes = c.episodesFor(season);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Episodes',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(c.subject.value?.title ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
        if (seasons.length > 1) ...[
          const SizedBox(height: 14),
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, e) {
              if (!_isKey(e, LogicalKeyboardKey.arrowDown)) return KeyEventResult.ignored;
              // Into the list: the playing episode on its season, else the first.
              final playingIdx =
                  season == playingSeason ? episodes.indexOf(c.selectedEpisode.value) : -1;
              var node = _rowNodes[playingIdx < 0 ? 0 : playingIdx];
              // Not built (scrolled away): take the first row instead.
              if (node?.context == null) node = _rowNodes[0];
              if (node?.context == null) return KeyEventResult.ignored;
              node!.requestFocus();
              return KeyEventResult.handled;
            },
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: seasons.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _SeasonChip(
                  focusNode: _chipNode(seasons[i]),
                  label: 'Season ${seasons[i]}',
                  selected: seasons[i] == season,
                  onSelect: () => setState(() => _browse = seasons[i]),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, e) {
              if (!_isKey(e, LogicalKeyboardKey.arrowUp)) return KeyEventResult.ignored;
              if (_rowNodes[0]?.hasFocus != true) return KeyEventResult.ignored;
              final chip = _chipNodes[season];
              if (chip?.context == null) return KeyEventResult.ignored;
              chip!.requestFocus();
              return KeyEventResult.handled;
            },
            child: ListView.builder(
              itemCount: episodes.length,
              itemBuilder: (_, i) {
                final ep = episodes[i];
                final playing = season == playingSeason && ep == c.selectedEpisode.value;
                return _EpisodeRow(
                  focusNode: _rowNode(i),
                  episode: ep,
                  season: season,
                  playing: playing,
                  // Land on the playing episode when the panel opens.
                  autofocus: playing,
                  onSelect: () => c.playEpisode(season, ep),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        _AutoPlaySwitch(value: c.autoPlayNext.value, onChanged: c.setAutoPlayNext),
      ],
    );
  }
}

class _SeasonChip extends StatelessWidget {
  const _SeasonChip({
    required this.label,
    required this.selected,
    required this.onSelect,
    this.focusNode,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      onSelect: onSelect,
      onFocusChange: (f) {
        if (f) {
          Scrollable.ensureVisible(context,
              alignment: 0.5, duration: const Duration(milliseconds: 150));
        }
      },
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: focused ? Colors.white : Colors.white.withValues(alpha: selected ? 0.2 : 0.08),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(label,
            style: TextStyle(
              color: focused ? const Color(0xFF111114) : (selected ? Colors.white : Colors.white70),
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            )),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.season,
    required this.playing,
    required this.onSelect,
    this.autofocus = false,
    this.focusNode,
  });

  final FocusNode? focusNode;
  final int episode;
  final int season;
  final bool playing;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Episode $episode${playing ? ', now playing' : ''}',
      child: TvFocusable(
        focusNode: focusNode,
        autofocus: autofocus,
        onSelect: onSelect,
        onFocusChange: (f) {
          if (f) {
            Scrollable.ensureVisible(context,
                alignment: 0.4, duration: const Duration(milliseconds: 150));
          }
        },
        builder: (context, focused) {
          final dark = const Color(0xFF111114);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: focused ? Colors.white : Colors.white.withValues(alpha: playing ? 0.12 : 0.0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text('$episode',
                      style: TextStyle(
                        color: focused ? Colors.black54 : Colors.white38,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      )),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Episode $episode',
                          style: TextStyle(
                              color: focused ? dark : Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      if (DownloadService.supported)
                        Obx(() {
                          DownloadService.to.items.length;
                          final it = DownloadService.to.itemFor(
                              Get.find<CustomVideoPlayerController>().subject.value?.subjectId, season, episode);
                          if (it?.state != DownloadState.complete) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(it!.watched ? 'Downloaded · watched' : 'Downloaded · plays offline',
                                style: TextStyle(
                                    color: focused ? Colors.black54 : const Color(0xFF3DDC84), fontSize: 11)),
                          );
                        }),
                    ],
                  ),
                ),
                if (playing) ...[
                  Icon(Icons.equalizer_rounded, size: 16, color: focused ? dark : kBrandPurple),
                  const SizedBox(width: 4),
                  Text('Now playing',
                      style: TextStyle(color: focused ? Colors.black54 : Colors.white60, fontSize: 11)),
                ] else
                  Icon(Icons.play_arrow_rounded, size: 20, color: focused ? dark : Colors.white24),
                // Phones only: TVs stream (DownloadService.supported), and a
                // D-pad row has one action (play).
                if (DownloadService.supported && !_isTvLayout(context))
                  _EpisodeDownloadButton(season: season, episode: episode, dark: focused),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Netflix's download control: an arrow, a radial progress ring while it
/// downloads (tap to pause / resume), a check when it's on the phone.
class _EpisodeDownloadButton extends StatelessWidget {
  const _EpisodeDownloadButton({required this.season, required this.episode, this.dark = false});
  final int season;
  final int episode;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<CustomVideoPlayerController>();
    final svc = DownloadService.to;
    return Obx(() {
      svc.items.length;
      final item = svc.itemFor(c.subject.value?.subjectId, season, episode);
      final state = item?.state;
      final fg = dark ? const Color(0xFF111114) : Colors.white;
      Widget face;
      String tip;
      VoidCallback? onTap;
      switch (state) {
        case null:
          face = Icon(Icons.download_rounded, color: fg.withValues(alpha: 0.85), size: 22);
          tip = 'Download episode $episode';
          onTap = () => c.downloadEpisode(season, episode);
        case DownloadState.complete:
          face = Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(color: Color(0xFF3DDC84), shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: Colors.black, size: 18),
          );
          tip = 'Downloaded';
          onTap = null;
        case DownloadState.failed:
          face = const Icon(Icons.error_outline_rounded, color: kBrandRed, size: 24);
          tip = 'Retry download';
          onTap = () => c.downloadEpisode(season, episode);
        case DownloadState.running:
        case DownloadState.paused:
        case DownloadState.queued:
          final paused = state == DownloadState.paused;
          face = SizedBox(
            width: 28,
            height: 28,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: state == DownloadState.queued ? null : item!.progress.clamp(0.0, 1.0),
                  strokeWidth: 2.6,
                  color: kBrandPurple,
                  backgroundColor: fg.withValues(alpha: 0.18),
                ),
                Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 14, color: fg),
              ],
            ),
          );
          tip = paused ? 'Resume download' : 'Pause download';
          onTap = () => paused ? svc.resume(item!) : svc.pause(item!);
      }
      return IconButton(
        tooltip: tip,
        onPressed: onTap,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: face,
      );
    });
  }
}

class _AutoPlaySwitch extends StatelessWidget {
  const _AutoPlaySwitch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const dark = Color(0xFF111114);
    return Semantics(
      toggled: value,
      label: 'Autoplay next episode',
      child: TvFocusable(
        onSelect: () => onChanged(!value),
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: focused ? Colors.white : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.skip_next_rounded, size: 20, color: focused ? dark : Colors.white70),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Autoplay next episode',
                    style: TextStyle(
                        color: focused ? dark : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
              // A small track + knob; ON uses the brand purple.
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 38,
                height: 22,
                padding: const EdgeInsets.all(3),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: value ? kBrandPurple : (focused ? Colors.black26 : Colors.white24),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Up next ───────────────────────────────────────────────────────────────────

/// Shown when an episode ends: a big ring counting down from
/// [CustomVideoPlayerController.upNextCountdown] seconds, then the next
/// episode starts. "Play now" skips the wait; "Cancel" (or BACK) stays.
/// With autoplay off the ring is full and waits for OK.
class _UpNextCard extends StatefulWidget {
  const _UpNextCard({super.key, required this.season, required this.episode, required this.seconds});
  final int season;
  final int episode;
  final int seconds; // 0 = autoplay off

  @override
  State<_UpNextCard> createState() => _UpNextCardState();
}

class _UpNextCardState extends State<_UpNextCard> {
  final CustomVideoPlayerController c = Get.find();
  final FocusNode _playNow = FocusNode(debugLabel: 'upNextPlay');

  @override
  void initState() {
    super.initState();
    // Take focus from the player's key catcher so OK / arrows reach the card.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playNow.requestFocus();
    });
  }

  @override
  void dispose() {
    _playNow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tv = _isTvLayout(context);
    final ring = tv ? 132.0 : 104.0;
    final counting = widget.seconds > 0;
    return Container(
      padding: EdgeInsets.all(tv ? 28 : 20),
      decoration: BoxDecoration(
        color: const Color(0xE60B0B0F),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: ring,
            height: ring,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  // Drains smoothly over the whole countdown.
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey('${widget.season}-${widget.episode}-$counting'),
                    tween: Tween(begin: 1.0, end: counting ? 0.0 : 1.0),
                    duration: Duration(
                        seconds: counting ? CustomVideoPlayerController.upNextCountdown : 0),
                    builder: (_, v, _) => CircularProgressIndicator(
                      value: v,
                      strokeWidth: tv ? 7 : 6,
                      strokeCap: StrokeCap.round,
                      backgroundColor: Colors.white12,
                      color: kBrandPurple,
                    ),
                  ),
                ),
                if (counting)
                  Text('${widget.seconds}',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: tv ? 56 : 44,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()]))
                else
                  Icon(Icons.play_arrow_rounded, size: tv ? 64 : 52, color: Colors.white),
              ],
            ),
          ),
          SizedBox(height: tv ? 18 : 14),
          const Text('NEXT EPISODE',
              style: TextStyle(
                  color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Text('Season ${widget.season} · Episode ${widget.episode}',
              style: TextStyle(color: Colors.white, fontSize: tv ? 18 : 16, fontWeight: FontWeight.w700)),
          SizedBox(height: tv ? 18 : 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CardButton(
                focusNode: _playNow,
                icon: Icons.play_arrow_rounded,
                label: 'Play now',
                onSelect: c.playUpNextNow,
              ),
              const SizedBox(width: 10),
              _CardButton(
                icon: Icons.close_rounded,
                label: 'Cancel',
                onSelect: () {
                  c.cancelUpNext();
                  c.showControls.value = true;
                  c.resetControlsTimer();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({required this.icon, required this.label, required this.onSelect, this.focusNode});
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    const dark = Color(0xFF111114);
    return Semantics(
      button: true,
      label: label,
      child: TvFocusable(
        focusNode: focusNode,
        onSelect: onSelect,
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: focused ? Colors.white : Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: focused ? dark : Colors.white),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: focused ? dark : Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
