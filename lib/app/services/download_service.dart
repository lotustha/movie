import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../data/api_provider.dart';
import '../data/user_data.dart';
import '../model/CaptionApiResponse.dart';
import '../model/StreamInfo.dart';
import '../model/subject_list.dart';
import 'prefs.dart';

enum DownloadState { queued, running, paused, failed, complete }

/// The user's answer when a download doesn't fit the storage limit.
enum StorageChoice { deleteWatched, downloadAnyway, cancel }

/// One downloaded (or downloading) movie / episode.
class DownloadItem {
  DownloadItem(this.data);
  final Map<String, dynamic> data;

  String get key => data['key'] as String;
  String get taskId => data['taskId'] as String? ?? '';
  String get subjectId => data['subjectId'] as String;
  Subject get subject => Subject.fromJson(Map<String, dynamic>.from(data['subject'] as Map));
  int get season => (data['season'] as num?)?.toInt() ?? 0;
  int get episode => (data['episode'] as num?)?.toInt() ?? 0;
  bool get isEpisode => season > 0;
  String get quality => '${data['quality'] ?? ''}';
  int get totalBytes => (data['totalBytes'] as num?)?.toInt() ?? 0;
  double get progress => (data['progress'] as num?)?.toDouble() ?? 0;
  String? get filePath => data['filePath'] as String?;
  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch((data['createdAt'] as num?)?.toInt() ?? 0);
  DownloadState get state =>
      DownloadState.values.firstWhere((s) => s.name == data['state'], orElse: () => DownloadState.queued);
  String? get error => data['error'] as String?;
  bool get waitingForWifi => data['waitingWifi'] == true;

  /// Set when playback of this download reached its end.
  DateTime? get watchedAt {
    final ms = (data['watchedAt'] as num?)?.toInt();
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool get watched => watchedAt != null;
  bool get active => state == DownloadState.running || state == DownloadState.queued || state == DownloadState.paused;

  /// Season → episode numbers, saved at download time for Smart Downloads.
  Map<int, List<int>> get episodeMap => {
        for (final e in ((data['episodes'] as Map?) ?? const {}).entries)
          int.parse('${e.key}'): [for (final x in e.value as List) (x as num).toInt()],
      };

  List<Map<String, dynamic>> get subtitles => [
        for (final s in (data['subtitles'] as List? ?? const [])) Map<String, dynamic>.from(s as Map),
      ];

  String get label => isEpisode ? 'S$season:E$episode' : 'Movie';
}

/// Netflix-style downloads: movies and episodes saved for offline playback,
/// downloading in the background (with a progress notification) and resuming
/// after pauses, network loss or app restarts. Smart Downloads deletes a
/// finished episode and fetches the next one.
class DownloadService extends GetxService {
  static DownloadService get to => Get.find<DownloadService>();

  static const _kItems = 'downloads_v1';
  static const _group = 'noonflix_downloads';

  final GetStorage _s = GetStorage();
  final RxList<DownloadItem> items = <DownloadItem>[].obs;
  ApiProvider get _api => Get.find<ApiProvider>();
  StreamSubscription<TaskUpdate>? _updates;
  final Set<String> _refreshing = {};

  /// Downloads are for phones/tablets; TVs stream.
  static bool get supported => !kIsWeb && Platform.isAndroid;

  Future<DownloadService> init() async {
    items.assignAll([
      for (final e in (_s.read<List>(_kItems) ?? const [])) DownloadItem(Map<String, dynamic>.from(e as Map)),
    ]);
    if (!supported) return this;
    final fd = FileDownloader();
    fd.configureNotification(
      running: const TaskNotification('Downloading {displayName}', '{progress} · {networkSpeed}'),
      complete: const TaskNotification('Downloaded {displayName}', 'Ready to watch offline'),
      error: const TaskNotification('Download failed', '{displayName}'),
      paused: const TaskNotification('Download paused', '{displayName}'),
      progressBar: true,
    );
    // Big files: run as a foreground service so Android doesn't stop them at 9 minutes.
    await fd.configure(androidConfig: [(Config.runInForeground, Config.always)]);
    await fd.requireWiFi(
        AppPrefs.to.wifiOnlyDownloads.value ? RequireWiFi.forAllTasks : RequireWiFi.forNoTasks);
    ever<bool>(AppPrefs.to.wifiOnlyDownloads, (on) {
      fd.requireWiFi(on ? RequireWiFi.forAllTasks : RequireWiFi.forNoTasks);
    });
    _updates = fd.updates.listen(_onUpdate);
    await fd.start();
    await _reconcile();
    return this;
  }

