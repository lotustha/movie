import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../model/subject_list.dart';
import '../../Subject_Detail/bindings/subject_detail_binding.dart';
import '../../Subject_Detail/views/subject_detail_view.dart';

// You will need to create and import these files for navigation to work.
// import '../../detail/subject_detail_view.dart';
// import '../../detail/subject_detail_binding.dart';

class VideoThumbnail extends StatefulWidget {
  final Subject subject;

  const VideoThumbnail({
    super.key,
    required this.subject,
  });

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  // A FocusNode is used to manage the focus state for TV remote navigation.
  late final FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fallback URL for the placeholder image.
    final String imageUrl = widget.subject.cover?.url ??
        'https://placehold.co/145x200/673AB7/white?text=No+Image';
    String getYear(String? date) {
      if (date != null && date.length >= 4) {
        return date.substring(0, 4);
      }
      return '';
    }

    // Prepare the info string parts to avoid dangling separators like "•"
    final year = getYear(widget.subject.releaseDate);
    final country = widget.subject.countryName ?? '';
    final List<String> infoParts = [];

    if (country.isNotEmpty) infoParts.add(country);
    if (year.isNotEmpty) infoParts.add(year);

    final String infoText = infoParts.join(' • ');
    return InkWell(
      focusNode: _focusNode,
      autofocus: false,
      onFocusChange: (hasFocus) {
        setState(() {
          _isFocused = hasFocus;
        });
      },
      onTap: () {

        Get.to(
              () => SubjectDetailView(),
          transition: Transition.rightToLeft,
          binding: SubjectDetailBinding(),
          arguments: widget.subject.subjectId,
        );
      },
      borderRadius: BorderRadius.circular(12.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(
            color:
            _isFocused ? Get.theme.colorScheme.primary : Colors.transparent,
            width: 3,
          ),
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image container with a fixed aspect ratio.
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                // Use CachedNetworkImage to automatically handle caching.
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  // Display a loading indicator while fetching the image.
                  placeholder: (context, url) =>
                  const Center(child: CircularProgressIndicator()),
                  // Display an error icon if the image fails to load.
                  errorWidget: (context, url, error) =>
                  const Center(child: Icon(Icons.broken_image)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Video title.
            Text(
              widget.subject.title ?? 'Untitled',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Get.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            // Additional video information.
            Text(
              infoText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Get.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

