import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../../app_theme.dart';
import '../../model/subject_list.dart';
import '../../services/download_service.dart';
import '../../services/prefs.dart';
import '../home_screen/views/mobile/mobile_common.dart' show openDetail;
import '../video_player/bindings/video_player_binding.dart';
import '../video_player/views/video_player_view.dart';

const Color _sheet = Color(0xFF1F1F27);

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

/// Hooks the "storage limit reached" question into the download service.
void registerDownloadPrompts() {
  if (!DownloadService.supported || !Get.isRegistered<DownloadService>()) return;
  DownloadService.to.onStorageFull = (need, freeable) async {
    final choice = await Get.dialog<StorageChoice>(AlertDialog(
      backgroundColor: _sheet,
      icon: const Icon(Icons.sd_storage_rounded, color: kBrandPurple, size: 34),
      title: const Text('Download space is full', style: TextStyle(color: Colors.white)),
      content: Text(
        'This download needs ${formatBytes(need)} more than your '
        '${AppPrefs.to.downloadLimitGb.value} GB limit.'
        '${freeable > 0 ? ' Deleting watched downloads frees ${formatBytes(freeable)}.' : ''}',
        style: const TextStyle(color: Colors.white70, height: 1.4),
      ),
      actions: [
        TextButton(onPressed: () => Get.back(result: StorageChoice.cancel), child: const Text('Cancel')),
        TextButton(
            onPressed: () => Get.back(result: StorageChoice.downloadAnyway), child: const Text('Download anyway')),
        if (freeable > 0)
          FilledButton(
            autofocus: true,
            onPressed: () => Get.back(result: StorageChoice.deleteWatched),
            child: const Text('Delete watched'),
          ),
      ],
    ));
    return choice ?? StorageChoice.cancel;
  };
}

// ─── Shared pickers (also used by Settings) ─────────────────────────────────

const _deleteModes = {
  'whenFull': ('When space runs out', 'Keep watched downloads until the limit is reached, then delete the oldest watched first.'),
  'immediately': ('Right after watching', 'Delete a download as soon as you finish it.'),
  'ask': ('Ask me', 'Never delete a watched download without asking.'),
};

String deleteWatchedLabel(String mode) => _deleteModes[mode]?.$1 ?? mode;

Future<void> pickDeleteWatchedMode() async {
  final prefs = AppPrefs.to;
  final choice = await _radioSheet<String>(
    'Delete watched downloads',
    [for (final e in _deleteModes.entries) (e.key, e.value.$1, e.value.$2)],
    prefs.deleteWatched.value,
  );
  if (choice != null) prefs.setDeleteWatched(choice);
}

const _limits = [0, 1, 2, 5, 10, 20, 50];

String limitLabel(int gb) => gb == 0 ? 'No limit' : '$gb GB';

Future<void> pickStorageLimit() async {
  final prefs = AppPrefs.to;
  final used = DownloadService.to.reservedBytes;
  final choice = await _radioSheet<int>(
    'Download storage limit',
    [
      for (final gb in _limits)
        (gb, limitLabel(gb), gb == 0 ? 'Use as much space as the phone has' : null),
    ],
    prefs.downloadLimitGb.value,
    footer: 'Downloads use ${formatBytes(used)} now.',
  );
  if (choice != null) prefs.setDownloadLimitGb(choice);
}

Future<T?> _radioSheet<T>(String title, List<(T, String, String?)> options, T current, {String? footer}) {
  return Get.bottomSheet<T>(
    SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(title,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (value, label, sub) in options)
                    ListTile(
                      onTap: () => Get.back(result: value),
                      leading: Icon(value == current ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: value == current ? kBrandPurple : Colors.white54),
                      title: Text(label, style: const TextStyle(color: Colors.white)),
                      subtitle: sub == null ? null : Text(sub, style: const TextStyle(color: Colors.white54)),
                    ),
                ],
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(footer, style: const TextStyle(color: Colors.white38, fontSize: 12.5)),
              ),
          ],
        ),
      ),
    ),
    backgroundColor: _sheet,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
  );
}

Future<bool> _confirm(String title, String body, {String action = 'Delete'}) async {
  final ok = await Get.dialog<bool>(AlertDialog(
    backgroundColor: _sheet,
    title: Text(title, style: const TextStyle(color: Colors.white)),
    content: Text(body, style: const TextStyle(color: Colors.white70)),
    actions: [
      TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: kBrandRed),
        onPressed: () => Get.back(result: true),
        child: Text(action),
      ),
    ],
  ));
  return ok == true;
}

