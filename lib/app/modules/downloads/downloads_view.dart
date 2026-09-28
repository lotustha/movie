import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../../app_theme.dart';
import '../../model/subject_list.dart';
import '../../services/download_service.dart';
import '../../services/prefs.dart';
import '../video_player/bindings/video_player_binding.dart';
import '../video_player/views/video_player_view.dart';

/// Plays a finished download from the device, resuming saved progress.
Future<void> playDownload(DownloadItem item) async {
  final svc = DownloadService.to;
  final stream = svc.offlineStream(item.subjectId, item.season, item.episode);
  if (stream == null) {
    Get.snackbar('Not downloaded yet', 'Wait for the download to finish.',
        snackPosition: SnackPosition.BOTTOM, colorText: Colors.white);
    return;
  }
  final saved = GetStorage().read('progress_${item.subjectId}');
  var start = Duration.zero;
  if (saved is Map && saved['season'] == item.season && saved['episode'] == item.episode) {
    start = Duration(seconds: (saved['position'] as num?)?.toInt() ?? 0);
  }
  final eps = item.episodeMap;
  await Get.to(
    () => const VideoPlayerView(),
    binding: VideoPlayerBinding(),
    arguments: {
      'subject': item.subject,
      'resource': Resource(seasons: [
        if (!item.isEpisode) SeasonResource(se: 0, maxEp: 0, allEp: ''),
        for (final e in eps.entries) SeasonResource(se: e.key, maxEp: e.value.length, allEp: e.value.join(',')),
      ]),
      'streams': [stream],
      'season': item.season,
      'episode': item.episode,
      'position': start,
      'offline': true,
    },
  );
}

/// Netflix's Downloads: titles grouped by show, live progress, Smart
/// Downloads status and the storage used.
class DownloadsView extends StatelessWidget {
  const DownloadsView({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = DownloadService.to;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Downloads', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Obx(() {
        final items = svc.items.toList();
        final groups = <String, List<DownloadItem>>{};
        for (final it in items) {
          groups.putIfAbsent(it.subjectId, () => []).add(it);
        }
        return Column(
          children: [
            _SmartBanner(),
            Expanded(
              child: items.isEmpty
                  ? const _Empty()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      children: [
                        for (final g in groups.values)
                          g.first.isEpisode ? _ShowGroup(items: g) : _DownloadRow(item: g.first),
                      ],
                    ),
            ),
            _StorageBar(used: svc.usedBytes),
          ],
        );
      }),
    );
  }
}

