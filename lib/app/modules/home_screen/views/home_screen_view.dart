import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:movie/app/modules/home_screen/views/side_nav.dart';
import '../controllers/home_screen_controller.dart';
import 'content_area.dart';

class HomeScreenView extends GetView<HomeScreenController> {
  const HomeScreenView({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Define the breakpoint for mobile/desktop layout
        bool isMobile = constraints.maxWidth < 768;

        if (isMobile) {
          // Build the mobile layout with a toggleable overlay sidebar
          return buildMobileLayout();
        } else {
          // Build the desktop/TV layout with a permanently visible sidebar
          return buildDesktopLayout();
        }
      },
    );
  }

  // Widget for Tablet and TV view
  Widget buildDesktopLayout() {
    return const Scaffold(
      body: Row(
        children: [
          // Sidebar is permanently visible
          SideNavigationBar(),
          // Content takes the remaining space
          Expanded(
            child: ContentArea(),
          ),
        ],
      ),
    );
  }

  // Widget for Mobile view
  Widget buildMobileLayout() {
    return Scaffold(
      // AppBar with a toggle icon only for mobile
      appBar: AppBar(
        title: Obx(() => Text(controller.selectedSubjectName.value)),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: controller.toggleSideNav, // Simple toggle
        ),
      ),
      body: GestureDetector(
        // Swipe gestures to open/close the navigation
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! > 200) {
            controller.openSideNav();
          } else if (details.primaryVelocity != null && details.primaryVelocity! < -200) {
            controller.closeSideNav();
          }
        },
        child: Stack(
          children: [
            // Main content area
            const ContentArea(),

            // Scrim (dark overlay) that appears over the content when nav is open
            Obx(() {
              if (!controller.isSideNavVisible.value) return const SizedBox.shrink();
              return GestureDetector(
                onTap: controller.closeSideNav, // Tap overlay to close
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                ),
              );
            }),

            // The side navigation bar, animated
            Obx(() {
              return AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                left: controller.isSideNavVisible.value ? 0 : -250, // Animate from off-screen
                top: 0,
                bottom: 0,
                width: 250, // Give it a fixed width
                child: const SideNavigationBar(),
              );
            }),
          ],
        ),
      ),
    );
  }
}