// ─── Downloads page ──────────────────────────────────────────────────────────

/// Netflix's Downloads, plus what it lacks: a storage limit you set, a choice
/// of when watched downloads go, bulk delete (Edit), per-show pages with
/// "Delete watched" / "Delete series", and Delete all.
class DownloadsView extends StatefulWidget {
  const DownloadsView({super.key});

  @override
  State<DownloadsView> createState() => _DownloadsViewState();
}

class _DownloadsViewState extends State<DownloadsView> {
  final DownloadService svc = DownloadService.to;
  bool _editing = false;
  final Set<String> _selected = {}; // item keys

  void _toggle(Iterable<DownloadItem> items) {
    setState(() {
      final keys = items.map((i) => i.key).toList();
      final all = keys.every(_selected.contains);
      all ? _selected.removeAll(keys) : _selected.addAll(keys);
    });
  }

  Future<void> _deleteSelected() async {
    final list = svc.items.where((i) => _selected.contains(i.key)).toList();
    if (list.isEmpty) return;
    final bytes = list.fold<int>(0, (a, i) => a + i.totalBytes);
    if (!await _confirm('Delete ${list.length} download${list.length == 1 ? '' : 's'}?',
        'Frees ${formatBytes(bytes)} on this phone.')) {
      return;
    }
    await svc.deleteItems(list);
    setState(() {
      _selected.clear();
      _editing = false;
    });
  }

  Future<void> _menu(String v) async {
    switch (v) {
      case 'watched':
        final n = svc.watchedItems.length;
        if (n == 0) {
          Get.snackbar('Downloads', 'No watched downloads.', snackPosition: SnackPosition.BOTTOM, colorText: Colors.white);
          return;
        }
        if (await _confirm('Delete watched downloads?', '$n watched download${n == 1 ? '' : 's'} will be removed.')) {
          await svc.deleteWatched();
        }
      case 'all':
        if (await _confirm('Delete all downloads?',
            'Everything you downloaded (${formatBytes(svc.reservedBytes)}) will be removed from this phone.',
            action: 'Delete all')) {
          await svc.deleteAll();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final items = svc.items.toList();
      final active = items.where((i) => i.active || i.state == DownloadState.failed).toList();
      final done = items.where((i) => i.state == DownloadState.complete).toList();
      final movies = done.where((i) => !i.isEpisode).toList();
      final shows = <String, List<DownloadItem>>{};
      for (final it in done.where((i) => i.isEpisode)) {
        shows.putIfAbsent(it.subjectId, () => []).add(it);
      }
      final selectedItems = items.where((i) => _selected.contains(i.key)).toList();
      return PopScope(
        canPop: !_editing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() {
                    _editing = false;
                    _selected.clear();
                  });
        },
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: Text(_editing ? '${_selected.length} selected' : 'Downloads',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            leading: _editing
                ? IconButton(
                    tooltip: 'Done',
                    onPressed: () => setState(() {
                    _editing = false;
                    _selected.clear();
                  }),
                    icon: const Icon(Icons.close_rounded),
                  )
                : null,
            actions: [
              if (items.isNotEmpty && !_editing)
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(Icons.edit_outlined),
                ),
              if (_editing)
                TextButton(
                  onPressed: () => _toggle(items),
                  child: Text(items.every((i) => _selected.contains(i.key)) ? 'Select none' : 'Select all'),
                ),
              if (!_editing)
                PopupMenuButton<String>(
                  tooltip: 'More',
                  color: _sheet,
                  onSelected: _menu,
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'watched', child: Text('Delete watched', style: TextStyle(color: Colors.white))),
                    if (items.isNotEmpty)
                      const PopupMenuItem(value: 'all', child: Text('Delete all downloads', style: TextStyle(color: Colors.white))),
                  ],
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    const _SmartCard(),
                    if (items.isEmpty) const _Empty(),
                    if (active.isNotEmpty) ...[
                      _Section('Downloading (${active.length})'),
                      for (final it in active)
                        _DownloadRow(
                          item: it,
                          editing: _editing,
                          selected: _selected.contains(it.key),
                          onSelect: () => _toggle([it]),
                        ),
                    ],
                    if (movies.isNotEmpty) ...[
                      _Section('Movies (${movies.length})'),
                      for (final it in movies)
                        _DownloadRow(
                          item: it,
                          editing: _editing,
                          selected: _selected.contains(it.key),
                          onSelect: () => _toggle([it]),
                        ),
                    ],
                    if (shows.isNotEmpty) ...[
                      _Section('TV Shows (${shows.length})'),
                      for (final g in shows.values)
                        _ShowRow(
                          items: g,
                          editing: _editing,
                          selected: g.every((i) => _selected.contains(i.key)),
                          onSelect: () => _toggle(g),
                        ),
                    ],
                    if (items.isNotEmpty && !_editing) ...[
                      const SizedBox(height: 20),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => _menu('all'),
                          style: TextButton.styleFrom(foregroundColor: kBrandRed),
                          icon: const Icon(Icons.delete_forever_outlined),
                          label: const Text('Delete all downloads'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_editing)
                _DeleteBar(
                  count: selectedItems.length,
                  bytes: selectedItems.fold(0, (a, i) => a + i.totalBytes),
                  onDelete: _deleteSelected,
                )
              else
                const _StorageBar(),
            ],
          ),
        ),
      );
    });
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 6),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      );
}

