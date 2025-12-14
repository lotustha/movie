import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:movie/app/modules/video_player/bindings/video_player_binding.dart';
import 'package:movie/app/modules/video_player/views/video_player_view.dart';

import '../../../data/api_provider.dart';
import '../../../model/StreamInfo.dart';
import '../../../model/subject_list.dart';

class SeasonViewController extends GetxController {
  // State variables
  final Subject subject = Get.arguments[0];
  final ApiProvider apiProvider = Get.find<ApiProvider>();
  final RxInt selectedSeasonIndex = 0.obs;
  final RxInt selectedEpisodeIndex = (-1).obs; // Start with -1 to have no initial selection
  final RxBool isLoading = false.obs;
  final RxList<StreamInfo> streamInfo = <StreamInfo>[].obs;
  final Resource resource = Get.arguments[1];

  /// Loads the stream information for a selected episode and navigates to the player.
  ///
  /// This function displays a loading indicator, fetches playback data from the API,
  /// handles success and error cases, and ensures the loading indicator is dismissed.
  Future<void> loadEpisode() async {
    // Prevent multiple simultaneous requests
    if (isLoading.value) return;

    try {
      isLoading.value = true;
      // Show a non-dismissible loading dialog
      Get.dialog(
        const Center(child: CircularProgressIndicator()),
        barrierDismissible: false,
      );

      final response = await apiProvider.fetchPlaybackInfoWithCookieManager(
        subject: subject,
        season: '${selectedSeasonIndex.value + 1}',
        episode: '${selectedEpisodeIndex.value + 1}',
      );

      // Check for a valid response structure
      if (response != null &&
          response['data'] != null &&
          response['data']['streams'] is List) {
        final streamsData = response['data']['streams'] as List;

        if (streamsData.isNotEmpty) {
          // Safely parse the stream data into the StreamInfo model list
          streamInfo.value = streamsData
              .map((streamJson) => StreamInfo.fromJson(streamJson as Map<String, dynamic>))
              .toList();

          // Close the loading dialog before navigating
          if (Get.isDialogOpen ?? false) Get.back();

          Get.to(
                () => VideoPlayerView(),
            binding: VideoPlayerBinding(),
            arguments: {'subject': subject, 'resource': resource, 'streams': streamInfo, 'season': selectedSeasonIndex.value + 1, 'episode': selectedEpisodeIndex.value + 1},
          );
        } else {
          // Handle case where streams are empty
          if (Get.isDialogOpen ?? false) Get.back();
          Get.snackbar(
            'No Streams Found',
            'This episode is currently unavailable.',
            snackPosition: SnackPosition.BOTTOM,
          );
        }
      } else {
        // Handle invalid or null response
        if (Get.isDialogOpen ?? false) Get.back();
        Get.snackbar(
          'Error',
          'Failed to retrieve episode information.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      // Handle exceptions during the API call
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar(
        'An Error Occurred',
        'Please check your connection and try again.',
        snackPosition: SnackPosition.BOTTOM,
      );
      // For debugging purposes
      debugPrint('Error loading episode: $e');
    } finally {
      // Ensure loading state is always reset
      isLoading.value = false;
    }
  }
}