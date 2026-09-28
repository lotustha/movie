import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'auth_service.dart';
import 'config.dart';
import 'device.dart';

/// VIP time: watching one rewarded ad gives [minutesPerAd] minutes of
/// playback. The time lives on the account (ani-nexus `movie_ad_unlocks`,
/// NoonFlix's own — separate from the other apps' — granted
/// by AdMob's signed server callback), so an ad watched on the phone unlocks
/// the TV too; the phone also starts the clock locally the moment the reward
/// is earned, so it never waits on the callback.
///
/// Whether playback needs VIP at all is the server's call (/access `paywall`):
/// with the paywall off everything plays and no ad is ever asked for.
class VipService extends GetxService {
  static VipService get to => Get.find<VipService>();

  final GetStorage _s = GetStorage();
  static const _kLocalUntil = 'vip_local_until';

  /// Server state (null until the first answer).
  final RxnBool paywall = RxnBool();
  final RxBool subscribed = false.obs; // a paid VIP subscription
  final Rxn<DateTime> serverUntil = Rxn<DateTime>(); // ad unlock on the account
  final Rxn<DateTime> subscriptionUntil = Rxn<DateTime>();
  final RxInt minutesPerAd = 30.obs;

  /// Earned on this phone, before (or without) the server confirming it.
  late final Rxn<DateTime> localUntil = Rxn<DateTime>(_readLocal());

  /// Ticks every 30 s so countdowns and [hasAccess] stay current.
  final Rx<DateTime> now = DateTime.now().obs;
  Timer? _tick;

  final RxBool loadingAd = false.obs;

  /// AdMob can't serve on Android TV; TVs unlock from a phone.
  static bool get adsSupported => !kIsWeb && Platform.isAndroid && !Device.isTv;

  /// AdMob test-device ids (MD5 of the Android ID, upper-case hex).
  static const _testDevices = [
    '99689748AF642F77163192E2DBF77246', // developer's Galaxy S25 Ultra
  ];

  static const _testRewardedUnit ='ca-app-pub-3940256099942544/5224354917';
  static String get _rewardedUnit => kReleaseMode ? AppConfig.rewardedAdUnit : _testRewardedUnit;

  @override
  void onInit() {
    super.onInit();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => now.value = DateTime.now());
    ever<String?>(AuthService.to.tokenRx, (_) => refresh());
    if (adsSupported) {
      // The developer's own phones get test ads from the real unit: watching
      // your own live ads counts as invalid traffic on the AdMob account.
      MobileAds.instance.updateRequestConfiguration(RequestConfiguration(testDeviceIds: _testDevices));
      MobileAds.instance.initialize();
    }
    refresh();
  }

  @override
  void onClose() {
    _tick?.cancel();
    super.onClose();
  }

  DateTime? _readLocal() {
    final ms = _s.read<int>(_kLocalUntil);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// The latest moment playback is paid for, from any source.
  DateTime? get until {
    final all = [localUntil.value, serverUntil.value, subscriptionUntil.value].whereType<DateTime>();
    if (all.isEmpty) return null;
    return all.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Time left, or null when none.
  Duration? get remaining {
    now.value; // reactive
    final u = until;
    if (u == null) return null;
    final left = u.difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  bool get isVip => subscribed.value || remaining != null;

  /// 18+ (Midnight) is for VIP subscribers only — never for time earned by
  /// watching an ad, so ads and adult content never meet. With the paywall
  /// off nothing is monetized and the viewer's own setting decides.
  bool get adultAllowed => subscribed.value || paywall.value == false;

  /// May play now. Unknown paywall state (offline, first launch) counts as
  /// free, so a network hiccup never locks anyone out.
  bool get hasAccess => paywall.value != true || isVip;

  Future<void> refresh() async {
    try {
      final r = await AuthService.to.dio.get('/api/mobile/v1/access', queryParameters: {'scope': 'movies'});
      final d = AuthService.dataOf(r);
      if (d == null) return;
      paywall.value = d['paywall'] == true;
      subscribed.value = d['vip'] == true;
      serverUntil.value = DateTime.tryParse('${d['adUnlockExpiresAt'] ?? ''}')?.toLocal();
      subscriptionUntil.value = DateTime.tryParse('${d['vipExpiresAt'] ?? ''}')?.toLocal();
      final m = (d['adUnlockMinutes'] as num?)?.toInt();
      if (m != null && m > 0) minutesPerAd.value = m;
      now.value = DateTime.now();
    } catch (e) {
      debugPrint('vip refresh: $e');
    }
  }

  /// Shows one rewarded ad. Returns null when the reward was earned, else a
  /// message for the viewer.
  Future<String?> watchAd() async {
    if (!adsSupported) return 'Ads play on the NoonFlix phone app.';
    if (loadingAd.value) return null;
    loadingAd.value = true;
    final done = Completer<String?>();
    var earned = false;
    final userId = AuthService.to.user.value?.id;
    RewardedAd.load(
      adUnitId: _rewardedUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          loadingAd.value = false;
          // Google echoes this to the server callback, which credits the
          // account (and so the viewer's TV).
          if (userId != null) {
            ad.setServerSideOptions(ServerSideVerificationOptions(userId: userId, customData: userId));
          }
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (!done.isCompleted) done.complete(earned ? null : 'Watch the whole ad to unlock VIP time.');
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              if (!done.isCompleted) done.complete("The ad couldn't be shown. Try again.");
            },
          );
          ad.show(onUserEarnedReward: (_, _) {
            earned = true;
            _grantLocal();
          });
        },
        onAdFailedToLoad: (error) {
          loadingAd.value = false;
          debugPrint('rewarded load failed: $error');
          if (!done.isCompleted) {
            done.complete(error.code == 3
                ? 'No ad is available right now. Try again in a minute.'
                : "The ad couldn't load. Check your connection and try again.");
          }
        },
      ),
    );
    final result = await done.future;
    if (result == null) _confirmOnServer();
    return result;
  }

  /// Starts the clock here at once. Like the server, an ad resets the window
  /// to a full [minutesPerAd] rather than stacking.
  void _grantLocal() {
    final u = DateTime.now().add(Duration(minutes: minutesPerAd.value));
    localUntil.value = u;
    _s.write(_kLocalUntil, u.millisecondsSinceEpoch);
    now.value = DateTime.now();
  }

  /// The signed callback lands on the server a few seconds after the ad;
  /// ask again so the account (and the TV) shows it.
  Future<void> _confirmOnServer() async {
    if (!AuthService.to.isSignedIn) return;
    try {
      await AuthService.to.dio
          .post('/api/mobile/v1/unlock/ad-reward', queryParameters: {'scope': 'movies'}, data: const {});
    } catch (_) {}
    for (final wait in const [3, 8, 20]) {
      await Future.delayed(Duration(seconds: wait));
      await refresh();
      if (serverUntil.value != null && serverUntil.value!.isAfter(DateTime.now())) return;
    }
  }
}

/// "12 min", "1 h 5 min".
String formatRemaining(Duration d) {
  final m = (d.inSeconds / 60).ceil();
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${m % 60} min';
}