/// Smart Downloads + what happens to watched downloads, in one card.
class _SmartCard extends StatelessWidget {
  const _SmartCard();

  @override
  Widget build(BuildContext context) {
    final prefs = AppPrefs.to;
    return Obx(() => Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [kBrandPurple.withValues(alpha: 0.22), kBrandRed.withValues(alpha: 0.12)]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              SwitchListTile(
                value: prefs.smartDownloads.value,
                onChanged: prefs.setSmartDownloads,
                activeTrackColor: kBrandPurple,
                secondary: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
                title: const Text('Smart Downloads',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                subtitle: const Text('When you finish an episode, the next one downloads.',
                    style: TextStyle(color: Colors.white60, fontSize: 12.5)),
              ),
              const Divider(height: 1, color: Colors.white10),
              ListTile(
                onTap: pickDeleteWatchedMode,
                leading: const Icon(Icons.delete_sweep_outlined, color: Colors.white),
                title: const Text('Delete watched downloads', style: TextStyle(color: Colors.white)),
                subtitle: Text(deleteWatchedLabel(prefs.deleteWatched.value),
                    style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
                trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
              ),
              ListTile(
                onTap: () => AppPrefs.to.setWifiOnly(!prefs.wifiOnlyDownloads.value),
                leading: const Icon(Icons.wifi_rounded, color: Colors.white),
                title: const Text('Wi-Fi only', style: TextStyle(color: Colors.white)),
                trailing: ExcludeSemantics(
                  child: Switch(
                    value: prefs.wifiOnlyDownloads.value,
                    onChanged: prefs.setWifiOnly,
                    activeTrackColor: kBrandPurple,
                  ),
                ),
              ),
            ],
          ),
        ));
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), shape: BoxShape.circle),
              child: const Icon(Icons.download_rounded, color: Colors.white38, size: 58),
            ),
            const SizedBox(height: 18),
            const Text('Movies and shows that you download appear here.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 15)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: Get.back,
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
              child: const Text('Find Something to Download'),
            ),
          ],
        ),
      );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.subject, this.width = 62});
  final Subject subject;
  final double width;

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

class _Check extends StatelessWidget {
  const _Check({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: selected ? kBrandPurple : Colors.white38, size: 26),
      );
}

/// A movie or an episode.
class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.item,
    this.compact = false,
    this.editing = false,
    this.selected = false,
    this.onSelect,
  });
  final DownloadItem item;
  final bool compact;
  final bool editing;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final s = item.subject;
    final meta = <String>[
      if (!compact && item.isEpisode) item.label,
      if (item.totalBytes > 0) formatBytes(item.totalBytes),
      if (item.quality.isNotEmpty) '${item.quality}p',
    ].join(' · ');
    final row = InkWell(
      onTap: editing ? onSelect : (item.state == DownloadState.complete ? () => playDownload(item) : null),
      onLongPress: editing ? null : onSelect == null ? null : () => onSelect!(),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            if (editing) _Check(selected: selected),
            if (!compact) ...[_Thumb(subject: s), const SizedBox(width: 12)],
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
            if (!editing) ...[
              IconButton(
                tooltip: item.state == DownloadState.complete ? 'Delete download' : 'Cancel download',
                onPressed: () => _deleteOne(item),
                icon: Icon(
                    item.state == DownloadState.complete ? Icons.delete_outline_rounded : Icons.close_rounded,
                    color: Colors.white60),
              ),
              _ActionButton(item: item),
            ],
          ],
        ),
      ),
    );
    if (editing) return row;
    // Swipe left to delete, as in most download lists.
    return Dismissible(
      key: ValueKey('dl-${item.key}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _deleteOne(item),
      background: const _SwipeDelete(),
      child: row,
    );
  }
}

