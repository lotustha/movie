import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
// NEW: Import GetStorage for local data persistence.
import 'package:get_storage/get_storage.dart';
import 'package:movie/app/data/api_provider.dart';
import 'package:movie/app/model/subject_list.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../model/CaptionApiResponse.dart';
import '../../../model/StreamInfo.dart';

// Enum to manage which settings panel is currently visible
enum SettingPanel { None, Episodes, Subtitles, Quality, Fit }

class CustomVideoPlayerController extends GetxController {
  // --- Core Player State ---
  late VideoPlayerController videoPlayerController;
  final RxBool isPlayerReady = false.obs;
  final RxBool isBuffering = false.obs;
  final RxString errorMessage = ''.obs;
  final RxBool isPlaying = false.obs;
  final RxString currentCaptionText = ''.obs;

  // --- UI State ---
  final RxBool showControls = true.obs;
  final Rx<SettingPanel> activeSettingPanel = SettingPanel.None.obs;
  final Rx<BoxFit> videoFit = BoxFit.contain.obs;
  Timer? _controlsVisibilityTimer;
  bool _isHandlingVideoEnd = false;

  // --- Content Data ---
  final Rx<Subject?> subject = Rx<Subject?>(null);
  final Rx<Resource?> resource = Rx<Resource?>(null);
  final RxList<StreamInfo> streamInfoList = <StreamInfo>[].obs;
  final Rx<StreamInfo?> selectedStream = Rx<StreamInfo?>(null);
  final RxInt selectedSeason = 1.obs;
  final RxInt selectedEpisode = 1.obs;

  // --- Subtitle State ---
  final ApiProvider apiProvider = Get.find<ApiProvider>();
  final RxList<Captions> captionList = <Captions>[].obs;
  final Rx<Captions?> selectedCaption = Rx<Captions?>(null);

  DateTime? _lastBackPressedTime;

  // NEW: For saving playback progress.
  final _storage = GetStorage();
  Timer? _progressSaveTimer;
  Duration _startAt = Duration.zero;

  @override
  void onInit() {
    super.onInit();
    WakelockPlus.enable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    final arguments = Get.arguments as Map<String, dynamic>;
    subject.value = arguments['subject'];
    resource.value = arguments['resource'];
    streamInfoList.value = arguments['streams'];
    selectedSeason.value = arguments['season'];
    selectedEpisode.value = arguments['episode'];
    // NEW: Receive the starting position for "Continue Watching".
    _startAt = arguments['position'] as Duration? ?? Duration.zero;

    if (streamInfoList.isNotEmpty) {
      _sortStreamsByQuality();
      _initializePlayerWithFallback(startAt: _startAt);
    } else {
      errorMessage.value = "No video streams were found for this content.";
    }
  }

