import 'dart:async';
import 'dart:io'; // Required for Platform check

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
// NEW: Import GetStorage for local data persistence.
import 'package:get_storage/get_storage.dart';
import 'package:movie/app/data/api_provider.dart';
import 'package:movie/app/data/user_data.dart';
import 'package:movie/app/modules/home_screen/controllers/home_screen_controller.dart';
import 'package:movie/app/model/subject_list.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart'; // Required for Full Screen

import '../../../../windowTitleBarController.dart';
import '../../../model/CaptionApiResponse.dart';
import '../../../model/StreamInfo.dart';
import '../../../services/download_service.dart';
import '../../../services/prefs.dart';

// Enum to manage which settings panel is currently visible
enum SettingPanel { None, Episodes, AudioSubtitles, Quality, Fit }

/// One language version of the title. MovieBox ships each dub (and each
/// burned-in-subtitle cut) as its own subject with its own streams.
class AudioTrack {
  const AudioTrack({
    required this.subjectId,
    required this.detailPath,
    required this.language,
    this.original = false,
  });

  final String subjectId;
  final String detailPath;
  final String language;
  final bool original;

  /// "Arabic sub" etc.: original audio with subtitles burned into the picture.
  bool get isHardsub => language.toLowerCase().trim().endsWith(' sub');
}

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

  // --- Audio versions ---
  final RxList<AudioTrack> audioTracks = <AudioTrack>[].obs;
  // subjectId of the version being played (starts as the opened title).
  final RxString currentTrackId = ''.obs;
  // Shown over the spinner while a new version / episode loads.
  final RxString loadingMessage = ''.obs;

  List<AudioTrack> get audioOptions => audioTracks.where((t) => !t.isHardsub).toList();
  List<AudioTrack> get hardsubOptions => audioTracks.where((t) => t.isHardsub).toList();

  /// The subject whose streams are playing: the chosen language version,
  /// while progress keeps saving under the opened title.
  Subject get _playbackSubject {
    final track = audioTracks.firstWhereOrNull((t) => t.subjectId == currentTrackId.value);
    if (track == null || track.subjectId == subject.value?.subjectId) return subject.value!;
    return Subject(
      subjectId: track.subjectId,
      detailPath: track.detailPath,
      title: subject.value?.title,
      subjectType: subject.value?.subjectType,
    );
  }

  // --- Storage & Persistence ---
  final _storage = GetStorage();
  Timer? _progressSaveTimer;
  Duration _startAt = Duration.zero;

  // Subtitle font-size multiplier (persisted, applied as the default going forward).
  final RxDouble subtitleScale = 1.0.obs;

  // Storage Keys
  static const String _keyVideoFit = 'user_pref_video_fit';
  static const String _keyResolution = 'user_pref_resolution';
  static const String _keySubtitleLang = 'user_pref_subtitle_lang';
  static const String _keySubtitleScale = 'user_pref_subtitle_scale';

  @override
  void onInit() {
    super.onInit();
    WakelockPlus.enable();

    // -------------------------------------------------------
    // FULL SCREEN LOGIC
    // -------------------------------------------------------
    if (!kIsWeb && Platform.isWindows) {
      windowManager.setFullScreen(true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (Get.isRegistered<WindowTitleBarController>()) {
            Get.find<WindowTitleBarController>().hide();
          }
        } catch (e) {
          if (kDebugMode) print("Error hiding title bar: $e");
        }
      });

    }

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    // TVs and desktops: full immersive. Phones keep the navigation bar: with
    // it hidden, Android spends the first BACK only revealing the bars, so
    // leaving the player took two presses.
    if (_isPhone) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.bottom]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }

    // -------------------------------------------------------
    // LOAD PREFERENCES
    // -------------------------------------------------------
    // 1. Video Fit Preference
    final savedFitIndex = _storage.read(_keyVideoFit);
    if (savedFitIndex != null &&
        savedFitIndex is int &&
        savedFitIndex >= 0 &&
        savedFitIndex < BoxFit.values.length) {
      videoFit.value = BoxFit.values[savedFitIndex];
    }

    // Auto-save Fit preference when it changes
    ever(videoFit, (BoxFit fit) {
      _storage.write(_keyVideoFit, fit.index);
    });

    // Subtitle size preference — becomes the default for future playback.
    final savedScale = _storage.read(_keySubtitleScale);
    if (savedScale is num) subtitleScale.value = savedScale.toDouble();
    ever(subtitleScale, (double s) => _storage.write(_keySubtitleScale, s));

    // -------------------------------------------------------
    // ARGS & INIT
    // -------------------------------------------------------
    final arguments = Get.arguments as Map<String, dynamic>;
    subject.value = arguments['subject'];
    resource.value = arguments['resource'];
    streamInfoList.value = arguments['streams'];
    selectedSeason.value = arguments['season'];
    selectedEpisode.value = arguments['episode'];
    _startAt = arguments['position'] as Duration? ?? Duration.zero;
    currentTrackId.value = subject.value?.subjectId ?? '';
    _loadAudioTracks();

    if (streamInfoList.isNotEmpty) {
      _sortStreamsByQuality(); // Now checks storage for preferred resolution
      _initializePlayerWithFallback(startAt: _startAt);
    } else {
      errorMessage.value = "No video streams were found for this content.";
    }
  }
  /// BACK, one step at a time: close an open menu → show the hidden
  /// controls → leave the player (only when the controls are already showing).
  void handleBackButtonPress() {
    if (upNext.value != null) {
      cancelUpNext();
      showControls.value = true;
      resetControlsTimer();
      return;
    }
    if (activeSettingPanel.value != SettingPanel.None) {
      closeSettingPanel();
      return;
    }
    // Remote only: the first BACK brings hidden controls up. On a phone BACK
    // leaves at once, as in Netflix.
    if (!showControls.value && !_isPhone) {
      showControls.value = true;
      resetControlsTimer();
      return;
    }
    leave();
  }

  /// Closes the player. Navigator directly: Get.back() first tries to close
  /// a GetX snackbar, and one that failed to show makes it throw and stay.
  void leave() {
    final nav = Get.key.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    } else {
      Get.back();
    }
  }

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

        await _openStream(stream);
        if (startAt != Duration.zero) {
          await videoPlayerController.seekTo(startAt);
        }
        await videoPlayerController.play();

        isPlayerReady.value = true;
        isPlaying.value = true;

        videoPlayerController.addListener(() {
          isPlaying.value = videoPlayerController.value.isPlaying;
          isBuffering.value = videoPlayerController.value.isBuffering;
          currentCaptionText.value = videoPlayerController.value.caption.text;

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

  /// A downloaded file (an absolute path) rather than a URL.
  static bool _isLocal(String? url) => url != null && (url.startsWith('/') || url.startsWith('file:'));

  /// Opens [stream] straight from the CDN, falling back to its proxied URL.
  Future<void> _openStream(StreamInfo stream) async {
    if (_isLocal(stream.url)) {
      final controller = VideoPlayerController.file(File(stream.url!.replaceFirst('file://', '')));
      await controller.initialize();
      videoPlayerController = controller;
      return;
    }
    final candidates = [
      (stream.url!, stream.headers ?? const <String, String>{}),
      if (stream.fallbackUrl != null)
        (stream.fallbackUrl!, const <String, String>{}),
    ];
    for (var i = 0; i < candidates.length; i++) {
      final (url, headers) = candidates[i];
      final controller =
          VideoPlayerController.networkUrl(Uri.parse(url), httpHeaders: headers);
      try {
        await controller.initialize();
        videoPlayerController = controller;
        return;
      } catch (e) {
        await controller.dispose();
        if (kDebugMode) {
          print("Stream source ${i + 1}/${candidates.length} failed: $e");
        }
        if (i == candidates.length - 1) rethrow;
      }
    }
  }

  // --- Progress Saving ---

  void _saveProgress() {
    if (isPlayerReady.value && subject.value?.subjectId != null) {
      final position = videoPlayerController.value.position;
      final duration = videoPlayerController.value.duration;
      if (duration > Duration.zero && _isFinished(position, duration)) {
        _markFinished();
        return;
      }
      if (position > const Duration(seconds: 5)) {
        final progressData = {
          'season': selectedSeason.value,
          'episode': selectedEpisode.value,
          'position': position.inSeconds,
        };
        _storage.write('progress_${subject.value!.subjectId}', progressData);

        // Feed the home "Continue Watching" row.
        UserData.saveProgress(
          subject.value!,
          season: selectedSeason.value,
          episode: selectedEpisode.value,
          positionSec: position.inSeconds,
          durationSec: videoPlayerController.value.duration.inSeconds,
        );
      }
    }
  }

  /// Into the credits: the last 10 seconds, or the final 5%.
  bool _isFinished(Duration position, Duration duration) =>
      position >= duration - const Duration(seconds: 10) ||
      position.inMilliseconds >= duration.inMilliseconds * 0.95;

  /// A finished title no longer "continues" where it stopped: a series moves
  /// on to the next episode (from its start); a movie or final episode leaves
  /// Continue Watching.
  void _markFinished() {
    final s = subject.value!;
    final next = _nextEpisodeAfter(selectedSeason.value, selectedEpisode.value);
    // Smart Downloads: the watched download goes, the next episode comes.
    if (DownloadService.supported && Get.isRegistered<DownloadService>()) {
      DownloadService.to.onFinished(s, selectedSeason.value, selectedEpisode.value);
    }
    if (next == null) {
      _storage.remove('progress_${s.subjectId}');
      UserData.removeContinue(s.subjectId);
      return;
    }
    _storage.write('progress_${s.subjectId}', {
      'season': next.$1,
      'episode': next.$2,
      'position': 0,
    });
    UserData.saveProgress(s,
        season: next.$1, episode: next.$2, positionSec: 0, durationSec: 0);
  }

  /// (season, episode) after the given one, or null at the end of the show.
  (int, int)? _nextEpisodeAfter(int season, int episode) {
    final seasons = resource.value?.seasons;
    if (seasons == null || season == 0) return null; // movies use season 0
    final eps = episodesFor(season);
    final i = eps.indexOf(episode);
    if (i >= 0 && i < eps.length - 1) return (season, eps[i + 1]);
    final nextEps = episodesFor(season + 1);
    return nextEps.isEmpty ? null : (season + 1, nextEps.first);
  }

  void _startPeriodicSave() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (isPlaying.value) {
        _saveProgress();
      }
    });
  }

  /// Language versions come from the title's detail (`subject.dubs`).
  Future<void> _loadAudioTracks() async {
    final id = subject.value?.subjectId;
    if (id == null) return;
    try {
      final detail = await apiProvider.fetchSubject(id);
      final raw = _field(_field(detail, 'subject'), 'dubs');
      if (raw is! List) return;
      audioTracks.assignAll(raw.whereType<Map>().where((d) =>
          d['subjectId'] != null && d['detailPath'] != null).map((d) => AudioTrack(
            subjectId: '${d['subjectId']}',
            detailPath: '${d['detailPath']}',
            language: '${d['lanName'] ?? ''}',
            original: d['original'] == true,
          )));
    } catch (e) {
      if (kDebugMode) print("Could not load audio versions: $e");
    }
  }

  /// Switches language version and carries on from the same moment: the new
  /// version's streams for this episode are fetched and opened at the current
  /// position. The subtitle language carries over when the version has it.
  Future<void> changeAudio(AudioTrack track, {bool subtitlesOff = false}) async {
    if (track.subjectId == currentTrackId.value || !isPlayerReady.value) return;
    final position = videoPlayerController.value.position;
    final previousLang = selectedCaption.value?.lan;
    final wasPlaying = isPlaying.value;
    closeSettingPanel();
    loadingMessage.value = 'Switching to ${track.language}…';

    final response = await apiProvider.fetchPlaybackInfoWithCookieManager(
      subject: Subject(
        subjectId: track.subjectId,
        detailPath: track.detailPath,
        title: subject.value?.title,
        subjectType: subject.value?.subjectType,
      ),
      season: '${selectedSeason.value}',
      episode: '${selectedEpisode.value}',
    );
    final streams = _field(_field(response, 'data'), 'streams');
    if (streams is! List || streams.isEmpty) {
      loadingMessage.value = '';
      Get.snackbar(track.language, 'Not available for this episode.',
          snackPosition: SnackPosition.BOTTOM, colorText: Colors.white);
      return;
    }

    currentTrackId.value = track.subjectId;
    streamInfoList.value =
        streams.map((s) => StreamInfo.fromJson(s as Map<String, dynamic>)).toList();
    _sortStreamsByQuality();
    // A burned-in version needs no soft subtitles on top.
    _carryCaptionLang = subtitlesOff ? _subtitlesOff : previousLang;

    await videoPlayerController.pause();
    isPlayerReady.value = false;
    selectedStream.value = streamInfoList.first;
    selectedCaption.value = null;
    captionList.clear();
    await videoPlayerController.dispose();
    await _initializePlayerWithFallback(startAt: position);
    if (!wasPlaying && isPlayerReady.value) await videoPlayerController.pause();
    loadingMessage.value = '';
  }

  /// `m[key]` when [m] is a map, else null (API payloads are loosely typed).
  static dynamic _field(dynamic m, String key) => m is Map ? m[key] : null;

  // Subtitle language to re-pick after an audio switch (overrides the saved
  // preference once; null = use the preference).
  String? _carryCaptionLang;
  static const String _subtitlesOff = 'off';

  Future<void> _fetchSubtitles() async {
    if (selectedStream.value == null || subject.value == null) return;
    try {
      final List<Captions>? captions;
      if (_isLocal(selectedStream.value!.url)) {
        // Saved next to the download.
        captions = DownloadService.to.offlineCaptions(
            subject.value!.subjectId, selectedSeason.value, selectedEpisode.value);
      } else {
        final dynamic responseData = await apiProvider.fetchSubtitlesForStream(
          streamId: selectedStream.value!.id!,
          subjectId: subject.value!.subjectId!,
        );
        captions = CaptionApiResponse.fromJson(responseData).data?.captions;
      }

      if (captions != null && captions.isNotEmpty) {
        captionList.value = captions;

        if (selectedCaption.value == null) {
          // 1. Try to load Preferred Language (the one playing before an audio
          //    switch wins; "off" is a real choice and is respected).
          final prefLang = _carryCaptionLang ?? _storage.read(_keySubtitleLang);
          _carryCaptionLang = null;
          if (prefLang == _subtitlesOff) return;
          Captions? targetCaption;

          if (prefLang != null) {
            targetCaption = captions.firstWhereOrNull((c) => c.lan == prefLang);
          }

          // 2. Fallback to English
          if (targetCaption == null) {
            targetCaption = captions.firstWhereOrNull(
                  (c) => c.lan == 'en' || c.lanName?.toLowerCase() == 'english',
            );
          }

          if (targetCaption != null) {
            // savePreference: false because this is auto-selection, not explicit user action.
            // We don't want to overwrite a user's preference for 'Spanish' just because this
            // specific movie only had 'English'.
            await changeSubtitle(targetCaption, savePreference: false);
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

  // --- D-pad scrubbing on the seek bar ---

  /// Where a held LEFT/RIGHT is heading; null when not scrubbing.
  final Rxn<Duration> scrubTarget = Rxn<Duration>();
  int _scrubRepeats = 0;

  /// One scrub step. Key repeats speed up the longer the key is held:
  /// 10 s steps, then 30 s (after ~1 s), then 60 s (after ~3 s).
  void scrubStep(int direction, {required bool repeat}) {
    if (!isPlayerReady.value) return;
    final v = videoPlayerController.value;
    if (v.duration <= Duration.zero) return;
    _scrubRepeats = repeat ? _scrubRepeats + 1 : 0;
    final step = _scrubRepeats < 12 ? 10 : (_scrubRepeats < 40 ? 30 : 60);
    var t = (scrubTarget.value ?? v.position) + Duration(seconds: step * direction);
    if (t < Duration.zero) t = Duration.zero;
    final end = v.duration - const Duration(seconds: 1);
    if (t > end) t = end;
    scrubTarget.value = t;
    showControls.value = true;
    resetControlsTimer();
  }

  /// Key released (or focus left the bar): jump to the scrub target.
  void commitScrub() {
    final t = scrubTarget.value;
    _scrubRepeats = 0;
    if (t == null) return;
    scrubTarget.value = null;
    if (isPlayerReady.value) videoPlayerController.seekTo(t);
  }

  // --- Downloads from the episodes panel ---

  Map<int, List<int>> get _episodeMap => {
        for (final s in resource.value?.seasons ?? const <SeasonResource>[])
          if ((s.se ?? 0) > 0) s.se!: episodesFor(s.se!),
      };

  /// Starts (or retries) an episode download of the opened title.
  Future<void> downloadEpisode(int season, int episode) async {
    final s = subject.value;
    if (s == null) return;
    final existing = DownloadService.to.itemFor(s.subjectId, season, episode);
    if (existing != null && existing.state == DownloadState.failed) {
      await DownloadService.to.retry(existing);
      return;
    }
    final err = await DownloadService.to.download(s, season: season, episode: episode, episodes: _episodeMap);
    if (err != null) {
      Get.snackbar('Download', err, snackPosition: SnackPosition.BOTTOM, colorText: Colors.white);
    }
  }

  // --- Touch: vertical swipe — left half brightness, right half volume ---

  /// 'brightness' | 'volume' while a vertical swipe is in progress.
  final RxnString levelKind = RxnString();
  final RxDouble level = 0.0.obs;
  double _levelFrom = 0;
  double _levelDy = 0;
  Timer? _levelHide;
  bool _brightnessChanged = false;

  static bool get _touchPlatform => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// A touch phone / tablet. A TV box is wide but short in logical pixels
  /// (1080p at 2x is 960×540); phones stay under 900 wide, tablets are tall.
  static bool get _isPhone {
    if (!_touchPlatform) return false;
    final long = Get.width > Get.height ? Get.width : Get.height;
    final short = Get.width > Get.height ? Get.height : Get.width;
    return !(long >= 900 && short < 700);
  }

  Future<void> startLevelDrag({required bool rightSide}) async {
    if (!_touchPlatform) return;
    _levelHide?.cancel();
    _levelDy = 0;
    final kind = rightSide ? 'volume' : 'brightness';
    try {
      if (kind == 'volume') {
        VolumeController.instance.showSystemUI = false;
        _levelFrom = await VolumeController.instance.getVolume();
      } else {
        _levelFrom = await ScreenBrightness.instance.application;
      }
    } catch (_) {
      _levelFrom = 0.5;
    }
    level.value = _levelFrom;
    levelKind.value = kind;
  }

  /// Up raises, down lowers; a swipe of ~80% of the height covers 0→100%.
  void updateLevelDrag(double dy, double height) {
    final kind = levelKind.value;
    if (kind == null || height <= 0) return;
    _levelDy += dy;
    final v = (_levelFrom - _levelDy / (height * 0.8)).clamp(0.0, 1.0);
    level.value = v;
    try {
      if (kind == 'volume') {
        VolumeController.instance.setVolume(v);
      } else {
        _brightnessChanged = true;
        ScreenBrightness.instance.setApplicationScreenBrightness(v);
      }
    } catch (_) {}
  }

  void endLevelDrag() {
    _levelHide?.cancel();
    _levelHide = Timer(const Duration(milliseconds: 700), () => levelKind.value = null);
  }

  // --- Touch: horizontal swipe on the picture scrubs ---

  Duration? _dragFrom;
  double _dragDx = 0;
  /// Seconds the current swipe moves (for the centre readout); null = no swipe.
  final RxnInt dragDeltaSec = RxnInt();

  void startDragScrub() {
    if (!isPlayerReady.value) return;
    _dragFrom = videoPlayerController.value.position;
    _dragDx = 0;
    dragDeltaSec.value = 0;
    showControls.value = true;
    _controlsVisibilityTimer?.cancel();
  }

  /// A full-width swipe covers 2 minutes, or a fifth of long titles.
  void updateDragScrub(double dx, double width) {
    final from = _dragFrom;
    final dur = videoPlayerController.value.duration;
    if (from == null || dur <= Duration.zero || width <= 0) return;
    _dragDx += dx;
    final spanSec = (dur.inSeconds ~/ 5).clamp(120, 1200).clamp(0, dur.inSeconds);
    var t = from + Duration(milliseconds: (spanSec * 1000 * _dragDx / width).round());
    if (t < Duration.zero) t = Duration.zero;
    final end = dur - const Duration(seconds: 1);
    if (t > end) t = end;
    scrubTarget.value = t;
    dragDeltaSec.value = (t - from).inSeconds;
  }

  void endDragScrub() {
    if (_dragFrom == null) return;
    _dragFrom = null;
    dragDeltaSec.value = null;
    commitScrub();
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
    final eps = episodesFor(season);
    playEpisode(season, eps.isEmpty ? 1 : eps.first);
  }

  Future<void> changeEpisode(int episode) => playEpisode(selectedSeason.value, episode);

  /// Episode numbers of [season] (`allEp` when listed, else 1..maxEp).
  List<int> episodesFor(int season) {
    final s = resource.value?.seasons?.firstWhereOrNull((x) => x.se == season);
    if (s == null) return const [];
    final listed = (s.allEp ?? '')
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList();
    return listed.isNotEmpty ? listed : List.generate(s.maxEp ?? 0, (i) => i + 1);
  }

  /// Switches to any episode (any season): fetches its streams in the chosen
  /// language (falling back to the original version when that dub lacks the
  /// episode) and starts it from the beginning. On failure the current
  /// episode keeps playing.
  Future<void> playEpisode(int season, int episode) async {
    if (season == selectedSeason.value &&
        episode == selectedEpisode.value &&
        isPlayerReady.value &&
        !_isHandlingVideoEnd) {
      closeSettingPanel();
      return;
    }
    cancelUpNext();
    _saveProgress();
    closeSettingPanel();
    final prevSeason = selectedSeason.value, prevEpisode = selectedEpisode.value;
    final wasReady = isPlayerReady.value;
    if (wasReady) await videoPlayerController.pause();
    isPlayerReady.value = false;
    loadingMessage.value = 'Loading S$season:E$episode…';

    // A downloaded episode plays from the device (works offline too).
    final offline = Get.isRegistered<DownloadService>()
        ? DownloadService.to.offlineStream(subject.value?.subjectId, season, episode)
        : null;
    if (offline != null) {
      selectedSeason.value = season;
      selectedEpisode.value = episode;
      streamInfoList.value = [offline];
      _carryCaptionLang ??= selectedCaption.value?.lan;
      selectedStream.value = offline;
      selectedCaption.value = null;
      captionList.clear();
      if (wasReady) await videoPlayerController.dispose();
      await _initializePlayerWithFallback();
      loadingMessage.value = '';
      return;
    }

    var response = await apiProvider.fetchPlaybackInfoWithCookieManager(
      subject: _playbackSubject,
      season: '$season',
      episode: '$episode',
    );
    var streams = _field(_field(response, 'data'), 'streams');
    if ((streams is! List || streams.isEmpty) &&
        currentTrackId.value != subject.value?.subjectId) {
      currentTrackId.value = subject.value?.subjectId ?? '';
      response = await apiProvider.fetchPlaybackInfoWithCookieManager(
        subject: subject.value!,
        season: '$season',
        episode: '$episode',
      );
      streams = _field(_field(response, 'data'), 'streams');
    }

    if (streams is! List || streams.isEmpty) {
      loadingMessage.value = '';
      selectedSeason.value = prevSeason;
      selectedEpisode.value = prevEpisode;
      if (wasReady) {
        isPlayerReady.value = true;
        videoPlayerController.play();
      }
      Get.snackbar('S$season:E$episode', 'This episode is unavailable right now.',
          snackPosition: SnackPosition.BOTTOM, colorText: Colors.white);
      return;
    }

    selectedSeason.value = season;
    selectedEpisode.value = episode;
    streamInfoList.value =
        streams.map((s) => StreamInfo.fromJson(s as Map<String, dynamic>)).toList();
    _sortStreamsByQuality();
    // Keep the subtitle language across episodes.
    _carryCaptionLang ??= selectedCaption.value?.lan;
    selectedStream.value = streamInfoList.first;
    selectedCaption.value = null;
    captionList.clear();
    if (wasReady) await videoPlayerController.dispose();
    await _initializePlayerWithFallback();
    loadingMessage.value = '';
  }

  Future<void> changeStream(StreamInfo newStream) async {
    if (!isPlayerReady.value || newStream.id == selectedStream.value?.id) {
      return;
    }
    // Save Resolution Preference
    if (newStream.resolutions != null) {
      _storage.write(_keyResolution, newStream.resolutions);
    }
    await _reloadPlayer(newStream: newStream);
  }

  Future<void> changeSubtitle(Captions? newCaption,
      {bool savePreference = true}) async {
    if (selectedCaption.value?.id == newCaption?.id) return;
    if (!isPlayerReady.value) return;

    // Save Subtitle Language Preference ("off" included).
    if (savePreference) {
      _storage.write(_keySubtitleLang, newCaption?.lan ?? _subtitlesOff);
    }

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

  // --- Manual next / previous episode navigation ---
  bool get hasNextEpisode =>
      _nextEpisodeAfter(selectedSeason.value, selectedEpisode.value) != null;

  /// A series (movies play as season 0).
  bool get isSeries => (resource.value?.seasons?.firstOrNull?.se ?? 0) != 0;

  Future<void> playNextEpisode() async {
    final next = _nextEpisodeAfter(selectedSeason.value, selectedEpisode.value);
    if (next != null) await playEpisode(next.$1, next.$2);
  }

  Future<void> playPreviousEpisode() async {
    final season = selectedSeason.value;
    final eps = episodesFor(season);
    final i = eps.indexOf(selectedEpisode.value);
    if (i > 0) {
      await playEpisode(season, eps[i - 1]);
      return;
    }
    final prev = episodesFor(season - 1);
    if (prev.isNotEmpty) await playEpisode(season - 1, prev.last);
  }

  // --- Up next (auto-play) ---

  static const String _keyAutoPlay = 'user_pref_autoplay_next';
  static const int upNextCountdown = 3;

  /// Play the next episode automatically when one ends (saved preference).
  late final RxBool autoPlayNext = (_storage.read(_keyAutoPlay) != false).obs;
  // (season, episode) offered after the current one ended; null = hidden.
  final Rxn<(int, int)> upNext = Rxn<(int, int)>();
  // Seconds left on the countdown; 0 when autoplay is off (card waits for OK).
  final RxInt upNextSeconds = 0.obs;
  Timer? _upNextTimer;

  void setAutoPlayNext(bool on) {
    autoPlayNext.value = on;
    _storage.write(_keyAutoPlay, on);
    if (Get.isRegistered<AppPrefs>()) AppPrefs.to.autoplayNext.value = on;
    if (!on && upNext.value != null) {
      _upNextTimer?.cancel();
      upNextSeconds.value = 0;
    }
  }

  void cancelUpNext() {
    _upNextTimer?.cancel();
    _upNextTimer = null;
    upNext.value = null;
    upNextSeconds.value = 0;
  }

  void playUpNextNow() {
    final next = upNext.value;
    cancelUpNext();
    if (next != null) playEpisode(next.$1, next.$2);
  }

  /// The episode reached its end: offer the next one with a countdown
  /// (autoplay) or a waiting "Next episode" card; at the end of the show just
  /// bring the controls back.
  Future<void> _handleNextEpisode() async {
    if (_isHandlingVideoEnd) return;
    _isHandlingVideoEnd = true;
    _saveProgress(); // marks it finished (see _markFinished)

    final next = _nextEpisodeAfter(selectedSeason.value, selectedEpisode.value);
    if (next == null) {
      isPlaying.value = false;
      showControls.value = true;
      return;
    }
    upNext.value = next;
    showControls.value = false;
    if (!autoPlayNext.value) {
      upNextSeconds.value = 0;
      return;
    }
    upNextSeconds.value = upNextCountdown;
    _upNextTimer?.cancel();
    _upNextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (upNextSeconds.value <= 1) {
        t.cancel();
        playUpNextNow();
      } else {
        upNextSeconds.value--;
      }
    });
  }

  // --- Helper Methods ---

  Future<ClosedCaptionFile>? _buildClosedCaptionFile({Captions? fromCaption}) {
    final url = fromCaption?.url;
    if (url == null) {
      return null;
    }

    if (_isLocal(url)) {
      return File(url.replaceFirst('file://', ''))
          .readAsString()
          .then((text) => SubRipCaptionFile(text));
    }
    return () async {
      try {
        final connect = GetConnect();
        final response = await connect.get(url);
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
    // 1. Standard sort (High to Low)
    streamInfoList.sort((a, b) {
      final resA = int.tryParse(a.resolutions ?? '0') ?? 0;
      final resB = int.tryParse(b.resolutions ?? '0') ?? 0;
      return resB.compareTo(resA);
    });

    // 2. Prioritize User Preference
    final prefRes = _storage.read(_keyResolution);
    if (prefRes != null && prefRes is String) {
      // Find the stream that matches the preferred resolution
      final index = streamInfoList.indexWhere((s) => s.resolutions == prefRes);
      // If found and not already the first one, move it to the front
      if (index > 0) {
        final item = streamInfoList.removeAt(index);
        streamInfoList.insert(0, item);
      }
    }
  }

  @override
  void onClose() {
    _upNextTimer?.cancel();
    _progressSaveTimer?.cancel();
    _levelHide?.cancel();
    // The player's brightness is its own; the rest of the app goes back to normal.
    if (_brightnessChanged) {
      ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) {});
    }
    _saveProgress();
    // Refresh the home "Continue Watching" row on the way out.
    if (Get.isRegistered<HomeScreenController>()) {
      Get.find<HomeScreenController>().refreshUserRows();
    }

    // -------------------------------------------------------
    // RESTORE WINDOW LOGIC
    // -------------------------------------------------------
    if (!kIsWeb && Platform.isWindows) {
      windowManager.setFullScreen(false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (Get.isRegistered<WindowTitleBarController>()) {
            Get.find<WindowTitleBarController>().show();
          }
        } catch (e) {
          if (kDebugMode) print("Error showing title bar: $e");
        }
      });
    }
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    videoPlayerController.dispose();
    super.onClose();
  }
}