/// Asks, then deletes (or cancels) one download. True when it went.
Future<bool> _deleteOne(DownloadItem item) async {
  final done = item.state == DownloadState.complete;
  final name = item.isEpisode ? '${item.subject.title ?? ''} ${item.label}' : (item.subject.title ?? 'this download');
  final ok = await _confirm(done ? 'Delete download?' : 'Cancel download?',
      done ? '$name (${formatBytes(item.totalBytes)}) will be removed from this phone.' : '$name will stop downloading.',
      action: done ? 'Delete' : 'Cancel download');
  if (ok) await DownloadService.to.delete(item);
  return ok;
}

class _SwipeDelete extends StatelessWidget {
  const _SwipeDelete();

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(color: kBrandRed, borderRadius: BorderRadius.circular(8)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white),
            SizedBox(width: 6),
            Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.item});
  final DownloadItem item;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (item.state) {
      DownloadState.complete when item.watched => ('Watched', Colors.white54),
      DownloadState.complete => ('Downloaded', const Color(0xFF3DDC84)),
      DownloadState.running => ('Downloading ${(item.progress * 100).clamp(0, 100).round()}%', kBrandPurple),
      DownloadState.paused => ('Paused ${(item.progress * 100).round()}%', Colors.white54),
      DownloadState.failed => (item.error ?? 'Download failed', kBrandRed),
      DownloadState.queued => (item.waitingForWifi ? 'Waiting for Wi-Fi' : 'Queued', Colors.white54),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          if (item.state == DownloadState.complete)
            Icon(item.watched ? Icons.visibility_rounded : Icons.download_done_rounded, color: color, size: 14),
          if (item.state == DownloadState.complete) const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
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
      color: _sheet,
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
      onSelected: (v) async {
        switch (v) {
          case 'play':
            playDownload(item);
          case 'pause':
            svc.pause(item);
          case 'resume':
            svc.resume(item);
          case 'retry':
            svc.retry(item);
          case 'info':
            openDetail(item.subject);
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
        _menu('info', Icons.info_outline_rounded, 'Title details'),
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

/// A downloaded show: opens its episodes page.
class _ShowRow extends StatelessWidget {
  const _ShowRow({required this.items, required this.editing, required this.selected, required this.onSelect});
  final List<DownloadItem> items;
  final bool editing;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final s = items.first.subject;
    final bytes = items.fold<int>(0, (a, i) => a + i.totalBytes);
    final watched = items.where((i) => i.watched).length;
    final row = InkWell(
      onTap: editing
          ? onSelect
          : () => Get.to(() => ShowDownloadsView(subjectId: items.first.subjectId),
              transition: Transition.rightToLeft),
      onLongPress: editing ? null : onSelect,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            if (editing) _Check(selected: selected),
            _Thumb(subject: s),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    '${items.length} episode${items.length == 1 ? '' : 's'} · ${formatBytes(bytes)}'
                    '${watched > 0 ? ' · $watched watched' : ''}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            if (!editing) ...[
              IconButton(
                tooltip: 'Delete series',
                onPressed: () => _deleteSeries(items),
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white60),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ],
          ],
        ),
      ),
    );
    if (editing) return row;
    return Dismissible(
      key: ValueKey('show-${items.first.subjectId}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _deleteSeries(items),
      background: const _SwipeDelete(),
      child: row,
    );
  }
}

Future<bool> _deleteSeries(List<DownloadItem> items) async {
  final s = items.first.subject;
  final bytes = items.fold<int>(0, (a, i) => a + i.totalBytes);
  final ok = await _confirm('Delete ${s.title}?',
      'All ${items.length} downloaded episode${items.length == 1 ? '' : 's'} (${formatBytes(bytes)}) will be removed.',
      action: 'Delete series');
  if (ok) await DownloadService.to.deleteSubject(items.first.subjectId);
  return ok;
}

/// Used vs the limit you set; tap to change the limit.
class _StorageBar extends StatelessWidget {
  const _StorageBar();

