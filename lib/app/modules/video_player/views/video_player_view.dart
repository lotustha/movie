import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:movie/app_theme.dart';
import 'package:video_player/video_player.dart';

import '../../../model/subject_list.dart';
import '../../../widgets/tv_focusable.dart';
import '../controllers/video_player_controller.dart';

part 'player_controls.dart';
part 'player_episodes.dart';


class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({super.key});

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  final CustomVideoPlayerController controller = Get.find();

  // Holds keyboard focus whenever the controls are hidden, so the very first
  // remote press "wakes up" the UI instead of doing nothing. When controls are
  // visible, focus lives on the on-screen buttons and D-pad traversal works.
  final FocusNode _rootNode = FocusNode(debugLabel: 'playerRoot', skipTraversal: true);
  Worker? _controlsWorker;
  double _lastTapDx = 0;

  @override
  void initState() {
    super.initState();
    // Move focus to the root catcher when controls hide; the on-screen
    // play/pause button auto-focuses itself when they show.
    _controlsWorker = ever<bool>(controller.showControls, (visible) {
      if (!visible) {
        _rootNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controlsWorker?.dispose();
    _rootNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleRootKey(FocusNode node, KeyEvent event) {
    final k = event.logicalKey;
    final isBack = k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.backspace;
    // BACK acts on key-down only, but its key-up/repeat must be swallowed
    // too: an unhandled BACK key-up reaches Android as a system back, which
    // would leave the player right after closing a menu.
    if (isBack && event is! KeyDownEvent) return KeyEventResult.handled;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (controller.showControls.value) controller.resetControlsTimer();

    // Back / media keys work regardless of control visibility.
    if (k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.backspace) {
      controller.handleBackButtonPress();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.mediaPlay ||
        k == LogicalKeyboardKey.mediaPause) {
      controller.togglePlayPause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaRewind) {
      controller.rewind10Seconds();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaFastForward) {
      controller.forward10Seconds();
      return KeyEventResult.handled;
    }

    // If a settings panel or the up-next card is open, let its focused items
    // handle navigation.
    if (controller.activeSettingPanel.value != SettingPanel.None ||
        controller.upNext.value != null) {
      return KeyEventResult.ignored;
    }

    // Controls hidden: any key just wakes the UI up.
    if (!controller.showControls.value) {
      final isDpadOrSelect = k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.arrowDown ||
          k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight ||
          k == LogicalKeyboardKey.select ||
          k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.gameButtonA ||
          k == LogicalKeyboardKey.space;
      if (isDpadOrSelect) {
        controller.toggleControlsVisibility();
        return KeyEventResult.handled;
      }
    }

    // Controls visible: the focused button / progress bar handles the key
    // (this ancestor only sees what they leave unhandled).
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final double screenWidth = mq.size.width;
    // TVs navigate by D-pad; size captions bigger there. On phones/tablets a
    // landscape width can exceed 600, so key off the shortest side instead —
    // otherwise a phone gets the (too large) TV size sitting near the middle.
    final bool isTv = mq.navigationMode == NavigationMode.directional;
    final double shortestSide = mq.size.shortestSide;
    final double subtitleFontSize =
        isTv ? 30.0 : (shortestSide < 400 ? 15.0 : 18.0);
    final double subtitleBottom = isTv ? 80.0 : 44.0;
    // Above the scrub bar and buttons while the controls are showing.
    final double subtitleBottomWithControls = isTv ? 170.0 : 130.0;

    // System back (phone gesture, or a remote BACK nobody handled) follows the
    // same steps as the remote: close menu → show controls → leave.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.handleBackButtonPress();
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _rootNode,
        // Controls start visible, so the play button takes initial focus; the
        // root only grabs focus once the controls hide (see the `ever` above).
        autofocus: false,
        onKeyEvent: _handleRootKey,
        child: Obx(() {
          if (controller.errorMessage.isNotEmpty) {
            return Center(
              child: Text(
                controller.errorMessage.value,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            );
          }

          if (!controller.isPlayerReady.value) {
            final message = controller.loadingMessage.value;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(message, style: const TextStyle(color: Colors.white70, fontSize: 15)),
                  ],
                ],
              ),
            );
          }

          return GestureDetector(
            onTap: controller.toggleControlsVisibility,
            // Swipe left / right across the picture to scrub (touch devices).
            onHorizontalDragStart: (_) => controller.startDragScrub(),
            onHorizontalDragUpdate: (d) => controller.updateDragScrub(d.delta.dx, screenWidth),
            onHorizontalDragEnd: (_) => controller.endDragScrub(),
            onHorizontalDragCancel: controller.endDragScrub,
            // Swipe up / down: left half brightness, right half volume.
            onVerticalDragStart: (d) =>
                controller.startLevelDrag(rightSide: d.localPosition.dx > screenWidth / 2),
            onVerticalDragUpdate: (d) =>
                controller.updateLevelDrag(d.delta.dy, MediaQuery.sizeOf(context).height),
            onVerticalDragEnd: (_) => controller.endLevelDrag(),
            onVerticalDragCancel: controller.endLevelDrag,
            // Double-tap the left / right half to skip 10s (touch devices).
            onDoubleTapDown: (d) => _lastTapDx = d.localPosition.dx,
            onDoubleTap: () {
              if (_lastTapDx < screenWidth / 2) {
                controller.rewind10Seconds();
              } else {
                controller.forward10Seconds();
              }
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                // --- Video Player ---
                SizedBox.expand(
                  child: FittedBox(
                    fit: controller.videoFit.value,
                    child: SizedBox(
                      width: controller.videoPlayerController.value.size.width,
                      height: controller.videoPlayerController.value.size.height,
                      child: VideoPlayer(controller.videoPlayerController),
                    ),
                  ),
                ),

                // --- Brightness / volume level ---
                Obx(() {
                  final kind = controller.levelKind.value;
                  if (kind == null) return const SizedBox.shrink();
                  final v = controller.level.value;
                  final volume = kind == 'volume';
                  final icon = volume
                      ? (v == 0 ? Icons.volume_off_rounded : v < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded)
                      : (v < 0.34 ? Icons.brightness_low_rounded : v < 0.67 ? Icons.brightness_medium_rounded : Icons.brightness_high_rounded);
                  return Align(
                    // On the side that was swiped, clear of the centre controls.
                    alignment: Alignment(volume ? 0.82 : -0.82, 0),
                    child: IgnorePointer(
                      child: Container(
                        width: 54,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(27),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, color: Colors.white, size: 24),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 130,
                              width: 5,
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: v,
                                    backgroundColor: Colors.white24,
                                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text('${(v * 100).round()}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

                // --- Swipe-to-seek readout ---
                Obx(() {
                  final delta = controller.dragDeltaSec.value;
                  final target = controller.scrubTarget.value;
                  if (delta == null || target == null) return const SizedBox.shrink();
                  final sign = delta < 0 ? '−' : '+';
                  // Above the centre controls, so it never covers play/pause.
                  return Align(
                    alignment: const Alignment(0, -0.55),
                    child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$sign${_formatPlayerTime(Duration(seconds: delta.abs()))}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: [FontFeature.tabularFigures()])),
                          const SizedBox(height: 2),
                          Text(
                              '${_formatPlayerTime(target)} / ${_formatPlayerTime(controller.videoPlayerController.value.duration)}',
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontFeatures: [FontFeature.tabularFigures()])),
                        ],
                      ),
                    ),
                  ));
                }),

                // --- Subtitles ---
                Obx(() {
                  final captionText = controller.currentCaptionText.value;
                  if (controller.selectedCaption.value != null &&
                      captionText.isNotEmpty) {
                    // MODIFIED: Strip HTML tags and normalize newlines
                    // RegExp(r'<[^>]*>') matches any string starting with < and ending with >
                    final formattedCaptionText = captionText
                        .replaceAll(r'\N', '\n')
                        .replaceAll(RegExp(r'<[^>]*>'), '');

                    return Positioned(
                      bottom: controller.showControls.value
                          ? subtitleBottomWithControls
                          : subtitleBottom,
                      left: 24,
                      right: 24,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14.0, vertical: 8.0),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.0),
                            borderRadius: BorderRadius.circular(6.0),
                          ),
                          child: Text(
                            formattedCaptionText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              // Responsive base size × the user's saved multiplier.
                              fontSize:
                                  subtitleFontSize * controller.subtitleScale.value,
                              fontFamily: 'Noto Sans',
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              shadows: const [
                                Shadow(
                                  blurRadius: 5.0,
                                  color: Colors.black,
                                  offset: Offset(1.0, 1.0),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  } else {
                    return const SizedBox.shrink();
                  }
                }),

                // --- Player Controls Overlay ---
                Obx(() => AnimatedOpacity(
                  opacity: controller.showControls.value ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: AbsorbPointer(
                    absorbing: !controller.showControls.value,
                    child: _PlayerControlsOverlay(),
                  ),
                )),

                // --- Settings Panel Overlay (Episodes / Quality) ---
                Obx(() => _SettingsOverlay(
                  activePanel: controller.activeSettingPanel.value,
                )),

                // --- Audio & Subtitles sheet ---
                Obx(() => _AudioSubtitlesSheet(
                      open: controller.activeSettingPanel.value == SettingPanel.AudioSubtitles,
                    )),

                // --- Episodes panel ---
                Obx(() => _EpisodesSheet(
                      open: controller.activeSettingPanel.value == SettingPanel.Episodes,
                    )),

                // --- Up next (end of an episode) ---
                Obx(() {
                  final next = controller.upNext.value;
                  if (next == null) return const SizedBox.shrink();
                  final tv = _isTvLayout(context);
                  return Positioned(
                    right: tv ? 56 : null,
                    bottom: tv ? 56 : null,
                    child: _UpNextCard(
                      key: ValueKey(next),
                      season: next.$1,
                      episode: next.$2,
                      seconds: controller.upNextSeconds.value,
                    ),
                  );
                }),
              ],
            ),
          );
        }),
      ),
      ),
    );
  }
}

