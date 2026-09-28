import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../../../data/user_data.dart';
import '../../../../model/subject_list.dart';
import '../../controllers/home_screen_controller.dart';
import 'mobile_common.dart';

enum _Section { comingSoon, everyone, topShows, topMovies }

extension on _Section {
  String get label => switch (this) {
        _Section.comingSoon => '🍿 Coming Soon',
        _Section.everyone => "🔥 Everyone's Watching",
        _Section.topShows => '🔟 Top 10 Shows',
        _Section.topMovies => '🔟 Top 10 Movies',
      };
}

/// Netflix's New & Hot: the feed's Coming Soon list (release date + trailer)
/// and what's popular now, one section at a time behind a chip bar.
class NewHotTab extends StatefulWidget {
  const NewHotTab({super.key});

  @override
  State<NewHotTab> createState() => _NewHotTabState();
}

class _NewHotTabState extends State<NewHotTab> {
  final HomeScreenController c = Get.find<HomeScreenController>();
  final ScrollController _scroll = ScrollController();
  _Section _section = _Section.comingSoon;

  // Only one trailer plays at a time: the id of the card that owns it.
  final ValueNotifier<String?> _playing = ValueNotifier(null);

  @override
  void dispose() {
    _scroll.dispose();
    _playing.dispose();
    super.dispose();
  }