  @override
  Widget build(BuildContext context) {
    final svc = DownloadService.to;
    return Obx(() {
      svc.items.length;
      final used = svc.reservedBytes;
      final limit = svc.limitBytes;
      final frac = limit <= 0 ? null : (used / limit).clamp(0.0, 1.0);
      final full = frac != null && frac >= 0.9;
      return Material(
        color: const Color(0xFF14141A),
        child: InkWell(
          onTap: pickStorageLimit,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Downloads ${formatBytes(used)}',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(limit <= 0 ? 'No limit · Change' : 'of ${limitLabel(AppPrefs.to.downloadLimitGb.value)} · Change',
                          style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
                    ],
                  ),
                  if (frac != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 5,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation(full ? kBrandRed : kBrandPurple),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _DeleteBar extends StatelessWidget {
  const _DeleteBar({required this.count, required this.bytes, required this.onDelete});
  final int count;
  final int bytes;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: count == 0 ? null : onDelete,
              style: FilledButton.styleFrom(
                backgroundColor: kBrandRed,
                disabledBackgroundColor: Colors.white12,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(count == 0 ? 'Select downloads to delete' : 'Delete $count · ${formatBytes(bytes)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );
}

// ─── One show's downloads ────────────────────────────────────────────────────

/// A downloaded show's episodes by season, with Delete watched / Delete
/// series and a way to download more.
class ShowDownloadsView extends StatelessWidget {
  const ShowDownloadsView({super.key, required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context) {
    final svc = DownloadService.to;
    return Obx(() {
      final eps = svc.itemsForSubject(subjectId);
      if (eps.isEmpty) {
        // Everything was deleted: nothing left to show here.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (Get.currentRoute.isNotEmpty) Navigator.of(context).maybePop();
        });
        return const Scaffold(body: SizedBox.shrink());
      }
      final s = eps.first.subject;
      final watched = eps.where((i) => i.watched).toList();
      final bytes = eps.fold<int>(0, (a, i) => a + i.totalBytes);
      final seasons = <int, List<DownloadItem>>{};
      for (final e in eps) {
        seasons.putIfAbsent(e.season, () => []).add(e);
      }
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: Text(s.title ?? 'Downloads', maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'More',
              color: _sheet,
              onSelected: (v) async {
                if (v == 'watched' &&
                    await _confirm('Delete watched episodes?',
                        '${watched.length} watched episode${watched.length == 1 ? '' : 's'} of ${s.title} will be removed.')) {
                  await svc.deleteWatched(subjectId);
                }
                if (v == 'series' &&
                    await _confirm('Delete ${s.title}?',
                        'All ${eps.length} downloaded episode${eps.length == 1 ? '' : 's'} (${formatBytes(bytes)}) will be removed.',
                        action: 'Delete series')) {
                  await svc.deleteSubject(subjectId);
                }
              },
              itemBuilder: (_) => [
                if (watched.isNotEmpty)
                  PopupMenuItem(
                      value: 'watched',
                      child: Text('Delete watched episodes (${watched.length})',
                          style: const TextStyle(color: Colors.white))),
                const PopupMenuItem(
                    value: 'series', child: Text('Delete series', style: TextStyle(color: Colors.white))),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                _Thumb(subject: s, width: 78),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.title ?? '',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('${eps.length} episodes · ${formatBytes(bytes)}',
                          style: const TextStyle(color: Colors.white60, fontSize: 13)),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => openDetail(s),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24)),
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text('Download more episodes'),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (watched.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () async {
                                if (await _confirm('Delete watched episodes?',
                                    '${watched.length} watched episode${watched.length == 1 ? '' : 's'} will be removed.')) {
                                  await svc.deleteWatched(subjectId);
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
                              icon: const Icon(Icons.visibility_off_outlined, size: 18),
                              label: Text('Delete watched (${watched.length})'),
                            ),
                          OutlinedButton.icon(
                            onPressed: () => _deleteSeries(eps),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: kBrandRed, side: BorderSide(color: kBrandRed.withValues(alpha: 0.6))),
                            icon: const Icon(Icons.delete_outline_rounded, size: 18),
                            label: const Text('Delete series'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            for (final entry in seasons.entries) ...[
              _Section('Season ${entry.key}'),
              for (final it in entry.value) _DownloadRow(item: it, compact: true),
            ],

          ],
        ),
      );
    });
  }
}

