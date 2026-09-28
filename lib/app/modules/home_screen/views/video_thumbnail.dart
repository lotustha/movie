import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app_theme.dart';
import '../../../model/subject_list.dart';
import '../../Subject_Detail/bindings/subject_detail_binding.dart';
import '../../Subject_Detail/views/subject_detail_view.dart';

class VideoThumbnail extends StatefulWidget {
  final Subject subject;

  /// 1-based position in a ranking list. When set, a rank badge is drawn on
  /// the poster (top 3 get the brand accent). Null = no badge.
  final int? rank;

  const VideoThumbnail({
    super.key,
    required this.subject,
    this.rank,
  });

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
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

  String getYear(String? date) {
    if (date != null && date.length >= 4) {
      return date.substring(0, 4);
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final coverUrl = widget.subject.cover?.url;
    final String imageUrl = (coverUrl != null && coverUrl.isNotEmpty)
        ? "$coverUrl?x-oss-process=image/resize%2Cw_200"
        : 'https://placehold.co/300x400/222/EEE?text=No+Image';
    final year = getYear(widget.subject.releaseDate);
    final country = widget.subject.countryName ?? '';

    final List<String> infoParts = [];
    if (country.isNotEmpty) infoParts.add(country);
    if (year.isNotEmpty) infoParts.add(year);

    final infoText = infoParts.join(' • ');

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
              () => const SubjectDetailView(),
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
            color: _isFocused
                ? Get.theme.colorScheme.primary
                : Colors.transparent,
            width: 3,
          ),
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,

                      placeholder: (_, __) =>
                      const ColoredBox(color: Colors.black26),

                      errorWidget: (_, __, ___) =>
                      const Center(child: Icon(Icons.broken_image)),
                    ),
                    if (widget.rank != null)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: _RankBadge(rank: widget.rank!),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Title
            Text(
              widget.subject.title ?? 'Untitled',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Get.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 4),

            // Info
            Text(
              infoText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Get.textTheme.bodySmall?.copyWith(
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A ranking badge drawn on the top-left of a poster. The top three ranks
/// carry the brand gradient; the rest use a neutral scrim so the number stays
/// legible without competing with the artwork.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    final bool isTop = rank <= 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        gradient: isTop ? kBrandGradient : null,
        color: isTop ? null : Colors.black.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          bottomRight: Radius.circular(10),
        ),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          color: Colors.white,
          fontSize: isTop ? 15 : 12,
          fontWeight: FontWeight.w800,
          height: 1.0,
          shadows: const [
            Shadow(color: Colors.black45, blurRadius: 2, offset: Offset(0, 1)),
          ],
        ),
      ),
    );
  }
}
