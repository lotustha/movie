import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../constants.dart'; // Assuming your color constants are here
import '../controllers/season_view_controller.dart';

class SeasonView extends GetView<SeasonViewController> {
  const SeasonView({super.key});

  @override
  Widget build(BuildContext context) {
    // We use a Stack to layer the background image, a gradient overlay, and the content
    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: Stack(
        children: [
          _buildBackground(),
          _buildGradientOverlay(),
          _buildContentView(context),
        ],
      ),
    );
  }

  /// Builds the blurred background image for an immersive feel.
  Widget _buildBackground() {
    // Use the subject's poster as the background
    final imageUrl = controller.subject.cover?.url ?? '';
    return Container(
      decoration: BoxDecoration(
        image: imageUrl.isNotEmpty
            ? DecorationImage(
          image: NetworkImage(imageUrl),
          fit: BoxFit.cover,
        )
            : null,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(color: Colors.black.withOpacity(0.3)),
      ),
    );
  }

  /// Adds a gradient overlay to ensure text is always readable over the background.
  Widget _buildGradientOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kBackgroundColor.withOpacity(0.95),
            kBackgroundColor.withOpacity(0.8),
            kBackgroundColor.withOpacity(0.95),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
    );
  }

  /// Builds the main UI content: title and the two-panel list view.
  Widget _buildContentView(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show Title
            Text(
              controller.subject.title ?? 'Seasons & Episodes',
              style: const TextStyle(
                color: kPrimaryTextColor,
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            // Main content area with Seasons and Episodes
            Expanded(
              child: Row(
                children: [
                  // --- Seasons List ---
                  Expanded(
                    flex: 2,
                    child: _buildSeasonsList(),
                  ),
                  const SizedBox(width: 24),
                  // --- Episodes List ---
                  Expanded(
                    flex: 4,
                    child: _buildEpisodesList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the list of seasons.
  Widget _buildSeasonsList() {
    return ListView.builder(
      itemCount: controller.resource.seasons?.length ?? 0,
      itemBuilder: (context, index) {
        final season = controller.resource.seasons?[index];
        if (season == null) return const SizedBox.shrink();

        return Obx(() {
          return _SeasonItem(
            label: 'Season ${season.se}',
            isSelected: controller.selectedSeasonIndex.value == index,
            // Automatically focus the first item
            autofocus: index == 0,
            onTap: () {
              controller.selectedSeasonIndex.value = index;
              controller.selectedEpisodeIndex.value = -1; // Reset episode selection
            },
          );
        });
      },
    );
  }

  /// Builds the list of episodes for the currently selected season.
  Widget _buildEpisodesList() {
    return Obx(() {
      final selectedSeasonIndex = controller.selectedSeasonIndex.value;
      if (controller.resource.seasons == null ||
          selectedSeasonIndex >= controller.resource.seasons!.length) {
        return _buildEmptyState("Select a season to see episodes.");
      }

      final episodeCount =
          controller.resource.seasons?[selectedSeasonIndex].maxEp ?? 0;
      if (episodeCount == 0) {
        return _buildEmptyState("No episodes available for this season.");
      }

      return ListView.builder(
        itemCount: episodeCount,
        itemBuilder: (context, index) {
          // Rebuilds the item when selection changes
          return Obx(() {
            final isSelected = controller.selectedEpisodeIndex.value == index;
            return _EpisodeItem(
              label: 'Episode ${index + 1}',
              isSelected: isSelected,
              onTap: () {
                controller.selectedEpisodeIndex.value = index;
                controller.loadEpisode();
              },
            );
          });
        },
      );
    });
  }

  /// A centered text widget for empty or initial states.
  Widget _buildEmptyState(String message) {
    return Center(
      child: Text(
        message,
        style: const TextStyle(color: kSecondaryTextColor, fontSize: 18),
      ),
    );
  }
}

// --- TV-Optimized Season Item Widget ---
class _SeasonItem extends StatefulWidget {
  final String label;
  final bool isSelected;
  final bool autofocus;
  final VoidCallback onTap;

  const _SeasonItem({
    required this.label,
    required this.isSelected,
    this.autofocus = false,
    required this.onTap,
  });

  @override
  State<_SeasonItem> createState() => _SeasonItemState();
}

class _SeasonItemState extends State<_SeasonItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final bool isHighlighted = widget.isSelected || _isFocused;
    final Color textColor = isHighlighted ? kPrimaryTextColor : kSecondaryTextColor;
    final Color backgroundColor = widget.isSelected ? kAccentColor.withOpacity(0.9) : kSurfaceColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (hasFocus) {
          setState(() => _isFocused = hasFocus);
          // Auto-scroll to keep the focused item visible
          if (hasFocus) {
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 300),
              alignment: 0.5, // Center the item in the viewport
            );
          }
        },
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedScale(
            scale: _isFocused ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: _isFocused
                    ? Border.all(color: kPrimaryTextColor, width: 2)
                    : Border.all(color: Colors.transparent, width: 2),
                boxShadow: [
                  if (_isFocused)
                    BoxShadow(
                      color: kAccentColor.withOpacity(0.5),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                ],
              ),
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- TV-Optimized Episode Item Widget ---
class _EpisodeItem extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _EpisodeItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_EpisodeItem> createState() => _EpisodeItemState();
}

class _EpisodeItemState extends State<_EpisodeItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final bool isHighlighted = widget.isSelected || _isFocused;
    final Color backgroundColor = widget.isSelected
        ? kAccentColor
        : (_isFocused ? kAccentColor.withOpacity(0.7) : kSurfaceColor);
    final Color textColor = isHighlighted ? kPrimaryTextColor : kSecondaryTextColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Focus(
        onFocusChange: (hasFocus) {
          setState(() => _isFocused = hasFocus);
          if (hasFocus) {
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 300),
              alignment: 0.5,
            );
          }
        },
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedScale(
            scale: _isFocused ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  if (_isFocused)
                    BoxShadow(
                      color: kAccentColor.withOpacity(0.6),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    widget.isSelected ? Icons.play_circle_filled : Icons.play_circle_outline,
                    color: textColor,
                    size: 28,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 18,
                      color: textColor,
                      fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
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