  @override
  void onClose() {
    _updates?.cancel();
    super.onClose();
  }

  // ─── Queries ───────────────────────────────────────────────────────────────

  static String keyFor(String subjectId, int season, int episode) => '$subjectId|$season|$episode';

  DownloadItem? itemFor(String? subjectId, int season, int episode) {
    if (subjectId == null) return null;
    return items.firstWhereOrNull((i) => i.key == keyFor(subjectId, season, episode));
  }

  List<DownloadItem> itemsForSubject(String subjectId) =>
      items.where((i) => i.subjectId == subjectId).toList()
        ..sort((a, b) => a.season != b.season ? a.season.compareTo(b.season) : a.episode.compareTo(b.episode));

  int get usedBytes =>
      items.where((i) => i.state == DownloadState.complete).fold(0, (sum, i) => sum + i.totalBytes);

  /// Space downloads take or will take (finished files + expected sizes).
  int get reservedBytes => items.fold(0, (sum, i) => sum + i.totalBytes);

  int get limitBytes => AppPrefs.to.downloadLimitGb.value * 1024 * 1024 * 1024;

  List<DownloadItem> get watchedItems =>
      items.where((i) => i.state == DownloadState.complete && i.watched).toList()
        ..sort((a, b) => a.watchedAt!.compareTo(b.watchedAt!));

  /// Shown when a download won't fit and deleting isn't automatic; set by
  /// the UI layer (a dialog). Without one, the download is refused.
  Future<StorageChoice> Function(int needBytes, int freeableBytes)? onStorageFull;

  /// Frees room for [need] bytes under the storage limit, following the
  /// user's "watched downloads" choice. True when the download may go ahead.
  Future<bool> _makeRoom(int need) async {
    final limit = limitBytes;
    if (limit <= 0) return true;
    int over() => reservedBytes + need - limit;
    if (over() <= 0) return true;
    final mode = AppPrefs.to.deleteWatched.value;
    if (mode == 'whenFull') {
      for (final w in watchedItems) {
        if (over() <= 0) break;
        await delete(w);
      }
      if (over() <= 0) return true;
    }
    final freeable = watchedItems.fold<int>(0, (s, i) => s + i.totalBytes);
    final ask = onStorageFull;
    if (ask == null) return false;
    switch (await ask(over(), freeable)) {
      case StorageChoice.deleteWatched:
        for (final w in watchedItems) {
          if (over() <= 0) break;
          await delete(w);
        }
        return true; // what's left is the user's call: they chose to go on
      case StorageChoice.downloadAnyway:
        return true;
      case StorageChoice.cancel:
        return false;
    }
  }

  int get activeCount =>
      items.where((i) => i.state == DownloadState.running || i.state == DownloadState.queued).length;

  /// A finished download of this episode, as a playable local stream.
  StreamInfo? offlineStream(String? subjectId, int season, int episode) {
    final it = itemFor(subjectId, season, episode);
    final path = it?.filePath;
    if (it == null || it.state != DownloadState.complete || path == null || !File(path).existsSync()) {
      return null;
    }
    return StreamInfo(
      id: 'offline-${it.key}',
      url: path,
      resolutions: it.quality,
      format: 'MP4',
      size: '${it.totalBytes}',
    );
  }

  List<Captions> offlineCaptions(String? subjectId, int season, int episode) {
    final it = itemFor(subjectId, season, episode);
    if (it == null) return const [];
    return [
      for (final s in it.subtitles)
        if (File('${s['path']}').existsSync())
          Captions(id: 'offline-${s['lan']}', lan: s['lan'] as String?, lanName: s['lanName'] as String?, url: s['path'] as String?),
    ];
  }