  /// MODIFIED: This method now implements the double-press-to-exit logic.
  void handleBackButtonPress() {
    if (activeSettingPanel.value != SettingPanel.None) {
      closeSettingPanel();
      return;
    }

    final now = DateTime.now();
    if (_lastBackPressedTime != null &&
        now.difference(_lastBackPressedTime!) < const Duration(milliseconds: 500)) {
      Get.back();
      _lastBackPressedTime = null;
    } else {
      toggleControlsVisibility();
      _lastBackPressedTime = now;
      Get.showSnackbar(
        GetSnackBar(
          messageText: const Text(
            'Press back again to close',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.black.withOpacity(0.7),
          margin: const EdgeInsets.only(bottom: 100, left: 300, right: 300),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          borderRadius: 12,
          duration: const Duration(seconds: 2),
          animationDuration: const Duration(milliseconds: 300),
          isDismissible: false,
        ),
      );
    }
  }

  /// MODIFIED: This method now seeks to the provided start time and
  /// starts a timer to periodically save progress.
  Future<void> _initializePlayerWithFallback({
    Duration startAt = Duration.zero,
  }) async {
    _isHandlingVideoEnd = false;
    isPlayerReady.value = false;
    errorMessage.value = '';

    final List<StreamInfo> streamsToTry = [];
    if (selectedStream.value != null) {
      streamsToTry.add(selectedStream.value!);
      streamsToTry.addAll(
          streamInfoList.where((s) => s.id != selectedStream.value!.id));
    } else {
      streamsToTry.addAll(streamInfoList);
    }

    for (final stream in streamsToTry) {
      try {
        selectedStream.value = stream;

        videoPlayerController = VideoPlayerController.networkUrl(
          Uri.parse(stream.url!),
          httpHeaders: {
            'Referer': 'https://fmoviesunblocked.net/',
            'Origin': 'https://fmoviesunblocked.net',
            'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
          },
        );

        await videoPlayerController.initialize();
        if (startAt != Duration.zero) {
          await videoPlayerController.seekTo(startAt);
        }
        await videoPlayerController.play();

        isPlayerReady.value = true;
        isPlaying.value = true;

        videoPlayerController.addListener(() {
          isPlaying.value = videoPlayerController.value.isPlaying;
          isBuffering.value = videoPlayerController.value.isBuffering;
          currentCaptionText.value =
              videoPlayerController.value.caption.text;

          if (isPlayerReady.value && !_isHandlingVideoEnd) {
            final position = videoPlayerController.value.position;
            final duration = videoPlayerController.value.duration;
            if (duration > Duration.zero && position >= duration) {
              _handleNextEpisode();
            }
          }
          update();
        });

        resetControlsTimer();
        if (captionList.isEmpty) {
          _fetchSubtitles();
        }
        // NEW: Start saving progress periodically after successful initialization.
        _startPeriodicSave();
        return;
      } catch (e) {
        if (kDebugMode) {
          print("Failed to load stream '${stream.resolutions}p'. Error: $e");
        }
      }
    }

    errorMessage.value = "All available video sources failed to load.";
  }
  // --- Progress Saving ---

  // NEW: Saves the current playback progress to local storage.
  void _saveProgress() {
    if (isPlayerReady.value && subject.value?.subjectId != null) {
      final position = videoPlayerController.value.position;
      // Only save if the video is past the first 5 seconds and not at the very end.
      if (position > const Duration(seconds: 5) &&
          position < videoPlayerController.value.duration - const Duration(seconds: 10)) {
        final progressData = {
          'season': selectedSeason.value,
          'episode': selectedEpisode.value,
          'position': position.inSeconds,
        };
        _storage.write('progress_${subject.value!.subjectId}', progressData);
      }
    }
  }

  // NEW: Sets up a timer that saves progress every 15 seconds.
  void _startPeriodicSave() {
    _progressSaveTimer?.cancel(); // Cancel any existing timer to avoid duplicates.
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (isPlaying.value) {
        _saveProgress();
      }
    });
  }


  Future<void> _fetchSubtitles() async {
    if (selectedStream.value == null || subject.value == null) return;
    try {
      final dynamic responseData = await apiProvider.fetchSubtitlesForStream(
        streamId: selectedStream.value!.id!,
        subjectId: subject.value!.subjectId!,
      );

      final captionApiResponse = CaptionApiResponse.fromJson(responseData);
      final List<Captions>? captions = captionApiResponse.data?.captions;

      if (captions != null && captions.isNotEmpty) {
        captionList.value = captions;

        if (selectedCaption.value == null) {
          final englishCaption = captions.firstWhereOrNull(
                (c) => c.lan == 'en' || c.lanName?.toLowerCase() == 'english',
          );
          if (englishCaption != null) {
            await changeSubtitle(
              englishCaption,
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("Could not fetch subtitles: $e");
      }
    }
  }

  // --- UI Control Methods ---

  void toggleControlsVisibility() {
    if (activeSettingPanel.value != SettingPanel.None) {
      closeSettingPanel();
      return;
    }
    showControls.value = !showControls.value;
    if (showControls.value) {
      resetControlsTimer();
    } else {
      _controlsVisibilityTimer?.cancel();
    }
  }

  void resetControlsTimer() {
    _controlsVisibilityTimer?.cancel();
    if (activeSettingPanel.value == SettingPanel.None) {
      _controlsVisibilityTimer = Timer(const Duration(seconds: 5), () {
        if (isPlaying.value) showControls.value = false;
      });
    }
  }

  void openSettingPanel(SettingPanel panel) {
    if (activeSettingPanel.value == panel) {
      closeSettingPanel();
    } else {
      activeSettingPanel.value = panel;
      showControls.value = true;
      _controlsVisibilityTimer?.cancel();
    }
  }

  void closeSettingPanel() {
    activeSettingPanel.value = SettingPanel.None;
    resetControlsTimer();
  }

  // --- Playback Control Methods ---

  void togglePlayPause() {
    if (!isPlayerReady.value) return;
    isPlaying.value
        ? videoPlayerController.pause()
        : videoPlayerController.play();
    resetControlsTimer();
  }

  void rewind10Seconds() {
    if (!isPlayerReady.value) return;
    final newPosition =
        videoPlayerController.value.position - const Duration(seconds: 10);
    videoPlayerController.seekTo(
      newPosition > Duration.zero ? newPosition : Duration.zero,
    );
    resetControlsTimer();
  }

  void forward10Seconds() {
    if (!isPlayerReady.value) return;
    final currentPosition = videoPlayerController.value.position;
    final duration = videoPlayerController.value.duration;
    final newPosition = currentPosition + const Duration(seconds: 10);
    videoPlayerController.seekTo(
      newPosition < duration ? newPosition : duration,
    );
    resetControlsTimer();
  }

  // --- Content Switching Methods ---

  void changeSeason(int season) {
    if (selectedSeason.value == season) return;
    _saveProgress(); // Save progress of the current episode before changing.
    selectedSeason.value = season;
    changeEpisode(1);
  }

  Future<void> changeEpisode(int episode) async {
    if (selectedEpisode.value == episode) return;
    _saveProgress(); // Save progress of the current episode before changing.
    selectedEpisode.value = episode;
    final response = await apiProvider.fetchPlaybackInfoWithCookieManager(
      subject: subject.value!,
      season: '${selectedSeason.value}',
      episode: '$episode',
    );

    if (response != null &&
        response['data'] != null &&
        response['data']['streams'] is List) {
      final streamsData = response['data']['streams'] as List;

      if (streamsData.isNotEmpty) {
        streamInfoList.value = streamsData
            .map(
              (streamJson) =>
              StreamInfo.fromJson(streamJson as Map<String, dynamic>),
        )
            .toList();
      }
    }
    await _reloadPlayer(
      newStream: streamInfoList.first,
      startFromBeginning: true,
    );
  }

  Future<void> changeStream(StreamInfo newStream) async {
    if (!isPlayerReady.value || newStream.id == selectedStream.value?.id) {
      return;
    }
    await _reloadPlayer(newStream: newStream);
  }

  Future<void> changeSubtitle(Captions? newCaption) async {
    if (selectedCaption.value?.id == newCaption?.id) return;
    if (!isPlayerReady.value) return;

    try {
      final Future<ClosedCaptionFile>? newCaptionFile = _buildClosedCaptionFile(
        fromCaption: newCaption,
      );
      await videoPlayerController.setClosedCaptionFile(newCaptionFile);
      selectedCaption.value = newCaption;
    } catch (e) {
      if (kDebugMode) {
        print("Error setting new subtitle file: $e");
      }
    }
  }

  Future<void> _reloadPlayer({
    StreamInfo? newStream,
    bool startFromBeginning = false,
  }) async {
    if (!isPlayerReady.value) return;
    final currentPosition = startFromBeginning
        ? Duration.zero
        : videoPlayerController.value.position;
    await videoPlayerController.pause();
    isPlayerReady.value = false;

    if (newStream != null) {
      selectedStream.value = newStream;
      selectedCaption.value = null;
      captionList.clear();
    }

    await videoPlayerController.dispose();
    await _initializePlayerWithFallback(startAt: currentPosition);
  }

  Future<void> _handleNextEpisode() async {
    if (_isHandlingVideoEnd) return;
    _isHandlingVideoEnd = true;

    if (kDebugMode) print("Video finished, attempting to load next episode...");

    final currentSeasonInfo = resource.value?.seasons?.firstWhereOrNull(
          (s) => s.se == selectedSeason.value,
    );

    if (currentSeasonInfo == null) {
      if (kDebugMode) {
        print("Could not find current season info to play next episode.");
      }
      _isHandlingVideoEnd = false;
      return;
    }

    final maxEpisodes = currentSeasonInfo.maxEp ?? 0;
    final nextEpisodeNumber = selectedEpisode.value + 1;

    if (nextEpisodeNumber <= maxEpisodes) {
      if (kDebugMode) {
        print("Loading next episode in same season: $nextEpisodeNumber");
      }
      await changeEpisode(nextEpisodeNumber);
    } else {
      final nextSeasonNumber = selectedSeason.value + 1;
      final nextSeasonInfo = resource.value?.seasons?.firstWhereOrNull(
            (s) => s.se == nextSeasonNumber,
      );

      if (nextSeasonInfo != null) {
        if (kDebugMode) {
          print("Loading first episode of next season: $nextSeasonNumber");
        }
        changeSeason(nextSeasonNumber);
      } else {
        if (kDebugMode) print("Finished all episodes in the series.");
        isPlaying.value = false;
        _isHandlingVideoEnd = false;
      }
    }
  }

  // --- Helper Methods ---

  Future<ClosedCaptionFile>? _buildClosedCaptionFile({Captions? fromCaption}) {
    final url = fromCaption?.url;
    if (url == null) {
      return null;
    }

    return () async {
      try {
        final connect = GetConnect();
        final response = await connect.get(
          url,
          headers: {'Origin': 'https://fmoviesunblocked.net'},
        );
        if (response.isOk && response.bodyString != null) {
          return SubRipCaptionFile(response.bodyString!);
        } else {
          throw Exception(
            'Failed to download subtitle file: ${response.statusText}',
          );
        }
      } catch (e) {
        if (kDebugMode) {
          print("Error fetching or parsing subtitle file: $e");
        }
        rethrow;
      }
    }();
  }

  void _sortStreamsByQuality() {
    streamInfoList.sort((a, b) {
      final resA = int.tryParse(a.resolutions ?? '0') ?? 0;
      final resB = int.tryParse(b.resolutions ?? '0') ?? 0;
      return resB.compareTo(resA);
    });
  }

  @override
  void onClose() {
    // NEW: Cancel timer and save progress one last time before closing.
    _progressSaveTimer?.cancel();
    _saveProgress();

    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    videoPlayerController.dispose();
    super.onClose();
  }
}

