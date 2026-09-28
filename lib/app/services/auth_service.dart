import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Response;
import 'package:get_storage/get_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'config.dart';

/// The signed-in account on ani-nexus (mugenstream.fun).
class AccountUser {
  AccountUser({required this.id, this.name, this.email, this.image});

  factory AccountUser.fromJson(Map<String, dynamic> j) => AccountUser(
        id: '${j['id']}',
        name: j['name'] as String?,
        email: j['email'] as String?,
        image: j['image'] as String?,
      );

  final String id;
  final String? name;
  final String? email;
  final String? image;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email, 'image': image};

  String get displayName => (name?.trim().isNotEmpty ?? false) ? name!.trim() : (email ?? 'You');
}

/// A pending TV sign-in: the code the TV shows and the secret it polls with.
class TvLinkSession {
  TvLinkSession({
    required this.userCode,
    required this.deviceSecret,
    required this.verifyUrl,
    required this.verifyUrlComplete,
    required this.expiresAt,
    required this.interval,
  });

  final String userCode;
  final String deviceSecret;
  final String verifyUrl;
  final String verifyUrlComplete;
  final DateTime expiresAt;
  final Duration interval;
}

enum TvLinkStatus { pending, approved, expired, error }

/// Accounts on ani-nexus. Phones sign in with Google (the ID token goes to
/// better-auth, which answers with a bearer session token); a TV shows a code
/// and QR that a signed-in phone or browser approves.
class AuthService extends GetxService {
  static AuthService get to => Get.find<AuthService>();

  final GetStorage _s = GetStorage();
  static const _kToken = 'auth_token';
  static const _kUser = 'auth_user';

  late final RxnString _token = RxnString(_s.read<String>(_kToken));
  late final Rxn<AccountUser> user = Rxn<AccountUser>(_readUser());

  bool get isSignedIn => _token.value != null;
  RxnString get tokenRx => _token;
  String? get token => _token.value;