  // ─── Actions ───────────────────────────────────────────────────────────────

  /// Starts downloading one movie (season 0) or episode. Returns null when
  /// queued, else a message to show.
  Future<String?> download(
    Subject subject, {
    int season = 0,
    int episode = 0,
    Map<int, List<int>>? episodes,
    String? quality,
  }) async {
    if (!supported) return 'Downloads are available on phones and tablets.';
    final id = subject.subjectId;
    if (id == null || subject.detailPath == null) return 'This title cannot be downloaded.';
    final existing = itemFor(id, season, episode);
    if (existing != null && existing.state != DownloadState.failed) return null;

    await FileDownloader().permissions.request(PermissionType.notifications);

    final stream = await _pickStream(subject, season, episode, quality ?? AppPrefs.to.downloadQuality.value);
    if (stream == null) return 'This title is not available to download right now.';
    if (existing == null && !await _makeRoom(int.tryParse(stream.size ?? '') ?? 0)) {
      return 'Not enough download space. Delete downloads or raise the limit in Settings.';
    }

    final key = keyFor(id, season, episode);
    final snap = UserData.snapshot(subject.toJson());
    final item = DownloadItem({
      'key': key,
      'subjectId': id,
      'subject': snap,
      'season': season,
      'episode': episode,
      'quality': stream.resolutions,
      'totalBytes': int.tryParse(stream.size ?? '') ?? 0,
      'progress': 0.0,
      'state': DownloadState.queued.name,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      if (episodes != null) 'episodes': {for (final e in episodes.entries) '${e.key}': e.value},
      if (existing != null && existing.data['episodes'] != null) 'episodes': existing.data['episodes'],
    });
    _put(item);
    unawaited(_saveSubtitles(item, stream));
    final ok = await _enqueue(item, stream);
    return ok ? null : 'Could not start the download.';
  }

  Future<bool> _enqueue(DownloadItem item, StreamInfo stream) async {
    final s = item.subject;
    final name = item.isEpisode ? '${s.title ?? ''} ${item.label}' : (s.title ?? 'Movie');
    final safe = item.key.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final task = DownloadTask(
      url: stream.url!,
      headers: stream.headers ?? const {},
      filename: '$safe.mp4',
      directory: 'downloads',
      baseDirectory: BaseDirectory.applicationSupport,
      group: _group,
      updates: Updates.statusAndProgress,
      retries: 3,
      allowPause: true,
      displayName: name,
      metaData: item.key,
    );
    item.data['taskId'] = task.taskId;
    item.data['state'] = DownloadState.queued.name;
    item.data.remove('error');
    _put(item);
    return FileDownloader().enqueue(task);
  }

  Future<StreamInfo?> _pickStream(Subject subject, int season, int episode, String quality) async {
    final r = await _api.fetchPlaybackInfoWithCookieManager(
        subject: subject, season: '$season', episode: '$episode');
    final raw = (r is Map && r['data'] is Map) ? r['data']['streams'] : null;
    if (raw is! List || raw.isEmpty) return null;
    final streams = [for (final s in raw) StreamInfo.fromJson(s)]
      ..sort((a, b) => (int.tryParse(b.resolutions ?? '') ?? 0).compareTo(int.tryParse(a.resolutions ?? '') ?? 0));
    if (quality == 'high') return streams.first;
    // Standard: the best stream at or under 720p (Netflix's "Standard" is ~480p).
    return streams.firstWhereOrNull((s) => (int.tryParse(s.resolutions ?? '') ?? 0) <= 720) ?? streams.last;
  }

