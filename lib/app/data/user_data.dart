import 'package:get_storage/get_storage.dart';

import '../model/subject_list.dart';

/// A local change the account sync should upload.
class UserDataChange {
  UserDataChange(this.kind, this.op, this.subjectId, [this.payload]);
  final String kind; // 'progress' | 'list'
  final String op; // 'put' | 'delete'
  final String subjectId;
  final Map<String, dynamic>? payload;
}

/// Local persistence for personalised rows: Continue Watching + My List.
/// Signed in, every change is also reported through [onChange] so the sync
/// service can mirror it to the account.
class UserData {
  static final GetStorage _s = GetStorage();
  static const String _kContinue = 'continue_watching';
  static const String _kMyList = 'my_list';

  static void Function(UserDataChange change)? onChange;

  /// The subject fields worth keeping (and syncing): enough to draw a poster,
  /// open the title and play it, without trailers/staff blowing up the size.
  static Map<String, dynamic> snapshot(Map<String, dynamic> subject) {
    const keep = [
      'subjectId', 'subjectType', 'title', 'description', 'releaseDate', 'duration',
      'genre', 'cover', 'countryName', 'imdbRatingValue', 'detailPath', 'subtitles',
      'hasResource', 'corner',
    ];
    final out = <String, dynamic>{
      for (final k in keep)
        if (subject[k] != null) k: subject[k],
    };
    final d = out['description'];
    if (d is String && d.length > 400) out['description'] = '${d.substring(0, 397)}...';
    return out;
  }

