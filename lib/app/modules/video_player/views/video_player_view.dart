import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:movie/app/modules/Subject_Detail/views/subject_detail_view.dart';
import 'package:video_player/video_player.dart';

import '../controllers/video_player_controller.dart';

class VideoPlayerView extends GetView<CustomVideoPlayerController> {
  const VideoPlayerView({super.key});
  @override
  Widget build(BuildContext context) {
    final FocusNode keyboardListenerFocusNode = FocusNode();
    // Request focus for the listener as soon as the view is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(keyboardListenerFocusNode);
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: keyboardListenerFocusNode,
        autofocus: true,
        // MODIFIED: The key handling logic is simplified and more robust for D-Pad navigation.
        onKeyEvent: (KeyEvent event) {
          // We only care about key down events.
          if (event is! KeyDownEvent) return;

          // If controls are visible, any key press should reset the auto-hide timer.
          if (controller.showControls.value) {
            controller.resetControlsTimer();
          }

          // Define the keys used for navigation and selection.
          final isDpadKey =
              event.logicalKey == LogicalKeyboardKey.arrowUp ||
                  event.logicalKey == LogicalKeyboardKey.arrowDown ||
                  event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                  event.logicalKey == LogicalKeyboardKey.arrowRight;

          final isSelectKey = event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter;

          // If controls are hidden, any D-pad or Select press should show them.
          // This is the primary interaction to "wake up" the UI.
          if (!controller.showControls.value && (isDpadKey || isSelectKey)) {
            controller.toggleControlsVisibility();
            return; // The event is handled, so we don't process it further.
          }

          // Handle global media and back keys. These work even if controls are hidden.
          switch (event.logicalKey) {
          // --- Media Keys ---
            case LogicalKeyboardKey.mediaPlayPause:
            case LogicalKeyboardKey.mediaPlay:
            case LogicalKeyboardKey.mediaPause:
              controller.togglePlayPause();
              break;
            case LogicalKeyboardKey.mediaRewind:
              controller.rewind10Seconds();
              break;
            case LogicalKeyboardKey.mediaFastForward:
              controller.forward10Seconds();
              break;

          // --- Back Button Logic ---
            case LogicalKeyboardKey.backspace:
            case LogicalKeyboardKey.escape:
            // Use the new, improved controller method for back navigation.
              controller.handleBackButtonPress();
              break;

          // --- D-Pad & Select Logic ---
          // The default case is now empty. Once controls are visible, Flutter's
          // built-in focus system handles D-pad navigation between the Focusable
          // widgets. We don't need to manually manage it here, which is cleaner.
            default:
              break;
          }
        },
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
            return const Center(child: CircularProgressIndicator());
          }