  void _select(_Section s) {
    _playing.value = null;
    setState(() => _section = s);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  List<Subject> _comingSoon() {
    final row = c.homeRows.firstWhereOrNull((r) => r.type == 'APPOINTMENT_LIST');
    final list = dedupeTitles(row?.subjects ?? const <Subject>[]);
    list.sort((a, b) => (a.releaseDate ?? '').compareTo(b.releaseDate ?? ''));
    return list;
  }

  List<Subject> _popular(bool Function(Subject) test, int take) =>
      dedupeTitles(c.subjectsList.where(test)).take(take).toList();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, top + 8, 4, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text('New & Hot',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: 'Search',
                onPressed: () {
                  stopInlineMedia();
                  openSearchTab();
                },
                icon: const Icon(Icons.search_rounded, color: Colors.white, size: 27),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            itemCount: _Section.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final s = _Section.values[i];
              final selected = s == _section;
              return ChoiceChip(
                label: Text(s.label),
                selected: selected,
                onSelected: (_) => _select(s),
                showCheckmark: false,
                labelStyle: TextStyle(
                  color: selected ? kInk : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                selectedColor: Colors.white,
                backgroundColor: const Color(0xFF1C1C24),
                side: BorderSide.none,
                shape: const StadiumBorder(),
              );
            },
          ),
        ),
        Expanded(
          child: Obx(() {
            final items = switch (_section) {
              _Section.comingSoon => _comingSoon(),
              _Section.everyone => _popular((_) => true, 20),
              _Section.topShows => _popular((s) => s.subjectType == 2, 10),
              _Section.topMovies => _popular((s) => s.subjectType == 1, 10),
            };
            final loading = _section == _Section.comingSoon ? c.isFeedLoading.value : c.isLoading.value;
            if (items.isEmpty) {
              return Center(
                child: loading
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Nothing to show right now.', style: TextStyle(color: Colors.white54)),
                          TextButton(
                            onPressed: _section == _Section.comingSoon ? c.fetchHomeFeed : c.refresh,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
              );
            }
            return RefreshIndicator(
              onRefresh: () => Future.wait([c.fetchHomeFeed(), c.refresh()]),
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                itemCount: items.length,
                itemBuilder: (_, i) => _NewHotCard(
                  subject: items[i],
                  rank: _section == _Section.topShows || _section == _Section.topMovies ? i + 1 : null,
                  upcoming: _section == _Section.comingSoon,
                  playing: _playing,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _NewHotCard extends StatefulWidget {
  const _NewHotCard({required this.subject, required this.upcoming, required this.playing, this.rank});
  final Subject subject;
  final bool upcoming;
  final int? rank;
  final ValueNotifier<String?> playing;

  @override
  State<_NewHotCard> createState() => _NewHotCardState();
}

class _NewHotCardState extends State<_NewHotCard> {
  late bool _inList = UserData.inMyList(widget.subject.subjectId);

  @override
  Widget build(BuildContext context) {
    final s = widget.subject;
    final date = DateTime.tryParse(s.releaseDate ?? '');
    final genres = (s.genre ?? '').split(',').where((g) => g.trim().isNotEmpty).take(3).join('  •  ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: widget.rank != null
                ? Text('${widget.rank}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900))
                : widget.upcoming && date != null
                    ? Column(
                        children: [
                          Text(DateFormat('MMM').format(date).toUpperCase(),
                              style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w700)),
                          Text('${date.day}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, height: 1.1)),
                        ],
                      )
                    : const SizedBox.shrink(),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TrailerFrame(subject: s, playing: widget.playing),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(s.title ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                      ),
                      _SmallAction(
                        icon: _inList ? Icons.check_rounded : Icons.add_rounded,
                        label: 'My List',
                        onTap: () {
                          setState(() => _inList = UserData.toggleMyList(s));
                          Get.find<HomeScreenController>().refreshUserRows();
                        },
                      ),
                      _SmallAction(
                        icon: widget.upcoming ? Icons.info_outline_rounded : Icons.play_arrow_rounded,
                        label: widget.upcoming ? 'Info' : 'Play',
                        onTap: () => openDetail(s, resume: !widget.upcoming),
                      ),
                    ],
                  ),
                  if (widget.upcoming && date != null) ...[
                    const SizedBox(height: 4),
                    Text(_comingLabel(date),
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                  if ((s.description ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(s.description!.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35)),
                  ],
                  if (genres.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(genres, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _comingLabel(DateTime date) {
  final today = DateTime.now();
  final days = DateTime(date.year, date.month, date.day)
      .difference(DateTime(today.year, today.month, today.day))
      .inDays;
  if (days < 0) return 'Released ${DateFormat('d MMM').format(date)}';
  if (days == 0) return 'Coming Today';
  if (days == 1) return 'Coming Tomorrow';
  if (days < 7) return 'Coming ${DateFormat('EEEE').format(date)}';
  return 'Coming ${DateFormat('d MMMM').format(date)}';
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 54,
          height: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 16:9 still (the trailer's cover, else the poster); tap plays the trailer
/// inline when the title has one.
class _TrailerFrame extends StatefulWidget {
  const _TrailerFrame({required this.subject, required this.playing});
  final Subject subject;
  final ValueNotifier<String?> playing;

  @override
  State<_TrailerFrame> createState() => _TrailerFrameState();
}

class _TrailerFrameState extends State<_TrailerFrame> {
  VideoPlayerController? _video;
  bool _muted = false;
  bool _failed = false;

  String? get _url => widget.subject.trailer?.videoAddress?.url;
  String get _key => widget.subject.subjectId ?? widget.subject.title ?? '';

  @override
  void initState() {
    super.initState();
    widget.playing.addListener(_onPlayingChanged);
    inlineMediaStop.addListener(_stop);
  }

  void _stop() {
    if (widget.playing.value == _key) widget.playing.value = null;
  }

  @override
  void dispose() {
    widget.playing.removeListener(_onPlayingChanged);
    inlineMediaStop.removeListener(_stop);
    _video?.dispose();
    super.dispose();
  }

  void _onPlayingChanged() {
    if (widget.playing.value != _key && _video != null) {
      _video!.dispose();
      setState(() => _video = null);
    }
  }

  Future<void> _play() async {
    final url = _url;
    if (url == null || url.isEmpty) {
      openDetail(widget.subject);
      return;
    }
    widget.playing.value = _key;
    final video = VideoPlayerController.networkUrl(Uri.parse(url));
    setState(() {
      _video = video;
      _failed = false;
    });
    try {
      await video.initialize();
      if (!mounted || _video != video) return;
      await video.setVolume(_muted ? 0 : 1);
      await video.play();
      video.addListener(() {
        if (video.value.isCompleted && widget.playing.value == _key) widget.playing.value = null;
      });
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.subject;
    final still = s.trailer?.cover?.url ?? s.cover?.url;
    final video = _video;
    final ready = video != null && video.value.isInitialized;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: video.value.size.width,
                  height: video.value.size.height,
                  child: VideoPlayer(video),
                ),
              )
            else
              GestureDetector(
                onTap: _play,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (still != null && still.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: posterUrl(still, width: 700),
                        fit: BoxFit.cover,
                        alignment: const Alignment(0, -0.3),
                        placeholder: (_, _) => const ColoredBox(color: kCard),
                        errorWidget: (_, _, _) => const ColoredBox(color: kCard),
                      )
                    else
                      const ColoredBox(color: kCard),
                    if ((_url ?? '').isNotEmpty)
                      Center(
                        child: video != null && !_failed
                            ? const CircularProgressIndicator(strokeWidth: 3)
                            : Semantics(
                                button: true,
                                label: 'Play trailer',
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.5),
                                  ),
                                  child: Icon(_failed ? Icons.refresh_rounded : Icons.play_arrow_rounded,
                                      color: Colors.white, size: 30),
                                ),
                              ),
                      ),
                  ],
                ),
              ),
            if (ready)
              Positioned(
                right: 6,
                bottom: 6,
                child: IconButton(
                  tooltip: _muted ? 'Unmute' : 'Mute',
                  onPressed: () {
                    setState(() => _muted = !_muted);
                    video.setVolume(_muted ? 0 : 1);
                  },
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            if (ready)
              Positioned(
                left: 6,
                bottom: 6,
                child: IconButton(
                  tooltip: 'Stop trailer',
                  onPressed: () => widget.playing.value = null,
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  icon: const Icon(Icons.stop_rounded, color: Colors.white, size: 20),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
