import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../data/user_data.dart';
import '../../../model/operating_list_model.dart';
import '../../../model/subject_list.dart';
import '../../Subject_Detail/bindings/subject_detail_binding.dart';
import '../../Subject_Detail/views/subject_detail_view.dart';
import '../controllers/home_screen_controller.dart';
import 'video_thumbnail.dart';

/// Netflix-style home: a hero billboard followed by horizontal content rows,
/// built from the MovieBox home feed (banner + themed rails).
class NetflixHome extends StatelessWidget {
  const NetflixHome({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<HomeScreenController>();
    final width = MediaQuery.of(context).size.width;
    final bool isTv = width >= 900;

    return Obx(() {
      if (c.isFeedLoading.value && c.homeRows.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (c.homeRows.isEmpty && c.heroSubject.value == null) {
        return _ErrorState(onRetry: c.fetchHomeFeed);
      }
      return RefreshIndicator(
        onRefresh: c.fetchHomeFeed,
        color: Get.theme.colorScheme.primary,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.axis == Axis.vertical) {
              c.feedScrollOffset.value = n.metrics.pixels;
            }
            return false;
          },
          child: Obx(() {
            // Assemble: hero, then personalised rows, then the feed rails.
            final sections = <Widget>[];
            if (c.continueWatching.isNotEmpty) {
              sections.add(_SubjectRow(
                  title: 'Continue Watching',
                  subjects: c.continueWatching.toList(),
                  isTv: isTv,
                  showProgress: true));
            }
            if (c.myList.isNotEmpty) {
              sections.add(_SubjectRow(
                  title: 'My List',
                  subjects: c.myList.toList(),
                  isTv: isTv));
            }
            for (final row in c.homeRows) {
              sections.add(_HomeRow(row: row, isTv: isTv));
            }
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 32),
              itemCount: sections.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return c.heroSubject.value != null
                      ? _Hero(subject: c.heroSubject.value!, isTv: isTv)
                      : const SizedBox(height: 12);
                }
                return sections[index - 1];
              },
            );
          }),
        ),
      );
    });
  }
}

void _openDetail(String? subjectId) {
  if (subjectId == null) return;
  Get.to(
    () => const SubjectDetailView(),
    transition: Transition.rightToLeft,
    binding: SubjectDetailBinding(),
    arguments: subjectId,
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.subject, required this.isTv});
  final Subject subject;
  final bool isTv;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final art = subject.stills?.url ?? subject.cover?.url;
    final height = size.height * (isTv ? 0.6 : 0.52);
    final bg = Get.theme.scaffoldBackgroundColor;
    final primary = Get.theme.colorScheme.primary;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (art != null && art.isNotEmpty)
            CachedNetworkImage(
              imageUrl: art,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 400),
              errorWidget: (_, __, ___) => ColoredBox(color: bg),
            )
          else
            ColoredBox(color: bg),
          // Bottom + left scrims for legibility.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [bg, bg.withValues(alpha: 0.0)],
                stops: const [0.0, 0.85],
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: isTv ? size.width * 0.4 : 24,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  subject.title ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isTv ? 44 : 30,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                _MetaRow(subject: subject),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _HeroButton(
                      label: 'Play',
                      icon: Icons.play_arrow_rounded,
                      filled: true,
                      color: primary,
                      autofocus: isTv,
                      onPressed: () => _openDetail(subject.subjectId),
                    ),
                    const SizedBox(width: 12),
                    _HeroButton(
                      label: 'More Info',
                      icon: Icons.info_outline_rounded,
                      onPressed: () => _openDetail(subject.subjectId),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.subject});
  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];
    if (subject.imdbRatingValue != null &&
        subject.imdbRatingValue!.isNotEmpty) {
      parts.add(Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star, color: Color(0xFFF5C518), size: 15),
        const SizedBox(width: 4),
        Text(subject.imdbRatingValue!,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
      ]));
    }
    void t(String v) => parts.add(Text(v,
        style: const TextStyle(color: Colors.white70, fontSize: 13)));
    if ((subject.releaseDate?.length ?? 0) >= 4) {
      t(subject.releaseDate!.substring(0, 4));
    }
    if (subject.subjectType == 2) t('TV');
    if (subject.subjectType == 1) t('Movie');
    if ((subject.genre ?? '').isNotEmpty) {
      t(subject.genre!.split(',').take(2).join(' · '));
    }
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: parts,
    );
  }
}

class _HeroButton extends StatefulWidget {
  const _HeroButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
    this.color,
    this.autofocus = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;
  final Color? color;
  final bool autofocus;

  @override
  State<_HeroButton> createState() => _HeroButtonState();
}

class _HeroButtonState extends State<_HeroButton> {
  bool _f = false;
  @override
  Widget build(BuildContext context) {
    final bg = _f
        ? Colors.white
        : (widget.filled ? (widget.color ?? Colors.red) : Colors.white24);
    final fg = _f ? Colors.black : Colors.white;
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (v) => setState(() => _f = v),
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: fg, size: 20),
              const SizedBox(width: 8),
              Text(widget.label,
                  style: TextStyle(
                      color: fg, fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled horizontal row backed by a plain [Subject] list (Continue
/// Watching, My List). Optionally shows a watched-progress bar under posters.
class _SubjectRow extends StatelessWidget {
  const _SubjectRow({
    required this.title,
    required this.subjects,
    required this.isTv,
    this.showProgress = false,
  });
  final String title;
  final List<Subject> subjects;
  final bool isTv;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final posterW = isTv ? 158.0 : 124.0;
    final rowH = posterW * 1.5 + 62;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
          SizedBox(
            height: rowH,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              physics: const BouncingScrollPhysics(),
              itemCount: subjects.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final s = subjects[i];
                final frac = showProgress
                    ? UserData.progressFraction(s.subjectId)
                    : 0.0;
                return SizedBox(
                  width: posterW,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: VideoThumbnail(subject: s)),
                      if (showProgress && frac > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: frac,
                              minHeight: 3,
                              backgroundColor: Colors.white24,
                              valueColor: AlwaysStoppedAnimation(
                                  Get.theme.colorScheme.primary),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeRow extends StatelessWidget {
  const _HomeRow({required this.row, required this.isTv});
  final OperatingList row;
  final bool isTv;

  @override
  Widget build(BuildContext context) {
    final posterW = isTv ? 158.0 : 124.0;
    final rowH = posterW * 1.5 + 62; // poster (2:3) + title/info below
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Text(
              row.title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          SizedBox(
            height: rowH,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              physics: const BouncingScrollPhysics(),
              itemCount: row.subjects.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => SizedBox(
                width: posterW,
                child: VideoThumbnail(subject: row.subjects[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.white38),
          const SizedBox(height: 12),
          const Text('Couldn’t load home',
              style: TextStyle(color: Colors.white, fontSize: 18)),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