          return GestureDetector(
            onTap: controller.toggleControlsVisibility,
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

                // --- Subtitles ---
                Obx(() {
                  final captionText = controller.currentCaptionText.value;
                  if (controller.selectedCaption.value != null &&
                      captionText.isNotEmpty) {
                    final formattedCaptionText = captionText.replaceAll(r'\N', '\n');
                    return Positioned(
                      bottom: 80,
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
                            style: const TextStyle(
                              fontSize: 32,
                              fontFamily: 'Noto Sans',
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              shadows: [
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

                // --- Settings Panel Overlay ---
                Obx(() => _SettingsOverlay(
                  activePanel: controller.activeSettingPanel.value,
                )),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// Converted to StatefulWidget to manage FocusNodes for all buttons.
class _PlayerControlsOverlay extends StatefulWidget {
  @override
  State<_PlayerControlsOverlay> createState() => _PlayerControlsOverlayState();
}

class _PlayerControlsOverlayState extends State<_PlayerControlsOverlay> {
  final CustomVideoPlayerController controller = Get.find();

  // Create FocusNodes for all interactive elements to manage D-Pad navigation.
  final FocusNode _playPauseFocusNode = FocusNode();
  final FocusNode _backButtonFocusNode = FocusNode();
  final FocusNode _rewindFocusNode = FocusNode();
  final FocusNode _forwardFocusNode = FocusNode();
  final FocusNode _episodesFocusNode = FocusNode();
  final FocusNode _subtitlesFocusNode = FocusNode();
  final FocusNode _qualityFocusNode = FocusNode();
  final FocusNode _fitFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // When the controls are shown, automatically focus the play/pause button.
    ever(controller.showControls, (bool isVisible) {
      if (isVisible && controller.activeSettingPanel.value == SettingPanel.None) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _playPauseFocusNode.requestFocus();
        });
      }
    });
  }

  @override
  void dispose() {
    // Dispose all focus nodes to prevent memory leaks.
    _playPauseFocusNode.dispose();
    _backButtonFocusNode.dispose();
    _rewindFocusNode.dispose();
    _forwardFocusNode.dispose();
    _episodesFocusNode.dispose();
    _subtitlesFocusNode.dispose();
    _qualityFocusNode.dispose();
    _fitFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withOpacity(0.6),
            Colors.transparent,
            Colors.black.withOpacity(0.8),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.4, 0.8],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // --- Top Bar ---
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                _FocusableIconButton(
                  focusNode: _backButtonFocusNode,
                  icon: Icons.arrow_back_ios_new,
                  onPressed: () => Get.back(), // Use new back logic
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.subject.value?.title ?? "Loading...",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (controller.resource.value?.seasons != null &&
                          controller.resource.value?.seasons!.first.maxEp != 0)
                        Obx(() => Text(
                          "Season ${controller.selectedSeason.value} - Episode ${controller.selectedEpisode.value}",
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 14),
                        )),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- Middle Controls ---
          Obx(() {
            return controller.isBuffering.value
                ? const Center(child: CircularProgressIndicator())
                : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _FocusableIconButton(
                  focusNode: _rewindFocusNode,
                  icon: Icons.replay_10,
                  onPressed: controller.rewind10Seconds,
                ),
                const SizedBox(width: 48),
                Obx(() => _FocusableIconButton(
                  focusNode: _playPauseFocusNode,
                  autofocus: true,
                  icon: controller.isPlaying.value
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  iconSize: 80,
                  onPressed: controller.togglePlayPause,
                )),
                const SizedBox(width: 48),
                _FocusableIconButton(
                  focusNode: _forwardFocusNode,
                  icon: Icons.forward_10,
                  onPressed: controller.forward10Seconds,
                ),
              ],
            );
          }),

          // --- Bottom Bar ---
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Using the custom focusable progress indicator
                      _FocusableVideoProgressIndicator(),
                      GetBuilder<CustomVideoPlayerController>(builder: (_) {
                        final position = controller.videoPlayerController.value.position;
                        final duration = controller.videoPlayerController.value.duration;
                        return Text(
                          "${_formatDuration(position)} / ${_formatDuration(duration)}",
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        );
                      }),
                    ],
                  ),
                ),
                if (controller.resource.value?.seasons != null &&
                    controller.resource.value?.seasons!.first.maxEp != 0)
                  const SizedBox(width: 24),
                if (controller.resource.value?.seasons != null &&
                    controller.resource.value?.seasons!.first.maxEp != 0)
                  _FocusableIconButton(
                    focusNode: _episodesFocusNode,
                    icon: Icons.video_library_outlined,
                    onPressed: () =>
                        controller.openSettingPanel(SettingPanel.Episodes),
                  ),
                if (controller.captionList.isNotEmpty) const SizedBox(width: 12),
                if (controller.captionList.isNotEmpty)
                  _FocusableIconButton(
                    focusNode: _subtitlesFocusNode,
                    icon: Icons.subtitles_outlined,
                    onPressed: () =>
                        controller.openSettingPanel(SettingPanel.Subtitles),
                  ),
                const SizedBox(width: 12),
                _FocusableIconButton(
                  focusNode: _qualityFocusNode,
                  icon: Icons.high_quality_outlined,
                  onPressed: () =>
                      controller.openSettingPanel(SettingPanel.Quality),
                ),
                const SizedBox(width: 12),
                _FocusableIconButton(
                  focusNode: _fitFocusNode,
                  icon: Icons.fit_screen_outlined,
                  onPressed: () => controller.openSettingPanel(SettingPanel.Fit),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final parts = d.toString().split('.').first.split(':');
    if (d.inHours > 0) {
      return "${parts[0]}:${parts[1]}:${parts[2]}";
    }
    return "${parts[1]}:${parts[2]}";
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
      case SettingPanel.Subtitles:
        return "Subtitles";
      case SettingPanel.Quality:
        return "Video Quality";
      case SettingPanel.Fit:
        return "Screen Fit";
      case SettingPanel.None:
        return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isOpen = activePanel != SettingPanel.None;

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
                          return _EpisodeSelectionPanel();
                        case SettingPanel.Subtitles:
                          return _SubtitleSelectionPanel();
                        case SettingPanel.Quality:
                          return _QualitySelectionPanel();
                        case SettingPanel.Fit:
                          return _FitSelectionPanel();
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

// --- Specific Setting Panels (No changes needed) ---
class _EpisodeSelectionPanel extends GetView<CustomVideoPlayerController> {
  @override
  Widget build(BuildContext context) {
    final currentSeason = controller.resource.value?.seasons?.firstWhereOrNull((s) => s.se == controller.selectedSeason.value);
    final episodeCount = currentSeason?.maxEp ?? 0;

    return Column(
      children: [
        _FocusableDropdown<int>(
          title: "Season",
          value: controller.selectedSeason.value,
          items: controller.resource.value?.seasons?.map((s) => DropdownMenuItem<int>(
            value: s.se,
            child: Text("Season ${s.se}",
                style: const TextStyle(color: Colors.white)),
          ))
              .toList() ??
              [],
          onChanged: (season) {
            if (season != null) controller.changeSeason(season);
          },
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            itemCount: episodeCount,
            itemBuilder: (context, index) {
              final episodeNumber = index + 1;
              return Obx(() => _FocusableListItem(
                text: "Episode $episodeNumber",
                isSelected: controller.selectedEpisode.value == episodeNumber,
                onPressed: () => controller.changeEpisode(episodeNumber),
              ));
            },
          ),
        ),
      ],
    );
  }
}