  Future<void> _saveSubtitles(DownloadItem item, StreamInfo stream) async {
    try {
      final r = await _api.fetchSubtitlesForStream(streamId: stream.id ?? '', subjectId: item.subjectId);
      final captions = CaptionApiResponse.fromJson(r).data?.captions ?? const <Captions>[];
      if (captions.isEmpty) return;
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/downloads/subs');
      await dir.create(recursive: true);
      final safe = item.key.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final saved = <Map<String, dynamic>>[];
      for (final c in captions) {
        if (c.url == null) continue;
        final path = '${dir.path}/${safe}_${c.lan ?? saved.length}.srt';
        try {
          await Dio().download(c.url!, path);
          saved.add({'lan': c.lan, 'lanName': c.lanName, 'path': path});
        } catch (_) {}
      }
      final current = itemFor(item.subjectId, item.season, item.episode);
      if (current != null) {
        current.data['subtitles'] = saved;
        _put(current);
      }
    } catch (e) {
      debugPrint('download subtitles: $e');
    }
  }

  Future<void> pause(DownloadItem item) async {
    final task = await _task(item);
    if (task is DownloadTask) await FileDownloader().pause(task);
  }

  Future<void> resume(DownloadItem item) async {
    final task = await _task(item);
    if (task is DownloadTask && await FileDownloader().resume(task)) return;
    await retry(item); // not resumable (e.g. the link expired): start over
  }

  /// Fresh link (they are signed and expire) and a new task.
  Future<void> retry(DownloadItem item) async {
    if (!_refreshing.add(item.key)) return;
    try {
      await _cancelTask(item);
      final stream = await _pickStream(item.subject, item.season, item.episode,
          (int.tryParse(item.quality) ?? 0) > 720 ? 'high' : 'standard');
      if (stream == null) {
        item.data['state'] = DownloadState.failed.name;
        item.data['error'] = 'Not available right now';
        _put(item);
        return;
      }
      item.data['quality'] = stream.resolutions;
      item.data['totalBytes'] = int.tryParse(stream.size ?? '') ?? item.totalBytes;
      item.data['progress'] = 0.0;
      await _enqueue(item, stream);
    } finally {
      _refreshing.remove(item.key);
    }
  }

