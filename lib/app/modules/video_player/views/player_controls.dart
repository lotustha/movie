part of 'video_player_view.dart';

// Netflix-style controls: title at the top; at the bottom the scrub bar with
// time remaining, transport buttons on the left and labelled actions on the
// right (Episodes · Audio & Subtitles · Quality · Next Episode).

bool _isTvLayout(BuildContext context) {
  final mq = MediaQuery.of(context);
  return mq.navigationMode == NavigationMode.directional || mq.size.width >= 900;
}

class _PlayerControlsOverlay extends StatefulWidget {
  @override
  State<_PlayerControlsOverlay> createState() => _PlayerControlsOverlayState();
}

class _PlayerControlsOverlayState extends State<_PlayerControlsOverlay> {
  final CustomVideoPlayerController controller = Get.find();

  final FocusNode _playPauseFocusNode = FocusNode();

  Worker? _showWorker;
  Worker? _panelWorker;

  @override
  void initState() {
    super.initState();
    // When the controls are shown, automatically focus the play/pause button.
    _showWorker = ever(controller.showControls, (bool isVisible) {
      if (isVisible && controller.activeSettingPanel.value == SettingPanel.None) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _playPauseFocusNode.requestFocus();
        });
      }
    });
    // When a settings panel closes, return focus to the controls so the remote
    // keeps working instead of getting stuck on the (now hidden) panel.
    _panelWorker = ever(controller.activeSettingPanel, (SettingPanel panel) {
      if (panel == SettingPanel.None && controller.showControls.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _playPauseFocusNode.requestFocus();
        });
      }
    });
  }

  @override
  void dispose() {
    _showWorker?.dispose();
    _panelWorker?.dispose();
    _playPauseFocusNode.dispose();
    super.dispose();
  }

  bool get _isSeries =>
      controller.resource.value?.seasons != null &&
      (controller.resource.value!.seasons!.firstOrNull?.se ?? 0) != 0;

  @override
  Widget build(BuildContext context) {
    final tv = _isTvLayout(context);
    final pad = tv ? 40.0 : 20.0;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB3000000), Color(0x00000000), Color(0x00000000), Color(0xE6000000)],
          stops: [0.0, 0.25, 0.55, 1.0],
        ),
      ),
      child: Column(
        children: [
          // --- Top: title ---
          Padding(
            padding: EdgeInsets.fromLTRB(tv ? pad : 8, tv ? 28 : 12, pad, 0),
            child: Row(
              children: [
                if (!tv) ...[
                  IconButton(
                    tooltip: 'Back',
                    onPressed: Get.back,
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Obx(() {
                    final title = controller.subject.value?.title ?? '';
                    final ep = _isSeries
                        ? 'S${controller.selectedSeason.value}:E${controller.selectedEpisode.value}'
                        : null;
                    return Text.rich(
                      TextSpan(children: [
                        if (ep != null)
                          TextSpan(
                              text: '$ep  ',
                              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                        TextSpan(text: title),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white, fontSize: tv ? 20 : 16, fontWeight: FontWeight.w700),
                    );
                  }),
                ),
              ],
            ),
          ),

          // --- Middle: buffering, and big transport buttons on touch screens ---
          Expanded(
            child: Center(
              child: Obx(() {
                if (controller.isBuffering.value) {
                  return const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                  );
                }
                if (tv) return const SizedBox.shrink();
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RoundControl(icon: Icons.replay_10_rounded, size: 34, onPressed: controller.rewind10Seconds),
                    const SizedBox(width: 36),
                    _RoundControl(
                      icon: controller.isPlaying.value ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 52,
                      onPressed: controller.togglePlayPause,
                    ),
                    const SizedBox(width: 36),
                    _RoundControl(icon: Icons.forward_10_rounded, size: 34, onPressed: controller.forward10Seconds),
                  ],
                );
              }),
            ),
          ),

          // --- Bottom: scrub bar + actions ---
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, tv ? 24 : 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(child: _FocusableVideoProgressIndicator()),
                    const SizedBox(width: 14),
                    GetBuilder<CustomVideoPlayerController>(builder: (_) {
                      final v = controller.videoPlayerController.value;
                      final left = v.duration - v.position;
                      return Text(
                        _formatPlayerTime(left.isNegative ? Duration.zero : left),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 10),
                Obx(() {
                  final hasAudio = controller.audioOptions.length > 1;
                  final hasSubs = controller.captionList.isNotEmpty || controller.hardsubOptions.isNotEmpty;
                  return Row(
                    children: [
                      if (tv) ...[
                        _RoundControl(
                          focusNode: _playPauseFocusNode,
                          autofocus: true,
                          icon: controller.isPlaying.value ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 28,
                          onPressed: controller.togglePlayPause,
                        ),
                        const SizedBox(width: 8),
                        _RoundControl(icon: Icons.replay_10_rounded, size: 26, onPressed: controller.rewind10Seconds),
                        const SizedBox(width: 8),
                        _RoundControl(icon: Icons.forward_10_rounded, size: 26, onPressed: controller.forward10Seconds),
                      ],
                      // A plain row (no scroll view) so D-pad RIGHT from the
                      // transport buttons reaches the actions.
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isSeries)
                                _PillAction(
                                  icon: Icons.video_library_outlined,
                                  label: 'Episodes',
                                  compact: !tv,
                                  onPressed: () => controller.openSettingPanel(SettingPanel.Episodes),
                                ),
                              if (hasAudio || hasSubs)
                                _PillAction(
                                  icon: Icons.subtitles_outlined,
                                  label: 'Audio & Subtitles',
                                  compact: !tv,
                                  onPressed: () => controller.openSettingPanel(SettingPanel.AudioSubtitles),
                                ),
                              _PillAction(
                                icon: Icons.tune_rounded,
                                label: 'Quality',
                                compact: !tv,
                                onPressed: () => controller.openSettingPanel(SettingPanel.Quality),
                              ),
                              if (controller.hasNextEpisode)
                                _PillAction(
                                  icon: Icons.skip_next_rounded,
                                  label: 'Next Episode',
                                  compact: !tv,
                                  onPressed: controller.playNextEpisode,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatPlayerTime(Duration d) {
  String two(int v) => v.toString().padLeft(2, '0');
  final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Round transport button: white icon on nothing; solid white disc with a
/// dark icon when focused (same calm focus as the rest of the TV app).
class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.onPressed,
    this.size = 28,
    this.focusNode,
    this.autofocus = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      onSelect: onPressed,
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.all(size * 0.3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: focused ? Colors.white : Colors.transparent,
        ),
        child: Icon(icon, size: size, color: focused ? Colors.black : Colors.white),
      ),
    );
  }
}

/// Labelled action (icon + text) in the bottom-right row.
class _PillAction extends StatelessWidget {
  const _PillAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool compact; // phone: icon + short label

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Semantics(
        button: true,
        label: label,
        child: TvFocusable(
          onSelect: onPressed,
          builder: (context, focused) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 8),
            decoration: BoxDecoration(
              color: focused ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: focused ? Colors.black : Colors.white),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        color: focused ? Colors.black : Colors.white,
                        fontSize: compact ? 13 : 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Audio & Subtitles sheet ───────────────────────────────────────────────────

/// Netflix-style panel over the lower part of the picture: Audio | Subtitles
/// | Text size side by side. LEFT/RIGHT moves between columns, BACK closes.
/// Changing audio keeps the playback position (see
/// [CustomVideoPlayerController.changeAudio]).
class _AudioSubtitlesSheet extends GetView<CustomVideoPlayerController> {
  const _AudioSubtitlesSheet({required this.open});
  final bool open;

  static const Map<String, double> _sizes = {
    'Small': 0.8,
    'Default': 1.0,
    'Large': 1.25,
    'Extra large': 1.5,
  };

  @override
  Widget build(BuildContext context) {
    final tv = _isTvLayout(context);
    final height = MediaQuery.of(context).size.height * (tv ? 0.62 : 0.7);
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      bottom: open ? 0 : -height - 40,
      height: height,
      child: IgnorePointer(
        ignoring: !open,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xEB0B0B0F), Color(0xF20B0B0F)],
              stops: [0.0, 0.12, 1.0],
            ),
          ),
          child: !open
              ? const SizedBox.expand()
              : FocusTraversalGroup(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(tv ? 56 : 20, 44, tv ? 56 : 20, 16),
                    child: Obx(() {
                      final audio = controller.audioOptions;
                      final hardsub = controller.hardsubOptions;
                      final current = controller.currentTrackId.value;
                      final captions = controller.captionList;
                      final selectedCaption = controller.selectedCaption.value;
                      final playingHardsub = hardsub.any((t) => t.subjectId == current);

                      final audioCol = _SheetColumn(
                        title: 'Audio',
                        children: [
                          if (audio.isEmpty)
                            const _SheetNote('Original')
                          else
                            for (final t in audio)
                              _SheetOption(
                                label: t.language,
                                trailing: t.original ? 'Original' : null,
                                selected: t.subjectId == current,
                                autofocus: t.subjectId == current,
                                onSelect: () => controller.changeAudio(t),
                              ),
                          if (audio.isNotEmpty && !audio.any((t) => t.subjectId == current))
                            const _SheetNote('Now playing a burned-in subtitle version'),
                        ],
                      );

                      final subsCol = _SheetColumn(
                        title: 'Subtitles',
                        children: [
                          _SheetOption(
                            label: 'Off',
                            selected: selectedCaption == null && !playingHardsub,
                            autofocus: audio.isEmpty && selectedCaption == null,
                            onSelect: () => controller.changeSubtitle(null),
                          ),
                          for (final c in captions)
                            _SheetOption(
                              label: c.lanName ?? c.lan ?? 'Unknown',
                              selected: selectedCaption?.id == c.id,
                              autofocus: audio.isEmpty && selectedCaption?.id == c.id,
                              onSelect: () => controller.changeSubtitle(c),
                            ),
                          if (hardsub.isNotEmpty) ...[
                            const _SheetHeading('Burned into the picture'),
                            for (final t in hardsub)
                              _SheetOption(
                                label: t.language.replaceAll(RegExp(r'\s*sub$', caseSensitive: false), ''),
                                selected: t.subjectId == current,
                                onSelect: () => controller.changeAudio(t, subtitlesOff: true),
                              ),
                          ],
                        ],
                      );

                      final sizeCol = _SheetColumn(
                        title: 'Text size',
                        children: [
                          for (final e in _sizes.entries)
                            _SheetOption(
                              label: e.key,
                              selected: (controller.subtitleScale.value - e.value).abs() < 0.001,
                              onSelect: () => controller.subtitleScale.value = e.value,
                            ),
                        ],
                      );

                      if (!tv) {
                        // Phone: two columns; text size folds under subtitles.
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: audioCol),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _SheetColumn(
                                title: 'Subtitles',
                                children: [...subsCol.children, const _SheetHeading('Text size'), ...sizeCol.children],
                              ),
                            ),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 4, child: audioCol),
                          const SizedBox(width: 32),
                          Expanded(flex: 4, child: subsCol),
                          const SizedBox(width: 32),
                          Expanded(flex: 3, child: sizeCol),
                        ],
                      );
                    }),
                  ),
                ),
        ),
      ),
    );
  }
}

class _SheetColumn extends StatelessWidget {
  const _SheetColumn({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: children,
          ),
        ),
      ],
    );
  }
}

class _SheetHeading extends StatelessWidget {
  const _SheetHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
      child: Text(text.toUpperCase(),
          style: const TextStyle(
              color: Colors.white38, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
    );
  }
}

class _SheetNote extends StatelessWidget {
  const _SheetNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 14)),
    );
  }
}

/// A choice row: a check marks the active one; focus turns it solid white.
class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.label,
    required this.selected,
    required this.onSelect,
    this.trailing,
    this.autofocus = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final String? trailing;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: TvFocusable(
        autofocus: autofocus,
        onSelect: onSelect,
        builder: (context, focused) {
          final fg = focused ? const Color(0xFF111114) : (selected ? Colors.white : Colors.white70);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: focused ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: selected ? Icon(Icons.check_rounded, size: 18, color: fg) : null,
                ),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: fg,
                          fontSize: 15,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                ),
                if (trailing != null)
                  Text(trailing!,
                      style: TextStyle(color: focused ? Colors.black45 : Colors.white38, fontSize: 11)),
              ],
            ),
          );
        },
      ),
    );
  }
}
