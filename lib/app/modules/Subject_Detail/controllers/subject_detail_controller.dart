import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:movie/app/data/api_provider.dart';
import 'package:movie/app/data/user_data.dart';
import 'package:movie/app/modules/home_screen/controllers/home_screen_controller.dart';
import 'package:video_player/video_player.dart';

import '../../../model/StreamInfo.dart';
import '../../../services/download_service.dart';
import '../../../model/subject_list.dart';
import '../../video_player/bindings/video_player_binding.dart';
import '../../video_player/views/video_player_view.dart';

/// One audio version of a title. MovieBox ships each dub as its own subject.
class DubOption {
  const DubOption({required this.subjectId, required this.language, this.original = false});
  final String subjectId;
  final String language;
  final bool original;
}

/// Arguments: a subjectId `String`, or `{'id': subjectId, 'resume': true}` to
/// continue playback as soon as the details load (home "Continue Watching").
class SubjectDetailController extends GetxController {
  // --- Observables ---
  final Rx<Subject?> subject = Subject().obs;
  final Rx<Resource?> resource = Resource().obs;
  final isLoading = true.obs;
  // Stream lookup after Play; the page stays up (only the button shows it).
  final isStarting = false.obs;
  final RxList<Star> cast = <Star>[].obs;
  final RxList<DubOption> dubs = <DubOption>[].obs;
  final RxList<String> subtitleLanguages = <String>[].obs;
  final inMyList = false.obs;

  // Episode picker: the season whose episodes are shown.
  final RxInt selectedSeason = 1.obs;

  // --- Trailer Player (TV / desktop background) ---
  final Rx<VideoPlayerController?> videoPlayerController =
      Rx<VideoPlayerController?>(null);
  final RxBool showTrailer = false.obs;

  // --- View State ---
  final isContentLoaded = false.obs;
  late final FocusNode playButtonFocusNode;

  // --- Continue Watching Feature ---
  final _storage = GetStorage();
  final Rx<int?> lastPlayedSeason = Rx<int?>(null);
  final Rx<int?> lastPlayedEpisode = Rx<int?>(null);
  final Rx<Duration> lastPlayedPosition = Duration.zero.obs;
  final RxBool hasSavedProgress = false.obs;
  final RxnInt remainingSec = RxnInt();
  final RxDouble progressFraction = 0.0.obs;

  bool _resumeOnLoad = false;

  // --- Injected Dependencies ---
  final ApiProvider apiProvider = Get.find<ApiProvider>();

  bool get isMovie {
    final seasons = resource.value?.seasons;
    return seasons == null || seasons.isEmpty || seasons.first.se == 0;
  }

  bool get canPlay => resource.value?.seasons?.isNotEmpty ?? false;

  /// Highest resolution any season offers (e.g. 1080), or null.
  int? get maxResolution {
    int? best;
    for (final s in resource.value?.seasons ?? const <SeasonResource>[]) {
      for (final r in s.resolutions ?? const <Resolution>[]) {
        final v = r.resolution;
        if (v != null && (best == null || v > best)) best = v;
      }
    }
    return best;
  }

  /// The audio version currently shown, if the title has dubs.
  DubOption? get currentDub =>
      dubs.firstWhereOrNull((d) => d.subjectId == subject.value?.subjectId);

  List<int> episodesFor(int season) {
    final s = resource.value?.seasons?.firstWhereOrNull((x) => x.se == season);
    if (s == null) return const [];
    final listed = (s.allEp ?? '')
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList();
    if (listed.isNotEmpty) return listed;
    return List.generate(s.maxEp ?? 0, (i) => i + 1);
  }

  // --- Downloads ---------------------------------------------------------------

  /// Season → episode numbers, for Smart Downloads' "next episode".
  Map<int, List<int>> get episodeMap => {
        for (final s in resource.value?.seasons ?? const <SeasonResource>[])
          if ((s.se ?? 0) > 0) s.se!: episodesFor(s.se!),
      };

  DownloadItem? downloadFor(int season, int episode) =>
      DownloadService.to.itemFor(subject.value?.subjectId, season, episode);

  /// Starts (or, when failed, retries) one download; tells the user why not.
  Future<void> download(int season, int episode) async {
    final s = subject.value;
    if (s == null) return;
    final existing = downloadFor(season, episode);
    if (existing != null && existing.state == DownloadState.failed) {
      await DownloadService.to.retry(existing);
      return;
    }
    final err = await DownloadService.to.download(s,
        season: season, episode: episode, episodes: isMovie ? null : episodeMap);
    if (err != null) {
      Get.snackbar('Download', err, snackPosition: SnackPosition.BOTTOM, colorText: Colors.white);
    }
  }

  /// Every episode of [season] that isn't downloaded yet.
  Future<void> downloadSeason(int season) async {
    for (final ep in episodesFor(season)) {
      if (downloadFor(season, ep) == null) await download(season, ep);
    }
  }