  Future<void> delete(DownloadItem item) async {
    await _cancelTask(item);
    for (final p in [item.filePath, for (final s in item.subtitles) s['path'] as String?]) {
      if (p == null) continue;
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    items.removeWhere((i) => i.key == item.key);
    _persist();
  }

  Future<void> deleteAll() async {
    for (final it in items.toList()) {
      await delete(it);
    }
  }

  Future<void> deleteSubject(String subjectId) async {
    for (final it in itemsForSubject(subjectId)) {
      await delete(it);
    }
  }

  /// Called by the player as a movie / episode ends. The download is marked
  /// watched (and deleted now if the user chose "immediately"); with Smart
  /// Downloads on, the next episode starts downloading.
  Future<void> onFinished(Subject subject, int season, int episode) async {
    if (!supported) return;
    final it = itemFor(subject.subjectId, season, episode);
    if (it == null || it.state != DownloadState.complete) return;
    it.data['watchedAt'] ??= DateTime.now().millisecondsSinceEpoch;
    _put(it);
    final next = it.isEpisode ? _nextAfter(it.episodeMap, season, episode) : null;
    if (AppPrefs.to.deleteWatched.value == 'immediately') await delete(it);
    if (!AppPrefs.to.smartDownloads.value || next == null) return;
    if (itemFor(subject.subjectId, next.$1, next.$2) != null) return;
    await download(it.subject, season: next.$1, episode: next.$2, episodes: it.episodeMap,
        quality: (int.tryParse(it.quality) ?? 0) > 720 ? 'high' : 'standard');
  }

  Future<void> deleteItems(Iterable<DownloadItem> list) async {
    for (final it in list.toList()) {
      await delete(it);
    }
  }

  /// Watched downloads of one title (or all titles).
  Future<int> deleteWatched([String? subjectId]) async {
    final gone = watchedItems.where((i) => subjectId == null || i.subjectId == subjectId).toList();
    await deleteItems(gone);
    return gone.length;
  }

  static (int, int)? _nextAfter(Map<int, List<int>> eps, int season, int episode) {
    final list = eps[season] ?? const [];
    final i = list.indexOf(episode);
    if (i >= 0 && i < list.length - 1) return (season, list[i + 1]);
    final nextSeason = eps[season + 1];
    return (nextSeason == null || nextSeason.isEmpty) ? null : (season + 1, nextSeason.first);
  }

  // ─── Plumbing ──────────────────────────────────────────────────────────────

  Future<Task?> _task(DownloadItem item) async {
    if (item.taskId.isEmpty) return null;
    return await FileDownloader().taskForId(item.taskId) ??
        (await FileDownloader().database.recordForId(item.taskId))?.task;
  }

  Future<void> _cancelTask(DownloadItem item) async {
    if (item.taskId.isEmpty) return;
    try {
      await FileDownloader().cancelTaskWithId(item.taskId);
      await FileDownloader().database.deleteRecordWithId(item.taskId);
    } catch (_) {}
  }

  DownloadItem? _byTask(Task task) =>
      items.firstWhereOrNull((i) => i.taskId == task.taskId) ??
      items.firstWhereOrNull((i) => i.key == task.metaData);

  Future<void> _onUpdate(TaskUpdate update) async {
    final item = _byTask(update.task);
    if (item == null) return;
    switch (update) {
      case TaskProgressUpdate():
        if (update.progress >= 0) item.data['progress'] = update.progress;
        if (update.expectedFileSize > 0) item.data['totalBytes'] = update.expectedFileSize;
        if (update.progress >= 0 && item.state != DownloadState.running) {
          item.data['state'] = DownloadState.running.name;
        }
        item.data['speed'] = update.networkSpeed;
        _put(item, persist: false);
      case TaskStatusUpdate():
        await _applyStatus(item, update.status, update.task, update.responseStatusCode);
    }
  }

  Future<void> _applyStatus(DownloadItem item, TaskStatus status, Task task, int? httpCode) async {
    switch (status) {
      case TaskStatus.enqueued:
        item.data['state'] = DownloadState.queued.name;
        item.data['waitingWifi'] = AppPrefs.to.wifiOnlyDownloads.value;
      case TaskStatus.running:
        item.data['state'] = DownloadState.running.name;
        item.data['waitingWifi'] = false;
      case TaskStatus.paused:
        item.data['state'] = DownloadState.paused.name;
      case TaskStatus.complete:
        item.data['state'] = DownloadState.complete.name;
        item.data['progress'] = 1.0;
        item.data['filePath'] = await task.filePath();
        try {
          item.data['totalBytes'] = await File(item.data['filePath'] as String).length();
        } catch (_) {}
      case TaskStatus.failed:
      case TaskStatus.notFound:
        // Signed CDN links expire: one automatic retry with a fresh link.
        if (item.data['autoRetried'] != true) {
          item.data['autoRetried'] = true;
          _put(item);
          unawaited(retry(item));
          return;
        }
        item.data['state'] = DownloadState.failed.name;
        item.data['error'] = httpCode != null ? 'Server error $httpCode' : 'Network error';
      case TaskStatus.canceled:
        return; // deletions remove the item themselves
      case TaskStatus.waitingToRetry:
        item.data['state'] = DownloadState.queued.name;
    }
    _put(item);
  }

  /// Picks up anything that changed while the app was closed.
  Future<void> _reconcile() async {
    final records = await FileDownloader().database.allRecords(group: _group);
    for (final r in records) {
      final item = _byTask(r.task);
      if (item == null) continue;
      await _applyStatus(item, r.status, r.task, null);
      if (r.progress >= 0 && r.status != TaskStatus.complete) item.data['progress'] = r.progress;
    }
    // A "complete" download whose file vanished (storage cleared) is gone.
    items.removeWhere((i) =>
        i.state == DownloadState.complete && (i.filePath == null || !File(i.filePath!).existsSync()));
    _persist();
  }

  void _put(DownloadItem item, {bool persist = true}) {
    final i = items.indexWhere((x) => x.key == item.key);
    if (i >= 0) {
      items[i] = item;
    } else {
      items.insert(0, item);
    }
    items.refresh();
    if (persist) _persist();
  }

  void _persist() => _s.write(_kItems, [for (final i in items) i.data]);
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  const gb = 1024 * 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  return '${(bytes / (1024 * 1024)).round()} MB';
}
