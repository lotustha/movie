import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../../app_theme.dart';
import '../../../../data/user_data.dart';
import '../../../../model/subject_list.dart';
import '../../../Subject_Detail/bindings/subject_detail_binding.dart';
import '../../../Subject_Detail/views/subject_detail_view.dart';
import '../../controllers/home_screen_controller.dart';

/// Shared pieces of the phone UI: poster tiles, the preview sheet, meta line.

const Color kCard = Color(0xFF1C1C24);
const Color kInk = Color(0xFF111114);

/// Asks the phone shell to switch tab (e.g. a top-bar search icon → Search).
final ValueNotifier<int?> mobileTabRequest = ValueNotifier(null);
const int kSearchTab = 2;
void openSearchTab() => mobileTabRequest.value = kSearchTab;

/// Bumped to stop inline trailers (tab switch, navigation away).
final ValueNotifier<int> inlineMediaStop = ValueNotifier(0);
void stopInlineMedia() => inlineMediaStop.value++;

/// Opens a title's detail page; with [resume] it starts playback right away
/// (resuming saved progress when there is any).
Future<void> openDetail(Subject subject, {bool resume = false}) async {
  if (subject.subjectId == null) return;
  stopInlineMedia();
  await Get.to(
    () => const SubjectDetailView(),
    transition: Transition.rightToLeft,
    binding: SubjectDetailBinding(),
    arguments: {'id': subject.subjectId, 'resume': resume},
    preventDuplicates: false,
  );
  // Playback / My List may have changed while away.
  if (Get.isRegistered<HomeScreenController>()) {
    Get.find<HomeScreenController>().refreshUserRows();
  }
}

/// Resized poster URL; MovieBox's CDN resizes on the fly.
String posterUrl(String url, {int width = 240}) =>
    url.contains('?') ? url : '$url?x-oss-process=image/resize%2Cw_$width';

/// Drops a dub listed next to its original ("Don't Be Shy [English]" and
/// "Don't Be Shy"), keeping the first of each title.
List<Subject> dedupeTitles(Iterable<Subject> all) {
  final seen = <String>{};
  return [
    for (final s in all)
      if (seen.add((s.title ?? s.subjectId ?? '')
          .replaceAll(RegExp(r'\s*\[[^\]]*\]'), '')
          .trim()
          .toLowerCase()))
        s,
  ];
}

/// The subject kinds the home filter chips can narrow to.
enum MediaFilter { all, shows, movies }

extension MediaFilterMatch on MediaFilter {
  bool matches(Subject s) => switch (this) {
        MediaFilter.all => true,
        MediaFilter.shows => s.subjectType == 2,
        MediaFilter.movies => s.subjectType == 1,
      };
}

/// ★ rating · year · Movie/TV · genres — only the parts that exist.
class MetaLine extends StatelessWidget {
  const MetaLine({super.key, required this.subject, this.fontSize = 13, this.genres = 3});
  final Subject subject;
  final double fontSize;
  final int genres;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if ((subject.releaseDate?.length ?? 0) >= 4) subject.releaseDate!.substring(0, 4),
      if (subject.subjectType == 1) 'Movie',
      if (subject.subjectType == 2) 'TV',
      if (genres > 0 && (subject.genre ?? '').isNotEmpty)
        subject.genre!.split(',').take(genres).join(', '),
    ];
    final rating = subject.imdbRatingValue ?? '';
    final hasRating = (double.tryParse(rating) ?? 0) > 0; // "0" = unrated
    return Row(
      children: [
        if (hasRating) ...[
          Icon(Icons.star_rounded, color: const Color(0xFFF5C518), size: fontSize + 3),
          const SizedBox(width: 3),
          Text(rating,
              style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w700)),
          if (parts.isNotEmpty) const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(parts.join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white70, fontSize: fontSize)),
        ),
      ],
    );
  }
}

/// A portrait poster tile; tapping opens the Netflix-style preview sheet.
class PosterTile extends StatelessWidget {
  const PosterTile({
    super.key,
    required this.subject,
    this.width = 112,
    this.height = 168,
    this.progress = 0,
    this.resume = false,
    this.onTap,
  });

