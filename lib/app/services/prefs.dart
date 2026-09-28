import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

/// App settings, persisted on the device and reactive for the settings UI.
class AppPrefs extends GetxService {
  static AppPrefs get to => Get.find<AppPrefs>();

  final GetStorage _s = GetStorage();

  static const _kAdult = 'pref_adult_enabled';
  static const _kAdultPin = 'pref_adult_pin';
  static const _kWifiOnly = 'pref_download_wifi_only';
  static const _kSmart = 'pref_smart_downloads';
  static const _kQuality = 'pref_download_quality';
  // Shared with the player, which owns the "Autoplay next episode" toggle.
  static const kAutoplay = 'user_pref_autoplay_next';

  /// 18+ ("Midnight") rows are shown only after an explicit, age-confirmed opt-in.
  late final RxBool adultEnabled = (_s.read(_kAdult) == true).obs;

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

  void setAdultEnabled(bool on) {
    adultEnabled.value = on;
    _s.write(_kAdult, on);
    if (!on) adultUnlocked.value = false;
  }

  /// Applies the account's setting from the server without re-uploading it.
  void applyRemoteAdult(bool on) {
    if (adultEnabled.value == on) return;
    setAdultEnabled(on);
  }

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