class _SubtitleSelectionPanel extends GetView<CustomVideoPlayerController> {
  @override
  Widget build(BuildContext context) {
    return Obx(() => controller.captionList.isEmpty
        ? const Center(
        child: Text("No subtitles available.",
            style: TextStyle(color: Colors.white70)))
        : ListView.builder(
      itemCount: controller.captionList.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _FocusableListItem(
            text: "Off",
            isSelected: controller.selectedCaption.value == null,
            onPressed: () => controller.changeSubtitle(null),
          );
        }
        final caption = controller.captionList[index - 1];
        return Obx(() {
          return _FocusableListItem(
            text: caption.lanName ?? "Unknown",
            isSelected: controller.selectedCaption.value?.id == caption.id,
            onPressed: () => controller.changeSubtitle(caption),
          );
        });
      },
    ));
  }
}

class _QualitySelectionPanel extends GetView<CustomVideoPlayerController> {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: controller.streamInfoList.length,
      itemBuilder: (context, index) {
        final stream = controller.streamInfoList[index];
        return Obx(() => _FocusableListItem(
          text: "${stream.resolutions}p",
          isSelected: controller.selectedStream.value?.id == stream.id,
          onPressed: () => controller.changeStream(stream),
        ));
      },
    );
  }
}

class _FitSelectionPanel extends GetView<CustomVideoPlayerController> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FocusableListItem(
          text: "Contain (Best Fit)",
          isSelected: controller.videoFit.value == BoxFit.contain,
          onPressed: () => controller.videoFit.value = BoxFit.contain,
        ),
        _FocusableListItem(
          text: "Cover (Fill Screen)",
          isSelected: controller.videoFit.value == BoxFit.cover,
          onPressed: () => controller.videoFit.value = BoxFit.cover,
        ),
      ],
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
    return GetBuilder<CustomVideoPlayerController>(
      builder: (controller) {
        return Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                controller.forward10Seconds();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                controller.rewind10Seconds();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Builder(
            builder: (context) {
              final isFocused = Focus.of(context).hasFocus;
              return TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 1.0, end: isFocused ? 1.5 : 1.0),
                duration: const Duration(milliseconds: 200),
                builder: (context, scale, child) {
                  return Transform.scale(
                    scale: scale,
                    child: VideoProgressIndicator(
                      controller.videoPlayerController,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      colors: VideoProgressColors(
                        playedColor: kAccentColor,
                        bufferedColor: Colors.white.withOpacity(0.5),
                        backgroundColor: Colors.white.withOpacity(0.2),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
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
      {required this.text, required this.isSelected, required this.onPressed});

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
        child: InkWell(
          onTap: () {
            if (!_focusNode.hasFocus) {
              _focusNode.requestFocus();
            }
            widget.onPressed();
          },
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: widget.isSelected
                    ? kAccentColor
                    : (_isFocused
                    ? Colors.white.withOpacity(0.2)
                    : Colors.white.withOpacity(0.1)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isFocused ? Colors.white : Colors.transparent,
                  width: 2,
                )
            ),
            child: Text(
              widget.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusableDropdown<T> extends StatefulWidget {
  final String title;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _FocusableDropdown({
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  State<_FocusableDropdown<T>> createState() => _FocusableDropdownState<T>();
}

class _FocusableDropdownState<T> extends State<_FocusableDropdown<T>> {
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
    return Focus(
      focusNode: _focusNode,
      child: FormField<T>(
        builder: (FormFieldState<T> state) {
          return InputDecorator(
            decoration: InputDecoration(
              labelText: widget.title,
              labelStyle:
              TextStyle(color: _isFocused ? Colors.white : Colors.white70),
              border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.5))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white, width: 2)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: widget.value,
                isDense: true,
                onChanged: widget.onChanged,
                items: widget.items,
                dropdownColor: const Color(0xFF1E1E1E),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              ),
            ),
          );
        },
      ),
    );
  }
}
