import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:movie/app/modules/home_screen/controllers/home_screen_controller.dart';

import '../../../data/trending_list.dart';

class SideNavigationBar extends GetView<HomeScreenController> {
  const SideNavigationBar({super.key});

  // Helper to get an icon based on the category name.
  IconData _getIconForCategory(String categoryName) {
    switch (categoryName.toLowerCase()) {
      case 'trending':
        return Icons.local_fire_department_outlined;
      case 'toplist':
        return Icons.leaderboard_outlined;
      case 'in cinema':
        return Icons.theaters_outlined;
      case 'movie':
        return Icons.movie_outlined;
      case 'western tv':
        return Icons.tv_outlined;
      case 'black drama':
      case 'k-drama':
      case 'c-drama':
        return Icons.theater_comedy_outlined;
      case 'anime':
        return Icons.animation_outlined;
      case 'nollywood':
      case 'bollywood':
      case 'south hindi':
        return Icons.local_movies_outlined;
      case 'animated film':
        return Icons.movie_creation_outlined;
      default:
        return Icons.video_library_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240, // Fixed width for the side panel
      color: const Color(0xFF1a1a1a),
      child: Column(
        children: [
          // A header for the side panel.
          SizedBox(
            height: 80,
            child: Center(
              child: Text(
                'Noonflix',
                style: Get.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold,color: Colors.deepPurpleAccent),
              ),
            ),
          ),
          const Divider(height: 1),
          // Use Expanded and ListView to make the menu scrollable.
          Expanded(
            child: Obx(
                  () => ListView(
                padding: const EdgeInsets.all(10), // Padding around the list
                children:
                TrendingList.trendingList.asMap().entries.map((entry) {
                  final item = entry.value;
                  final bool isSelected = controller.selectedSubjectId.value == item.id;
                  return _FocusableMenuItem(
                    icon: _getIconForCategory(item.name ?? ''),
                    title: item.name ?? '',
                    isSelected: isSelected,
                    // When the side nav opens, autofocus will be set on the selected item.
                    autofocus: isSelected,
                    onTap: () {
                      controller.updateSelectedSubject(
                          item.id ?? '', item.name ?? '');
                      controller.closeSideNav();
                    },
                    // This new callback updates the content when an item receives focus.
                    onFocus: () {
                      controller.updateSelectedSubject(
                          item.id ?? '', item.name ?? '');
                    },
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// A stateful widget to create menu items that can manage their own focus state.
class _FocusableMenuItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool isSelected;
  final bool autofocus;
  final VoidCallback onTap;
  // A new callback to handle focus changes, separate from tap events.
  final VoidCallback onFocus;

  const _FocusableMenuItem({
    required this.icon,
    required this.title,
    required this.isSelected,
    this.autofocus = false,
    required this.onTap,
    required this.onFocus,
  });

  @override
  __FocusableMenuItemState createState() => __FocusableMenuItemState();
}

class __FocusableMenuItemState extends State<_FocusableMenuItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    // Determine colors based on selection and focus state.
    final Color backgroundColor = widget.isSelected
        ? Get.theme.colorScheme.primary
        : _isFocused
        ? Colors.white.withOpacity(0.1) // Highlight for focused items
        : Colors.transparent;
    final Color contentColor = widget.isSelected ? Colors.white : Colors.white70;
    final FontWeight fontWeight =
    widget.isSelected || _isFocused ? FontWeight.bold : FontWeight.normal;

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (hasFocus) {
        setState(() {
          _isFocused = hasFocus;
        });
        // When a new item gets focus (and it's not already the selected one),
        // trigger the onFocus callback to update the content in the background.
        if (hasFocus && !widget.isSelected) {
          widget.onFocus();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  Icon(widget.icon, color: contentColor),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 16,
                        color: contentColor,
                        fontWeight: fontWeight,
                      ),
                    ),
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