class _SmartBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final on = AppPrefs.to.smartDownloads.value;
      return InkWell(
        onTap: () => AppPrefs.to.setSmartDownloads(!on),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: on ? kBrandPurple : Colors.white38, size: 20),
              const SizedBox(width: 8),
              Text('Smart Downloads', style: TextStyle(color: on ? Colors.white : Colors.white54, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text(on ? 'ON' : 'OFF',
                  style: TextStyle(color: on ? kBrandPurple : Colors.white38, fontWeight: FontWeight.w800)),
              const Spacer(),
              Obx(() => Text(AppPrefs.to.wifiOnlyDownloads.value ? 'Wi-Fi only' : 'Any network',
                  style: const TextStyle(color: Colors.white38, fontSize: 12))),
            ],
          ),
        ),
      );
    });
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), shape: BoxShape.circle),
                child: const Icon(Icons.download_rounded, color: Colors.white38, size: 64),
              ),
              const SizedBox(height: 20),
              const Text('Movies and shows that you download appear here.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 15)),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: Get.back,
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                child: const Text('Find Something to Download'),
              ),
            ],
          ),
        ),
      );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.subject});
  final Subject subject;
  static const double width = 64;

  @override
  Widget build(BuildContext context) {
    final url = subject.cover?.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: width,
        height: width * 1.5,
        child: url == null
            ? const ColoredBox(color: Color(0xFF1C1C24))
            : CachedNetworkImage(
                imageUrl: '$url?x-oss-process=image/resize%2Cw_200',
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF1C1C24)),
              ),
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({required this.item, this.compact = false});
  final DownloadItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = item.subject;
    final meta = <String>[
      if (item.isEpisode) item.label,
      if (item.totalBytes > 0) formatBytes(item.totalBytes),
      if (item.quality.isNotEmpty) '${item.quality}p',
    ].join(' · ');
    return InkWell(
      onTap: item.state == DownloadState.complete ? () => playDownload(item) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (!compact) _Thumb(subject: s) else const SizedBox(width: 4),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(compact ? 'Episode ${item.episode}' : (s.title ?? ''),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(meta, style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
                  const SizedBox(height: 3),
                  _StatusLine(item: item),
                ],
              ),
            ),
            _ActionButton(item: item),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.item});
  final DownloadItem item;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (item.state) {
      DownloadState.complete => ('Downloaded', const Color(0xFF3DDC84)),
      DownloadState.running => ('Downloading ${(item.progress * 100).clamp(0, 100).round()}%', kBrandPurple),
      DownloadState.paused => ('Paused ${(item.progress * 100).round()}%', Colors.white54),
      DownloadState.failed => (item.error ?? 'Download failed', kBrandRed),
      DownloadState.queued => (item.waitingForWifi ? 'Waiting for Wi-Fi' : 'Queued', Colors.white54),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        if (item.state == DownloadState.running || item.state == DownloadState.paused) ...[
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: item.progress.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(kBrandPurple),
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.item});
  final DownloadItem item;

  @override
  Widget build(BuildContext context) {
    final svc = DownloadService.to;
    return PopupMenuButton<String>(
      tooltip: 'Download options',
      color: const Color(0xFF1F1F27),
      icon: Icon(
        switch (item.state) {
          DownloadState.complete => Icons.play_circle_outline_rounded,
          DownloadState.running => Icons.pause_circle_outline_rounded,
          DownloadState.paused => Icons.play_arrow_rounded,
          DownloadState.failed => Icons.refresh_rounded,
          DownloadState.queued => Icons.schedule_rounded,
        },
        color: Colors.white,
        size: 28,
      ),
      onSelected: (v) {
        switch (v) {
          case 'play':
            playDownload(item);
          case 'pause':
            svc.pause(item);
          case 'resume':
            svc.resume(item);
          case 'retry':
            svc.retry(item);
          case 'delete':
            svc.delete(item);
        }
      },
      itemBuilder: (_) => [
        if (item.state == DownloadState.complete) _menu('play', Icons.play_arrow_rounded, 'Play'),
        if (item.state == DownloadState.running || item.state == DownloadState.queued)
          _menu('pause', Icons.pause_rounded, 'Pause download'),
        if (item.state == DownloadState.paused) _menu('resume', Icons.play_arrow_rounded, 'Resume download'),
        if (item.state == DownloadState.failed) _menu('retry', Icons.refresh_rounded, 'Retry'),
        _menu('delete', Icons.delete_outline_rounded,
            item.state == DownloadState.complete ? 'Delete download' : 'Cancel download'),
      ],
    );
  }

  static PopupMenuItem<String> _menu(String v, IconData icon, String label) => PopupMenuItem(
        value: v,
        child: Row(children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white)),
        ]),
      );
}

class _ShowGroup extends StatelessWidget {
  const _ShowGroup({required this.items});
  final List<DownloadItem> items;

  @override
  Widget build(BuildContext context) {
    final s = items.first.subject;
    final done = items.where((i) => i.state == DownloadState.complete).length;
    final bytes = items.fold<int>(0, (a, i) => a + i.totalBytes);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 76),
        leading: _Thumb(subject: s),
        iconColor: Colors.white70,
        collapsedIconColor: Colors.white70,
        title: Text(s.title ?? '',
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        subtitle: Text('${items.length} episode${items.length == 1 ? '' : 's'} · $done ready · ${formatBytes(bytes)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
        children: [
          for (final it in (items..sort((a, b) =>
              a.season != b.season ? a.season.compareTo(b.season) : a.episode.compareTo(b.episode))))
            _DownloadRow(item: it, compact: true),
        ],
      ),
    );
  }
}

class _StorageBar extends StatelessWidget {
  const _StorageBar({required this.used});
  final int used;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFF14141A),
          child: Row(
            children: [
              Container(width: 10, height: 10, decoration: const BoxDecoration(color: kBrandPurple, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('NoonFlix downloads: ${formatBytes(used)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            ],
          ),
        ),
      );
}