  @override
  void onInit() {
    super.onInit();
    playButtonFocusNode = FocusNode();
    final args = Get.arguments;
    String subjectId = '';
    if (args is String) {
      subjectId = args;
    } else if (args is Map) {
      subjectId = '${args['id'] ?? ''}';
      _resumeOnLoad = args['resume'] == true;
    }
    fetchSubjectDetails(subjectId);
  }

  @override
  void onClose() {
    _trailerAllowed = false;
    _disposeTrailer();
    playButtonFocusNode.dispose();
    super.onClose();
  }

  void toggleMyList() {
    final s = subject.value;
    if (s == null || s.subjectId == null) return;
    inMyList.value = UserData.toggleMyList(s);
    if (Get.isRegistered<HomeScreenController>()) {
      Get.find<HomeScreenController>().refreshUserRows();
    }
  }

  /// Switches to another audio version (a separate MovieBox subject).
  void selectDub(DubOption dub) {
    if (dub.subjectId == subject.value?.subjectId) return;
    fetchSubjectDetails(dub.subjectId);
  }

  Future<void> fetchSubjectDetails(String subjectId) async {
    try {
      isLoading(true);
      isContentLoaded.value = false; // Reset animation state
      hasSavedProgress.value = false;
      _disposeTrailer();

      final tempSubject = await apiProvider.fetchSubject(subjectId);
      // Guard: no host resolved this id (missing from the detail catalog / HTML
      // fallback) — show a clear message instead of a silent blank page.
      if (tempSubject == null || tempSubject['subject'] == null) {
        isLoading(false);
        Get.snackbar('Unavailable', 'This title has no details right now.',
            snackPosition: SnackPosition.BOTTOM);
        Future.delayed(const Duration(milliseconds: 400), () {
          if (!isClosed) Get.back();
        });
        return;
      }
      final rawSubject = Map<String, dynamic>.from(tempSubject['subject'] as Map);
      subject.value = Subject.fromJson(rawSubject);
      resource.value = tempSubject['resource'] == null
          ? Resource(seasons: [])
          : Resource.fromJson(tempSubject['resource']);

      // Cast (the detail endpoint returns a `stars` list).
      final rawStars = tempSubject['stars'];
      if (rawStars is List) {
        cast.assignAll(rawStars.map((e) => Star.fromJson(e)).toList());
      } else {
        cast.clear();
      }

      // Audio versions and subtitle languages, straight from the subject.
      final rawDubs = rawSubject['dubs'];
      dubs.assignAll(rawDubs is List
          ? rawDubs.whereType<Map>().where((d) => d['subjectId'] != null).map((d) =>
              DubOption(
                subjectId: '${d['subjectId']}',
                language: '${d['lanName'] ?? ''}',
                original: d['original'] == true,
              ))
          : const <DubOption>[]);
      subtitleLanguages.assignAll((subject.value?.subtitles ?? '')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty));

      inMyList.value = UserData.inMyList(subject.value?.subjectId);

      _loadProgress();
      final seasons = resource.value?.seasons ?? const <SeasonResource>[];
      selectedSeason.value = lastPlayedSeason.value ??
          (seasons.isNotEmpty ? (seasons.first.se ?? 1) : 1);

      initializeTrailerPlayer();
    } catch (e) {
      Get.snackbar('Error', 'Failed to load details: ${e.toString()}');
    } finally {
      isLoading(false);
      // Trigger animation and focus after loading is complete
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!isClosed) isContentLoaded.value = true;
      });
      Future.delayed(const Duration(milliseconds: 650), () {
        if (!isClosed) playButtonFocusNode.requestFocus();
      });
      if (_resumeOnLoad) {
        _resumeOnLoad = false;
        Future.delayed(const Duration(milliseconds: 300), () {
          if (isClosed) return;
          hasSavedProgress.value ? continuePlayback() : playFromBeginning();
        });
      }
    }
  }

  // The trailer controller from the moment it is created — including while it
  // is still initializing, before it lands in [videoPlayerController]. TV
  // boxes have one hardware video decoder, so a trailer that finishes
  // initializing after Play was pressed would make the movie fail to start.
  VideoPlayerController? _trailer;
  // False while playback is starting or the player is open.
  bool _trailerAllowed = true;

  void _disposeTrailer() {
    showTrailer.value = false;
    _trailer?.dispose();
    _trailer = null;
    videoPlayerController.value = null;
  }

  void initializeTrailerPlayer() {
    // Big screens only: a muted background trailer is noise on a phone.
    final isBigScreen = Get.width >= 900;
    final trailerUrl = subject.value?.trailer?.videoAddress?.url;

    // Continue Watching resumes straight into the player: no trailer at all.
    if (_resumeOnLoad || !_trailerAllowed) return;
    if (isBigScreen && trailerUrl != null && trailerUrl.isNotEmpty) {
      try {
        _disposeTrailer();
        final controller = VideoPlayerController.networkUrl(Uri.parse(trailerUrl));
        _trailer = controller;
        controller.initialize().then((_) {
          // Superseded (disposed for playback, another title, or page closed).
          // (_disposeTrailer already disposed it if it is no longer _trailer.)
          if (_trailer != controller) return;
          if (isClosed || !_trailerAllowed) {
            _disposeTrailer();
            return;
          }
          videoPlayerController.value = controller;
          Future.delayed(const Duration(seconds: 2), () {
            if (videoPlayerController.value == controller && !isClosed && !isStarting.value) {
              showTrailer.value = true;
              controller.play();
            }
          });
        }).catchError((e) {
          debugPrint("Trailer unavailable: $e");
        });
        controller.setLooping(true);
        controller.setVolume(0.0);
      } catch (e) {
        debugPrint("Error initializing background video player: $e");
      }
    }
  }

  // --- Continue Watching Logic ---

  void _loadProgress() {
    final id = subject.value?.subjectId;
    if (id == null) return;
    final progressData = _storage.read('progress_$id');
    if (progressData is Map) {
      lastPlayedSeason.value = progressData['season'];
      lastPlayedEpisode.value = progressData['episode'];
      lastPlayedPosition.value = Duration(seconds: progressData['position'] ?? 0);
      hasSavedProgress.value = true;
    } else {
      lastPlayedSeason.value = null;
      lastPlayedEpisode.value = null;
      lastPlayedPosition.value = Duration.zero;
      hasSavedProgress.value = false;
    }
    remainingSec.value = UserData.remainingSec(id);
    progressFraction.value = UserData.progressFraction(id);
  }

  void continuePlayback() {
    if (!hasSavedProgress.value ||
        lastPlayedSeason.value == null ||
        lastPlayedEpisode.value == null) {
      return;
    }
    _playVideo(
      season: lastPlayedSeason.value!,
      episode: lastPlayedEpisode.value!,
      startAt: lastPlayedPosition.value,
    );
  }

  void playFromBeginning() {
    if (resource.value == null || (resource.value!.seasons?.isEmpty ?? true)) {
      return;
    }
    final firstSeason = resource.value!.seasons![0].se ?? 0;
    _playVideo(season: firstSeason, episode: firstSeason == 0 ? 0 : 1);
  }

  /// Starts the saved movie / episode over from 0:00.
  void restartSaved() {
    if (lastPlayedSeason.value == null || lastPlayedEpisode.value == null) return;
    _playVideo(season: lastPlayedSeason.value!, episode: lastPlayedEpisode.value!);
  }

  /// Plays one episode; resumes it when it's the saved one.
  void playEpisode(int season, int episode) {
    final saved = hasSavedProgress.value &&
        lastPlayedSeason.value == season &&
        lastPlayedEpisode.value == episode;
    _playVideo(
      season: season,
      episode: episode,
      startAt: saved ? lastPlayedPosition.value : Duration.zero,
    );
  }

  Future<void> _playVideo(
      {required int season,
      required int episode,
      Duration startAt = Duration.zero}) async {
    if (isLoading.value || isStarting.value) return;

    // Block the trailer from here on, even one still initializing (see
    // [_trailer]); it comes back when the player closes.
    _trailerAllowed = false;
    _disposeTrailer();
    try {
      isStarting.value = true;
      // Downloaded: play from the device, no network needed.
      final offline = DownloadService.to.offlineStream(subject.value?.subjectId, season, episode);
      final response = offline != null
          ? {
              'data': {
                'streams': [offline.toJson()]
              }
            }
          : await apiProvider.fetchPlaybackInfoWithCookieManager(
        subject: subject.value!,
        season: '$season',
        episode: '$episode',
      );

      if (response != null &&
          response['data'] != null &&
          response['data']['streams'] is List) {
        final streamsData = response['data']['streams'] as List;

        if (streamsData.isNotEmpty) {
          List<StreamInfo> streamInfo = streamsData
              .map((streamJson) =>
                  StreamInfo.fromJson(streamJson as Map<String, dynamic>))
              .toList();

          isStarting.value = false;
          await Get.to(
            () => const VideoPlayerView(),
            binding: VideoPlayerBinding(),
            arguments: {
              'subject': subject.value,
              'resource': resource.value,
              'streams': streamInfo,
              'season': season,
              'episode': episode,
              'position': startAt,
            },
          );
          _loadProgress();
          if (lastPlayedSeason.value != null) {
            selectedSeason.value = lastPlayedSeason.value!;
          }
        } else {
          Get.snackbar(
            'No Streams Found',
            'This episode is currently unavailable.',
            snackPosition: SnackPosition.BOTTOM,
          );
        }
      } else {
        Get.snackbar(
          'Error',
          'Failed to retrieve episode information.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      Get.snackbar(
        'An Error Occurred',
        'Please check your connection and try again.',
        snackPosition: SnackPosition.BOTTOM,
      );
      debugPrint('Error loading episode: $e');
    } finally {
      isStarting.value = false;
      // Player closed (or never opened): the background trailer may return.
      _trailerAllowed = true;
      if (!isClosed) initializeTrailerPlayer();
      // Ensure focus is returned to the button after coming back.
      if (!isClosed) playButtonFocusNode.requestFocus();
    }
  }
}
