import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import '../../../model/subject_list.dart';
import '../controllers/home_screen_controller.dart';
import 'video_thumbnail.dart';

class ContentArea extends StatelessWidget {
  const ContentArea({super.key});

  @override
  Widget build(BuildContext context) {
    // The controller can be found directly within the build method.
    final HomeScreenController controller = Get.find<HomeScreenController>();

    return SafeArea(
      child: Container(
          color: Get.theme.scaffoldBackgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: _buildSubjectContent(controller),
      ),
    );
  }

  // Builds the content grid for a selected subject, with API data.
  Widget _buildSubjectContent(HomeScreenController controller) {
    return Obx(() {
      // Show a centered loader only on the very first load for a category.
      if (controller.isLoading.value && controller.subjectsList.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }

      if (controller.subjectsList.isEmpty) {
        // If the list is empty after loading, show a "not found" message.
        return Center(
          child: Text(
            'No results found.',
            style: Get.textTheme.headlineSmall,
          ),
        );
      }

      // The main content grid, now wrapped in the SmartRefresher.
      return SmartRefresher(
        controller: controller.refreshController,
        enablePullUp: true,
        // Enable infinite scrolling.
        onRefresh: controller.refresh,
        onLoading: controller.loadMore,
        header: const WaterDropHeader(),
        // Customizable header.
        footer: CustomFooter(
          builder: (BuildContext context, LoadStatus? mode) {
            Widget body;
            if (mode == LoadStatus.idle) {
              body = const Text("pull up load");
            } else if (mode == LoadStatus.loading) {
              body = const CircularProgressIndicator();
            } else if (mode == LoadStatus.failed) {
              body = const Text("Load Failed!Click retry!");
            } else if (mode == LoadStatus.canLoading) {
              body = const Text("release to load more");
            } else {
              body = const Text("No more Data");
            }
            return SizedBox(
              height: 55.0,
              child: Center(child: body),
            );
          },
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            // Scale the ranked grid from phone (2-up) to TV (6-up).
            final crossAxisCount = w < 600
                ? 2
                : w < 900
                    ? 4
                    : w < 1300
                        ? 5
                        : 6;
            final spacing = w < 600 ? 12.0 : 20.0;
            return GridView.builder(
              controller: controller.scrollController,
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio:
                    145 / 258, // Adjusted for portrait image + text.
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
              ),
              itemCount: controller.subjectsList.length,
              itemBuilder: (context, index) {
                final Subject subject = controller.subjectsList[index];
                // Ranked order: 1-based position drives the poster badge.
                return VideoThumbnail(
                  subject: subject,
                  rank: index + 1,
                );
              },
            );
          },
        ),
      );
    });
  }


}