  late final Dio dio = Dio(BaseOptions(
    baseUrl: AppConfig.nexusApi,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    validateStatus: (s) => s != null && s < 500,
  ))
    ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      final t = _token.value;
      if (t != null && !o.headers.containsKey('Authorization')) {
        o.headers['Authorization'] = 'Bearer $t';
      }
      h.next(o);
    }, onResponse: (r, h) {
      // A revoked / expired session: drop it so the UI offers sign-in again.
      if (r.statusCode == 401 && _token.value != null && r.requestOptions.path.contains('/mobile/')) {
        _clear();
      }
      h.next(r);
    }));

  AccountUser? _readUser() {
    final raw = _s.read(_kUser);
    return raw is Map ? AccountUser.fromJson(Map<String, dynamic>.from(raw)) : null;
  }

  void _store(String token, AccountUser? u) {
    _token.value = token;
    _s.write(_kToken, token);
    if (u != null) {
      user.value = u;
      _s.write(_kUser, u.toJson());
    }
  }

  void _clear() {
    _token.value = null;
    user.value = null;
    _s.remove(_kToken);
    _s.remove(_kUser);
  }

  // ─── Google (phone) ────────────────────────────────────────────────────────

  bool _googleReady = false;

  Future<void> _initGoogle() async {
    if (_googleReady) return;
    await GoogleSignIn.instance.initialize(serverClientId: AppConfig.googleWebClientId);
    _googleReady = true;
  }

  /// Signs in with Google. Returns null on success, else a message to show.
  Future<String?> signInWithGoogle() async {
    try {
      await _initGoogle();
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) return 'Google did not return an ID token.';
      final r = await dio.post('/api/auth/sign-in/social', data: {
        'provider': 'google',
        'idToken': {'token': idToken},
      });
      final token = r.headers.value('set-auth-token');
      if (r.statusCode != 200 || token == null) {
        return _message(r.data) ?? 'Sign-in failed (${r.statusCode}).';
      }
      final u = r.data is Map && r.data['user'] is Map
          ? AccountUser.fromJson(Map<String, dynamic>.from(r.data['user']))
          : null;
      _store(token, u);
      await refreshMe();
      return null;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return 'Sign-in cancelled.';
      return e.description ?? 'Google sign-in failed.';
    } on DioException catch (e) {
      return 'Network error: ${e.message}';
    } catch (e) {
      debugPrint('signInWithGoogle: $e');
      return 'Sign-in failed.';
    }
  }

  /// Account details + profile settings; returns the profile map (or null).
  Future<Map<String, dynamic>?> refreshMe() async {
    if (!isSignedIn) return null;
    try {
      final r = await dio.get('/api/mobile/v1/me');
      final data = _data(r);
      if (data == null) return null;
      if (data['user'] is Map) {
        final u = AccountUser.fromJson(Map<String, dynamic>.from(data['user']));
        user.value = u;
        _s.write(_kUser, u.toJson());
      }
      return data['profile'] is Map ? Map<String, dynamic>.from(data['profile']) : null;
    } catch (e) {
      debugPrint('refreshMe: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      if (isSignedIn) await dio.post('/api/auth/sign-out', data: {});
    } catch (_) {}
    try {
      if (_googleReady) await GoogleSignIn.instance.signOut();
    } catch (_) {}
    _clear();
  }

  // ─── TV sign-in (device code) ──────────────────────────────────────────────

  Future<TvLinkSession?> startTvLink({String deviceName = 'Android TV'}) async {
    try {
      final r = await dio.post('/api/mobile/v1/tv-link/start', data: {'deviceName': deviceName});
      final d = _data(r);
      if (d == null) return null;
      return TvLinkSession(
        userCode: '${d['userCode']}',
        deviceSecret: '${d['deviceSecret']}',
        verifyUrl: '${d['verifyUrl']}',
        verifyUrlComplete: '${d['verifyUrlComplete'] ?? d['verifyUrl']}',
        expiresAt: DateTime.now().add(Duration(seconds: (d['expiresIn'] as num?)?.toInt() ?? 600)),
        interval: Duration(seconds: (d['interval'] as num?)?.toInt() ?? 3),
      );
    } catch (e) {
      debugPrint('startTvLink: $e');
      return null;
    }
  }

  /// One poll; on approval stores the session and returns [TvLinkStatus.approved].
  Future<TvLinkStatus> pollTvLink(TvLinkSession session) async {
    try {
      final r = await dio.post('/api/mobile/v1/tv-link/poll', data: {'deviceSecret': session.deviceSecret});
      final d = _data(r);
      if (d == null) return r.statusCode == 404 || r.statusCode == 410 ? TvLinkStatus.expired : TvLinkStatus.error;
      switch (d['status']) {
        case 'approved':
          final u = d['user'] is Map ? AccountUser.fromJson(Map<String, dynamic>.from(d['user'])) : null;
          _store('${d['token']}', u);
          await refreshMe();
          return TvLinkStatus.approved;
        case 'expired':
          return TvLinkStatus.expired;
        default:
          return TvLinkStatus.pending;
      }
    } catch (_) {
      return TvLinkStatus.error;
    }
  }

  /// A signed-in phone approves the code a TV shows. Null on success.
  Future<String?> approveTvLink(String code) async {
    if (!isSignedIn) return 'Sign in first.';
    try {
      final r = await dio.post('/api/mobile/v1/tv-link/approve', data: {'code': code.trim()});
      if (_data(r) != null) return null;
      return _message(r.data) ?? 'That code could not be approved.';
    } catch (e) {
      return 'Network error.';
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  /// `data` of an `{ok:true,data}` envelope, or null.
  static Map<String, dynamic>? _data(Response r) {
    final b = r.data;
    if (r.statusCode == 200 && b is Map && b['ok'] == true) {
      final d = b['data'];
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    }
    return null;
  }

  static Map<String, dynamic>? dataOf(Response r) => _data(r);

  static String? _message(dynamic body) {
    if (body is! Map) return null;
    final e = body['error'] ?? body['message'];
    if (e is String) return e;
    if (e is Map && e['message'] is String) return e['message'] as String;
    return null;
  }
}
