import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:movie/app/data/api_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../model/StreamInfo.dart';
import '../../../model/subject_list.dart';
import '../../video_player/bindings/video_player_binding.dart';
import '../../video_player/views/video_player_view.dart';

class SubjectDetailController extends GetxController {
  // --- Observables ---
  final Rx<Subject?> subject = Subject().obs;
  final Rx<Resource?> resource = Resource().obs;
  final isLoading = true.obs;
  final RxList<Subject> subjectsList = <Subject>[].obs;

  // --- Trailer Player ---
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

  // --- Injected Dependencies ---
  final ApiProvider apiProvider = Get.find<ApiProvider>();

  @override
  void onInit() {
    super.onInit();
    playButtonFocusNode = FocusNode();
    final String subjectId = Get.arguments as String? ?? '';
    fetchSubjectDetails(subjectId);
  }

  @override
  void onClose() {
    videoPlayerController.value?.dispose();
    playButtonFocusNode.dispose();
    super.onClose();
  }

  Future<void> fetchSubjectDetails(String subjectId) async {
    try {
      isLoading(true);
      isContentLoaded.value = false; // Reset animation state
      hasSavedProgress.value = false;

      final tempSubject = await apiProvider.fetchSubject(subjectId);
      subject.value = Subject.fromJson(tempSubject['subject']);
      resource.value = Resource.fromJson(tempSubject['resource']);

      initializeTrailerPlayer();
      searchLanguage();
      _loadProgress();
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
    }
  }

  void initializeTrailerPlayer() {
    final isTv = Get.width > 960;
    final trailerUrl = subject.value?.trailer?.videoAddress?.url;

    if (isTv && trailerUrl != null && trailerUrl.isNotEmpty) {
      try {
        final controller =
        VideoPlayerController.networkUrl(Uri.parse(trailerUrl));
        controller.initialize().then((_) {
          videoPlayerController.value = controller;
          Future.delayed(const Duration(seconds: 2), () {
            if (videoPlayerController.value != null && !isClosed) {
              showTrailer.value = true;
              videoPlayerController.value?.play();
            }
          });
        });
        controller.setLooping(true);
        controller.setVolume(0.0);
      } catch (e) {
        debugPrint("Error initializing background video player: $e");
      }
    }
  }

  Future<void> searchLanguage() async {
    if (subject.value?.title == null) return;
    String keyword =
    subject.value!.title!.replaceAll(RegExp(r"\s*\[.*?\]"), "");
    var data = await apiProvider.searchMovies(keyword);

    List<Subject> tempSubjects = (data as List)
        .map((e) => Subject.fromJson(e as Map<String, dynamic>))
        .toList();

    subjectsList.assignAll(
      tempSubjects
          .where((e) =>
      e.imdbRatingValue == subject.value?.imdbRatingValue &&
          e.title!.contains(keyword))
          .toList(),
    );
  }

  // --- Continue Watching Logic ---

  void _loadProgress() {
    if (subject.value?.subjectId == null) return;
    final progressData = _storage.read('progress_${subject.value!.subjectId}');
    if (progressData is Map) {
      lastPlayedSeason.value = progressData['season'];
      lastPlayedEpisode.value = progressData['episode'];
      lastPlayedPosition.value =
          Duration(seconds: progressData['position'] ?? 0);
      hasSavedProgress.value = true;
    } else {
      hasSavedProgress.value = false;
    }
  }

  void continuePlayback() {
    if (!hasSavedProgress.value ||
        lastPlayedSeason.value == null ||
        lastPlayedEpisode.value == null) return;
    _playVideo(
      season: lastPlayedSeason.value!,
      episode: lastPlayedEpisode.value!,
      startAt: lastPlayedPosition.value,
    );
  }

  void playFromBeginning() {
    if (resource.value == null || (resource.value!.seasons?.isEmpty ?? true))
      return;
    final firstSeason = resource.value!.seasons![0].se ?? 0;
    int episode=1;
    if (firstSeason == 0){
      episode=0;
    }
    _playVideo(season: firstSeason, episode: episode);
  }

  Future<void> _playVideo(
      {required int season,
        required int episode,
        Duration startAt = Duration.zero}) async {
    if (isLoading.value) return;

    try {
      isLoading.value = true;
      final response = await apiProvider.fetchPlaybackInfoWithCookieManager(
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
      isLoading.value = false;
      // Ensure focus is returned to the button after coming back.
      playButtonFocusNode.requestFocus();
    }
  }
}

