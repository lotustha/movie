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
          child: Column(
            children: [
              _buildHeader(controller),
              Expanded(
                // Display the API-driven content for the selected category.
                child: _buildSubjectContent(controller),
              ),
            ],
          )),
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
        child: GridView.builder(
          padding: const EdgeInsets.only(top: 16, bottom: 24),
          gridDelegate:  SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: Get.width < 600 ? 2 : 4,
            childAspectRatio:
            145 / 258, // Adjusted for portrait image + text.
            crossAxisSpacing: 20,
            mainAxisSpacing: 20,
          ),
          itemCount: controller.subjectsList.length,
          itemBuilder: (context, index) {
            final Subject subject = controller.subjectsList[index];
            // Display each item using the VideoThumbnail widget.
            return VideoThumbnail(
              subject: subject,
            );
          },
        ),
      );
    });
  }

  // Builds the header with a search button and the live date/time display.
  Widget _buildHeader(HomeScreenController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Obx(() {
            return Text(controller.selectedSubjectName.value, style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 28,
                color: Colors.white
            ),);
          }),
          Spacer(),
          IconButton(
            onPressed: () {
              Get.toNamed('/search');
            },
            icon: const Icon(Icons.search, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Obx(() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  controller.currentTime.value,
                  style: Get.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  controller.currentDate.value,
                  style: Get.textTheme.bodyLarge?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