  // ── Continue Watching ────────────────────────────────────────────────────
  static List<Map<String, dynamic>> _rawContinue() =>
      (_s.read<List>(_kContinue) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  static Map<String, dynamic> _progressPayload(Map<String, dynamic> e) => {
        'subjectId': e['subjectId'],
        'subject': e['subject'],
        'season': e['season'] ?? 0,
        'episode': e['episode'] ?? 0,
        'positionSec': e['position'] ?? 0,
        'durationSec': e['duration'] ?? 0,
        'updatedAt': DateTime.fromMillisecondsSinceEpoch(
                (e['updatedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch)
            .toUtc()
            .toIso8601String(),
      };

  static void saveProgress(
    Subject subject, {
    required int season,
    required int episode,
    required int positionSec,
    required int durationSec,
  }) {
    final id = subject.subjectId;
    if (id == null) return;
    // One entry per title: a dub (its own MovieBox id) replaces the original's
    // entry and vice versa, instead of showing the title twice.
    final key = _titleKey(subject.toJson());
    final list = _rawContinue();
    final replaced = list
        .where((e) => e['subjectId'] != id && _titleKey(e['subject']) == key)
        .map((e) => '${e['subjectId']}')
        .toList();
    list.removeWhere((e) => e['subjectId'] == id || _titleKey(e['subject']) == key);
    final entry = {
      'subjectId': id,
      'subject': snapshot(subject.toJson()),
      'season': season,
      'episode': episode,
      'position': positionSec,
      'duration': durationSec,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    list.insert(0, entry);
    if (list.length > 20) list.removeRange(20, list.length);
    _s.write(_kContinue, list);
    for (final other in replaced) {
      onChange?.call(UserDataChange('progress', 'delete', other));
    }
    onChange?.call(UserDataChange('progress', 'put', id, _progressPayload(entry)));
  }

  static void removeContinue(String? id) {
    if (id == null) return;
    _s.write(_kContinue, _rawContinue()..removeWhere((e) => e['subjectId'] == id));
    onChange?.call(UserDataChange('progress', 'delete', id));
  }

  /// Continue Watching entries with their saved season/episode/position, most
  /// recent first and one per title — for the TV launcher's Play Next row.
  static List<Map<String, dynamic>> continueEntries() {
    final seen = <String>{};
    return [
      for (final e in _rawContinue())
        if (seen.add(_titleKey(e['subject']))) e,
    ];
  }

  /// Continue Watching, most recent first, one per title (older saved
  /// duplicates from language versions are skipped).
  static List<Subject> continueSubjects() {
    final seen = <String>{};
    return [
      for (final e in _rawContinue())
        if (seen.add(_titleKey(e['subject'])))
          Subject.fromJson(Map<String, dynamic>.from(e['subject'] as Map)),
    ];
  }

  /// Same show across its language versions: "Tavvai [Hindi]" and "Tavvai"
  /// (and dubs that keep the exact title) share a key. Title + year, so a
  /// remake with the same name stays separate.
  static String _titleKey(dynamic subject) {
    if (subject is! Map) return '';
    final title = '${subject['title'] ?? ''}'
        .replaceAll(RegExp(r'\s*\[[^\]]*\]'), '')
        .trim()
        .toLowerCase();
    if (title.isEmpty) return 'id:${subject['subjectId']}';
    final date = '${subject['releaseDate'] ?? ''}';
    return '$title|${date.length >= 4 ? date.substring(0, 4) : ''}';
  }

  /// Seconds left in the saved episode/movie, or null when unknown.
  static int? remainingSec(String? id) {
    if (id == null) return null;
    final e = _rawContinue().firstWhere(
      (x) => x['subjectId'] == id,
      orElse: () => const {},
    );
    final pos = (e['position'] as num?)?.toInt() ?? 0;
    final dur = (e['duration'] as num?)?.toInt() ?? 0;
    if (dur <= 0 || pos >= dur) return null;
    return dur - pos;
  }

  /// 0..1 watched fraction for a subject (0 when unknown).
  static double progressFraction(String? id) {
    if (id == null) return 0;
    final e = _rawContinue().firstWhere(
      (x) => x['subjectId'] == id,
      orElse: () => const {},
    );
    final pos = (e['position'] as num?)?.toDouble() ?? 0;
    final dur = (e['duration'] as num?)?.toDouble() ?? 0;
    if (dur <= 0) return 0;
    return (pos / dur).clamp(0.0, 1.0);
  }

  // ── My List ──────────────────────────────────────────────────────────────
  static List<Map<String, dynamic>> _rawMyList() =>
      (_s.read<List>(_kMyList) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  static List<Subject> myList() =>
      _rawMyList().map((e) => Subject.fromJson(e)).toList();

  static bool inMyList(String? id) =>
      id != null && _rawMyList().any((e) => e['subjectId'] == id);

  /// Adds or removes the subject; returns the new membership state.
  static bool toggleMyList(Subject subject) {
    final id = subject.subjectId;
    if (id == null) return false;
    final list = _rawMyList();
    final idx = list.indexWhere((e) => e['subjectId'] == id);
    if (idx >= 0) {
      list.removeAt(idx);
      _s.write(_kMyList, list);
      onChange?.call(UserDataChange('list', 'delete', id));
      return false;
    }
    final snap = snapshot(subject.toJson());
    list.insert(0, snap);
    _s.write(_kMyList, list);
    onChange?.call(UserDataChange('list', 'put', id, {'subjectId': id, 'subject': snap}));
    return true;
  }

  // ── Account sync ─────────────────────────────────────────────────────────

  /// Merges the account's state into this device. Progress: the newer of the
  /// two wins; My List: the server's additions and removals are applied.
  static void applyRemote({
    required List<Map<String, dynamic>> progress,
    required List<Map<String, dynamic>> list,
    required List<String> deletedProgress,
    required List<String> deletedList,
  }) {
    final cw = _rawContinue();
    for (final p in progress) {
      final id = '${p['subjectId']}';
      final remoteAt = DateTime.tryParse('${p['updatedAt']}')?.millisecondsSinceEpoch ?? 0;
      final i = cw.indexWhere((e) => e['subjectId'] == id);
      final localAt = i >= 0 ? (cw[i]['updatedAt'] as num?)?.toInt() ?? 0 : -1;
      if (remoteAt <= localAt) continue;
      final entry = {
        'subjectId': id,
        'subject': p['subject'],
        'season': (p['season'] as num?)?.toInt() ?? 0,
        'episode': (p['episode'] as num?)?.toInt() ?? 0,
        'position': (p['positionSec'] as num?)?.toInt() ?? 0,
        'duration': (p['durationSec'] as num?)?.toInt() ?? 0,
        'updatedAt': remoteAt,
      };
      if (i >= 0) cw.removeAt(i);
      cw.add(entry);
      // The detail page / player resume from this key.
      _s.write('progress_$id', {
        'season': entry['season'],
        'episode': entry['episode'],
        'position': entry['position'],
      });
    }
    cw.removeWhere((e) => deletedProgress.contains(e['subjectId']));
    for (final id in deletedProgress) {
      _s.remove('progress_$id');
    }
    cw.sort((a, b) => ((b['updatedAt'] as num?) ?? 0).compareTo((a['updatedAt'] as num?) ?? 0));
    if (cw.length > 20) cw.removeRange(20, cw.length);
    _s.write(_kContinue, cw);

    final ml = _rawMyList();
    for (final l in list.reversed) {
      final id = '${l['subjectId']}';
      if (ml.any((e) => e['subjectId'] == id) || l['subject'] is! Map) continue;
      ml.insert(0, Map<String, dynamic>.from(l['subject'] as Map));
    }
    ml.removeWhere((e) => deletedList.contains(e['subjectId']));
    _s.write(_kMyList, ml);
  }

  /// First sync after signing in: offer everything on this device.
  static void queueAllForUpload() {
    for (final e in _rawContinue().reversed) {
      onChange?.call(UserDataChange('progress', 'put', '${e['subjectId']}', _progressPayload(e)));
    }
    for (final s in _rawMyList().reversed) {
      final id = s['subjectId'];
      if (id == null) continue;
      onChange?.call(UserDataChange('list', 'put', '$id', {'subjectId': id, 'subject': snapshot(s)}));
    }
  }
}
