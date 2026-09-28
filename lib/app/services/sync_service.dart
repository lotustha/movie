import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../data/user_data.dart';
import '../modules/home_screen/controllers/home_screen_controller.dart';
import 'auth_service.dart';
import 'prefs.dart';

/// Keeps Continue Watching, My List and the 18+ setting in step with the
/// account on ani-nexus. Local changes are queued (so they survive being
/// offline) and flushed shortly after they happen; the server's state is
/// pulled on start, on resume and after sign-in. Progress merges last-write-
/// wins on its timestamp; deletions travel as tombstones.
class SyncService extends GetxService with WidgetsBindingObserver {
  static SyncService get to => Get.find<SyncService>();

  final GetStorage _s = GetStorage();
  static const _kQueue = 'sync_queue';
  static const _kSince = 'sync_since';

  final RxBool syncing = false.obs;
  final Rxn<DateTime> lastSynced = Rxn<DateTime>();
  Timer? _flushTimer;

  AuthService get _auth => AuthService.to;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    UserData.onChange = _onLocalChange;
    // Signing in: bring the account's state down, then push what's local.
    ever<String?>(_auth.tokenRx, (t) {
      if (t != null) {
        _s.remove(_kSince);
        syncNow(initial: true);
      }
    });
    if (_auth.isSignedIn) syncNow();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _auth.isSignedIn) syncNow();
    if (state == AppLifecycleState.paused && _auth.isSignedIn) _flush();
  }

  // ─── Local → server ────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _queue() => (_s.read<List>(_kQueue) ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  void _onLocalChange(UserDataChange change) {
    final q = _queue();
    // Only the latest op per (kind, subject) matters.
    q.removeWhere((e) => e['kind'] == change.kind && e['subjectId'] == change.subjectId);
    q.add({
      'kind': change.kind,
      'op': change.op,
      'subjectId': change.subjectId,
      if (change.payload != null) 'payload': change.payload,
    });
    _s.write(_kQueue, q);
    if (!_auth.isSignedIn) return;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 3), _flush);
  }

  /// The user changed the 18+ setting on this device.
  Future<void> pushAdultSetting(bool show) async {
    if (!_auth.isSignedIn) return;
    try {
      await _auth.dio.post('/api/mobile/v1/settings/adult', data: {'show': show});
    } catch (e) {
      debugPrint('pushAdultSetting: $e');
    }
  }

  Future<void> _flush() async {
    if (!_auth.isSignedIn) return;
    final q = _queue();
    if (q.isEmpty) return;
    final done = <Map<String, dynamic>>[];
    final progress = [
      for (final e in q)
        if (e['kind'] == 'progress' && e['op'] == 'put') e,
    ];
    try {
      for (var i = 0; i < progress.length; i += 50) {
        final batch = progress.skip(i).take(50).toList();
        final r = await _auth.dio.post('/api/mobile/v1/movies/progress', data: {
          'items': [for (final e in batch) e['payload']],
        });
        if (AuthService.dataOf(r) == null) break;
        done.addAll(batch);
      }
      for (final e in q) {
        if (done.contains(e)) continue;
        final id = Uri.encodeQueryComponent('${e['subjectId']}');
        dynamic r;
        if (e['kind'] == 'progress' && e['op'] == 'delete') {
          r = await _auth.dio.delete('/api/mobile/v1/movies/progress?subjectId=$id');
        } else if (e['kind'] == 'list' && e['op'] == 'put') {
          r = await _auth.dio.post('/api/mobile/v1/movies/list', data: e['payload']);
        } else if (e['kind'] == 'list' && e['op'] == 'delete') {
          r = await _auth.dio.delete('/api/mobile/v1/movies/list?subjectId=$id');
        } else {
          continue;
        }
        // 4xx other than auth: the op is malformed / stale, drop it anyway.
        if (r.statusCode == 200 || (r.statusCode >= 400 && r.statusCode < 500 && r.statusCode != 401)) {
          done.add(e);
        }
      }
    } catch (e) {
      debugPrint('sync flush: $e'); // offline: keep the queue for later
    }
    if (done.isEmpty) return;
    // Ops queued while flushing stay (they aren't in `done`).
    final left = _queue()..removeWhere((e) => done.any((d) => _sameOp(d, e)));
    _s.write(_kQueue, left);
  }

  static bool _sameOp(Map a, Map b) =>
      a['kind'] == b['kind'] && a['subjectId'] == b['subjectId'] && a['op'] == b['op'];

  // ─── Server → local ────────────────────────────────────────────────────────

  Future<void> syncNow({bool initial = false}) async {
    if (!_auth.isSignedIn || syncing.value) return;
    syncing.value = true;
    try {
      await _flush();
      final since = _s.read<String>(_kSince);
      final r = await _auth.dio.get('/api/mobile/v1/movies/state',
          queryParameters: {if (since != null) 'since': since});
      final d = AuthService.dataOf(r);
      if (d != null) {
        UserData.applyRemote(
          progress: [
            for (final p in (d['progress'] as List? ?? const []))
              Map<String, dynamic>.from(p as Map),
          ],
          list: [
            for (final l in (d['list'] as List? ?? const []))
              Map<String, dynamic>.from(l as Map),
          ],
          deletedProgress: [
            for (final x in ((d['deleted'] as Map?)?['progress'] as List? ?? const [])) '$x',
          ],
          deletedList: [
            for (final x in ((d['deleted'] as Map?)?['list'] as List? ?? const [])) '$x',
          ],
        );
        if (d['serverTime'] != null) _s.write(_kSince, '${d['serverTime']}');
        lastSynced.value = DateTime.now();
        if (initial) {
          // First sync on this device: upload anything that predates sign-in.
          UserData.queueAllForUpload();
          await _flush();
        }
        if (Get.isRegistered<HomeScreenController>()) {
          Get.find<HomeScreenController>().refreshUserRows();
        }
      }
      final profile = await _auth.refreshMe();
      if (profile != null && profile['showAdultContent'] is bool) {
        AppPrefs.to.applyRemoteAdult(profile['showAdultContent'] as bool);
      }
    } catch (e) {
      debugPrint('syncNow: $e');
    } finally {
      syncing.value = false;
    }
  }
}