  final Subject subject;
  final double width;
  final double height;
  final double progress;
  final bool resume;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final url = subject.cover?.url;
    return Semantics(
      button: true,
      label: subject.title,
      child: Material(
        color: kCard,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap ?? () => showPreviewSheet(subject, resume: resume),
          onLongPress: () => showPreviewSheet(subject, resume: resume),
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url != null && url.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: posterUrl(url),
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 200),
                    placeholder: (_, _) => const SizedBox.shrink(),
                    errorWidget: (_, _, _) => PosterFallback(title: subject.title),
                  )
                else
                  PosterFallback(title: subject.title),
                if (progress > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(kBrandRed),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PosterFallback extends StatelessWidget {
  const PosterFallback({super.key, this.title});
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(title ?? '',
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ),
    );
  }
}

class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key, this.width = 112});
  final double width;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, _) => Container(
        width: width,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

/// Netflix's tap-a-poster sheet: poster, title, meta, synopsis, then Play,
/// My List and a link to the full page.
Future<void> showPreviewSheet(Subject subject, {bool resume = false}) {
  return Get.bottomSheet(
    _PreviewSheet(subject: subject, resume: resume),
    backgroundColor: const Color(0xFF1F1F27),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
  );
}

class _PreviewSheet extends StatefulWidget {
  const _PreviewSheet({required this.subject, required this.resume});
  final Subject subject;
  final bool resume;

  @override
  State<_PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends State<_PreviewSheet> {
  late bool _inList = UserData.inMyList(widget.subject.subjectId);

  void _toggleList() {
    setState(() => _inList = UserData.toggleMyList(widget.subject));
    if (Get.isRegistered<HomeScreenController>()) {
      Get.find<HomeScreenController>().refreshUserRows();
    }
  }

  void _go({required bool play}) {
    Get.back();
    openDetail(widget.subject, resume: play);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.subject;
    final url = s.cover?.url;
    final remaining = UserData.remainingSec(s.subjectId);
    final progress = UserData.progressFraction(s.subjectId);
    final upcoming = s.hasResource == false;
    final playLabel = progress > 0 ? 'Resume' : 'Play';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 96,
                    height: 144,
                    child: url == null || url.isEmpty
                        ? PosterFallback(title: s.title)
                        : CachedNetworkImage(
                            imageUrl: posterUrl(url),
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => PosterFallback(title: s.title),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.title ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      MetaLine(subject: s, fontSize: 12, genres: 2),
                      if ((s.description ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(s.description!.trim(),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35)),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: Get.back,
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  if (!upcoming)
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: () => _go(play: true),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: kInk,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 26),
                          label: Text(playLabel),
                        ),
                      ),
                    ),
                  _SheetAction(
                    icon: _inList ? Icons.check_rounded : Icons.add_rounded,
                    label: 'My List',
                    onTap: _toggleList,
                  ),
                  _SheetAction(
                    icon: Icons.info_outline_rounded,
                    label: upcoming ? 'Details' : 'Episodes & Info',
                    onTap: () => _go(play: false),
                  ),
                ],
              ),
            ),
            if (progress > 0 && remaining != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(kBrandRed),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(_remainingLabel(remaining),
                        style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _remainingLabel(int sec) {
  final m = (sec / 60).ceil();
  if (m < 60) return '${m}m left';
  return '${m ~/ 60}h ${m % 60}m left';
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 24),
                const SizedBox(height: 3),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Row header used by every rail on the phone.
class RailTitle extends StatelessWidget {
  const RailTitle(this.title, {super.key, this.onMore, this.action});
  final String title;
  final VoidCallback? onMore;
  /// Optional trailing text button (e.g. "Clear").
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Text(title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: action != null
          ? Row(children: [Expanded(child: text), action!])
          : onMore == null
          ? text
          : InkWell(
              onTap: onMore,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Flexible(child: text),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                  ],
                ),
              ),
            ),
    );
  }
}
