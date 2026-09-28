import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../model/subject_list.dart';

/// App settings, persisted on the device and reactive for the settings UI.
class AppPrefs extends GetxService {
  static AppPrefs get to => Get.find<AppPrefs>();

  final GetStorage _s = GetStorage();

  // v2: v1 could be switched on by the account's flag (set by another Mugen
  // app); now only an explicit, age-confirmed opt-in in this app counts.
  static const _kAdult = 'pref_adult_enabled_v2';
  static const _kAdultV1 = 'pref_adult_enabled';
  static const _kAdultPin = 'pref_adult_pin';
  static const _kWifiOnly = 'pref_download_wifi_only';
  static const _kSmart = 'pref_smart_downloads';
  static const _kQuality = 'pref_download_quality';
  static const _kLimit = 'pref_download_limit_gb';
  static const _kDeleteWatched = 'pref_delete_watched';
  // Shared with the player, which owns the "Autoplay next episode" toggle.
  static const kAutoplay = 'user_pref_autoplay_next';

  /// 18+ ("Midnight") rows are shown only after an explicit, age-confirmed opt-in.
  late final RxBool adultEnabled = RxBool(_s.read<bool>(_kAdult) ??
      // Carried over only where a PIN was set, i.e. the user opted in here.
      (_s.read(_kAdultV1) == true && (_s.read<String>(_kAdultPin) ?? '').isNotEmpty));

  /// Ids of titles seen in the 18+ tab. MovieBox doesn't tag all of them as
  /// adult (some are just "Drama"), so membership in that tab is what marks a
  /// title as 18+ for Continue Watching / My List / the launcher.
  late final Set<String> _adultIds = {...(_s.read<List>('adult_ids') ?? const []).map((e) => '$e')};

  void markAdultIds(Iterable<String> ids) {
    final before = _adultIds.length;
    _adultIds.addAll(ids);
    if (_adultIds.length == before) return;
    final list = _adultIds.toList();
    _s.write('adult_ids', list.length > 3000 ? list.sublist(list.length - 3000) : list);
  }

  /// A title from the 18+ tab, flagged adult, or tagged adult by MovieBox.
  bool isAdultJson(Map? subject) {
    if (subject == null) return false;
    if (subject['adult'] == true) return true;
    if (_adultIds.contains('${subject['subjectId']}')) return true;
    return isAdultTagged(subject['genre'] as String?, subject['title'] as String?);
  }

  /// sha256 of the optional 4-digit PIN that locks the 18+ section ('' = none).
  late final RxString _adultPinHash = (_s.read<String>(_kAdultPin) ?? '').obs;
  bool get hasAdultPin => _adultPinHash.value.isNotEmpty;

  /// Unlocked for the rest of this app session once the PIN was entered.
  final RxBool adultUnlocked = false.obs;

  late final RxBool wifiOnlyDownloads = (_s.read(_kWifiOnly) != false).obs;
  late final RxBool smartDownloads = (_s.read(_kSmart) != false).obs;

  /// 'high' (best available, up to 1080p) or 'standard' (smaller files).
  late final RxString downloadQuality = (_s.read<String>(_kQuality) ?? 'standard').obs;

  late final RxBool autoplayNext = (_s.read(kAutoplay) != false).obs;

  /// Space the downloads may use, in GB; 0 = no limit.
  late final RxInt downloadLimitGb = RxInt(_s.read<int>(_kLimit) ?? 0);

  /// What happens to a download once it's watched:
  /// 'immediately' — deleted when it ends; 'whenFull' — kept until the
  /// storage limit is reached, then the oldest watched go first; 'ask' —
  /// never deleted without asking.
  late final RxString deleteWatched = RxString(_s.read<String>(_kDeleteWatched) ?? 'whenFull');

  /// Detail page: episodes as a number grid instead of rows.
  late final RxBool episodeGrid = RxBool(_s.read<bool>('pref_episode_grid') ?? false);

  void setEpisodeGrid(bool on) {
    episodeGrid.value = on;
    _s.write('pref_episode_grid', on);
  }

  void setDownloadLimitGb(int gb) {
    downloadLimitGb.value = gb;
    _s.write(_kLimit, gb);
  }

  void setDeleteWatched(String mode) {
    deleteWatched.value = mode;
    _s.write(_kDeleteWatched, mode);
  }

  void setAdultEnabled(bool on) {
    adultEnabled.value = on;
    _s.write(_kAdult, on);
    if (!on) adultUnlocked.value = false;
  }

  /// The account's setting from the server can only turn 18+ OFF here;
  /// turning it on takes the age confirmation on this device.
  void applyRemoteAdult(bool on) {
    if (!on && adultEnabled.value) setAdultEnabled(false);
  }

  /// Titles MovieBox tags as adult. Kept out of the regular rows, search and
  /// the launcher channel unless 18+ is on.
  static final RegExp _adultTag = RegExp(r'(?<!young )adult|erotic|hentai|porn|18\+', caseSensitive: false);
  static bool isAdultTagged(String? genre, String? title) =>
      _adultTag.hasMatch(genre ?? '') || (title ?? '').contains('18+');

  bool hideAdult(String? genre, String? title) => !adultEnabled.value && isAdultTagged(genre, title);

  /// Keep [s] out of the regular rows / search: 18+ and 18+ is off.
  bool hideSubject(Subject s) =>
      !adultEnabled.value && (_adultIds.contains(s.subjectId) || isAdultTagged(s.genre, s.title));

  void setAdultPin(String? pin) {
    final hash = (pin == null || pin.isEmpty) ? '' : _hash(pin);
    _adultPinHash.value = hash;
    _s.write(_kAdultPin, hash);
    adultUnlocked.value = hash.isEmpty;
  }

  bool checkAdultPin(String pin) {
    final ok = hasAdultPin && _hash(pin) == _adultPinHash.value;
    if (ok) adultUnlocked.value = true;
    return ok;
  }

  /// Whether the 18+ rows may be shown right now.
  bool get adultVisible => adultEnabled.value && (!hasAdultPin || adultUnlocked.value);

  void setWifiOnly(bool on) {
    wifiOnlyDownloads.value = on;
    _s.write(_kWifiOnly, on);
  }

  void setSmartDownloads(bool on) {
    smartDownloads.value = on;
    _s.write(_kSmart, on);
  }

  void setDownloadQuality(String q) {
    downloadQuality.value = q;
    _s.write(_kQuality, q);
  }

  void setAutoplay(bool on) {
    autoplayNext.value = on;
    _s.write(kAutoplay, on);
  }

  static String _hash(String pin) => sha256.convert(utf8.encode('noonflix:$pin')).toString();
}