// --- Settings Overlay UI ---
class _SettingsOverlay extends GetView<CustomVideoPlayerController> {
  final SettingPanel activePanel;

  const _SettingsOverlay({required this.activePanel});

  String _getTitleForPanel(SettingPanel panel) {
    switch (panel) {
      case SettingPanel.Episodes:
        return "Episodes";
      case SettingPanel.Quality:
        return "Quality & Picture";
      case SettingPanel.Fit:
        return "Screen Fit";
      case SettingPanel.AudioSubtitles: // its own bottom sheet
      case SettingPanel.None:
        return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    // Audio & Subtitles and Episodes have their own panels.
    final bool isOpen = activePanel == SettingPanel.Quality || activePanel == SettingPanel.Fit;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      top: 0,
      bottom: 0,
      right: isOpen ? 0 : -400,
      width: 400,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: Colors.black.withOpacity(0.6),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _getTitleForPanel(activePanel),
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                      _FocusableIconButton(
                        autofocus: true, // Auto-focus close button when panel opens
                        icon: Icons.close,
                        onPressed: controller.closeSettingPanel,
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 32),
                  Expanded(
                    child: () {
                      switch (activePanel) {
                        case SettingPanel.Episodes:
                          return const SizedBox.shrink();
                        case SettingPanel.Quality:
                          return _QualitySelectionPanel();
                        case SettingPanel.Fit:
                          return _FitSelectionPanel();
                        case SettingPanel.AudioSubtitles:
                        case SettingPanel.None:
                          return const SizedBox.shrink();
                      }
                    }(),
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

class _QualitySelectionPanel extends GetView<CustomVideoPlayerController> {
  @override
  Widget build(BuildContext context) {
    // Quality, then screen fit (the separate Fit button folded in here).
    return Obx(() => ListView(
      children: [
        for (final stream in controller.streamInfoList)
          _FocusableListItem(
            text: "${stream.resolutions}p",
            isSelected: controller.selectedStream.value?.id == stream.id,
            onPressed: () => controller.changeStream(stream),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text('SCREEN FIT',
              style: TextStyle(
                  color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
        ),
        for (final e in _FitSelectionPanel._options.entries)
          _FocusableListItem(
            text: e.key,
            isSelected: controller.videoFit.value == e.value,
            onPressed: () => controller.videoFit.value = e.value,
          ),
      ],
    ));
  }
}

class _FitSelectionPanel extends GetView<CustomVideoPlayerController> {
  static const _options = <String, BoxFit>{
    "Contain (Best Fit)": BoxFit.contain,
    "Cover (Fill Screen)": BoxFit.cover,
    "Stretch": BoxFit.fill,
    "Fit Width": BoxFit.fitWidth,
    "Fit Height": BoxFit.fitHeight,
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: _options.entries
          .map((e) => Obx(() => _FocusableListItem(
                text: e.key,
                isSelected: controller.videoFit.value == e.value,
                onPressed: () => controller.videoFit.value = e.value,
              )))
          .toList(),
    );
  }
}


// --- Reusable Focusable Widgets ---

// A custom, focusable video progress indicator for TV remotes.
class _FocusableVideoProgressIndicator
    extends GetView<CustomVideoPlayerController> {
  const _FocusableVideoProgressIndicator();

  @override
  Widget build(BuildContext context) {
    return Focus(
      // LEFT/RIGHT scrub (holding keeps going, faster the longer it's held);
      // the seek happens on release. OK toggles play/pause.
      onKeyEvent: (node, event) {
        final k = event.logicalKey;
        final dir = k == LogicalKeyboardKey.arrowRight
            ? 1
            : k == LogicalKeyboardKey.arrowLeft
                ? -1
                : 0;
        if (dir != 0) {
          if (event is KeyDownEvent) controller.scrubStep(dir, repeat: false);
          if (event is KeyRepeatEvent) controller.scrubStep(dir, repeat: true);
          if (event is KeyUpEvent) controller.commitScrub();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter)) {
          controller.togglePlayPause();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (f) {
        if (!f) controller.commitScrub();
      },
      child: Builder(builder: (context) {
        final focused = Focus.of(context).hasFocus;
        return Obx(() {
          final target = controller.scrubTarget.value;
          final bar = target == null
              ? VideoProgressIndicator(
                  controller.videoPlayerController,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  colors: VideoProgressColors(
                    playedColor: kBrandPurple,
                    bufferedColor: Colors.white.withValues(alpha: 0.5),
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                  ),
                )
              : _ScrubPreview(
                  target: target,
                  duration: controller.videoPlayerController.value.duration,
                );
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            // Thicker when focused so the D-pad target is obvious.
            transform: Matrix4.diagonal3Values(1, focused ? 1.8 : 1, 1),
            transformAlignment: Alignment.center,
            child: bar,
          );
        });
      }),
    );
  }
}

/// Bar + time bubble at the scrub target while LEFT/RIGHT is being used.
class _ScrubPreview extends StatelessWidget {
  const _ScrubPreview({required this.target, required this.duration});
  final Duration target;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final frac = duration.inMilliseconds <= 0
        ? 0.0
        : (target.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 4,
        child: LayoutBuilder(builder: (context, c) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Container(color: Colors.white24),
              FractionallySizedBox(
                widthFactor: frac,
                child: Container(color: Colors.white),
              ),
              Positioned(
                left: c.maxWidth * frac - 36,
                bottom: 12,
                child: Container(
                  width: 72,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_formatPlayerTime(target),
                      style: const TextStyle(
                          color: Color(0xFF111114),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// Accepts an optional external FocusNode
class _FocusableIconButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onPressed;
  final bool autofocus;
  final FocusNode? focusNode;

  const _FocusableIconButton({
    super.key, // ADDED super.key
    required this.icon,
    this.iconSize = 36,
    required this.onPressed,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  State<_FocusableIconButton> createState() => _FocusableIconButtonState();
}

class _FocusableIconButtonState extends State<_FocusableIconButton> {
  bool _isFocused = false;
  // Use the provided focus node or create an internal one.
  late final FocusNode _focusNode;
  bool _isInternalNode = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _focusNode = FocusNode();
      _isInternalNode = true;
    } else {
      _focusNode = widget.focusNode!;
    }
    // Add listener to the focus node to update the state
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    // Only dispose the node if it was created internally.
    if (_isInternalNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      // 3. ADDED: Intercept Select/Enter to simulate a tap for TV Remotes
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: () {
          // It's good practice to ensure the node has focus before acting on it.
          if (!_focusNode.hasFocus) {
            _focusNode.requestFocus();
          }
          widget.onPressed();
        },
        borderRadius: BorderRadius.circular(50),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isFocused ? Colors.white.withOpacity(0.3) : Colors.transparent,
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}


class _FocusableListItem extends StatefulWidget {
  final String text;
  final bool isSelected;
  final VoidCallback onPressed;

  const _FocusableListItem(
      {super.key, // ADDED super.key
        required this.text, required this.isSelected, required this.onPressed});

  @override
  State<_FocusableListItem> createState() => _FocusableListItemState();
}

class _FocusableListItemState extends State<_FocusableListItem> {
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Focus(
        focusNode: _focusNode,
        // 4. ADDED: Intercept Select/Enter for list items (Episodes, Quality, etc.)
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter) {
              widget.onPressed();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: InkWell(
          onTap: () {
            if (!_focusNode.hasFocus) {
              _focusNode.requestFocus();
            }
            widget.onPressed();
          },
          borderRadius: BorderRadius.circular(8),
          // Same calm style as the Audio & Subtitles sheet: a check marks
          // the active row, focus turns it solid white.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: _isFocused ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: widget.isSelected
                      ? Icon(Icons.check_rounded,
                          size: 18, color: _isFocused ? const Color(0xFF111114) : Colors.white)
                      : null,
                ),
                Expanded(
                  child: Text(
                    widget.text,
                    style: TextStyle(
                      color: _isFocused
                          ? const Color(0xFF111114)
                          : (widget.isSelected ? Colors.white : Colors.white70),
                      fontSize: 16,
                      fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

