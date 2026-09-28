import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../app_theme.dart';
import '../../services/prefs.dart';
import '../../services/sync_service.dart';
import '../home_screen/controllers/home_screen_controller.dart';

/// Turning 18+ on needs an explicit age confirmation; turning it off doesn't.
/// The choice follows the account (ani-nexus `showAdultContent`).
Future<void> setAdultEnabled(bool on) async {
  final prefs = AppPrefs.to;
  if (on) {
    final ok = await Get.dialog<bool>(AlertDialog(
      backgroundColor: const Color(0xFF1F1F27),
      icon: const Icon(Icons.nightlight_round, color: kBrandPurple, size: 36),
      title: const Text('Show 18+ content?', style: TextStyle(color: Colors.white)),
      content: const Text(
        'Midnight contains sexually explicit movies and shows for adults only. '
        'Confirm that you are 18 or older and that viewing adult content is legal where you live.',
        style: TextStyle(color: Colors.white70, height: 1.4),
      ),
      actions: [
        TextButton(autofocus: true, onPressed: () => Get.back(result: false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kBrandRed),
          onPressed: () => Get.back(result: true),
          child: const Text("I'm 18 or older"),
        ),
      ],
    ));
    if (ok != true) return;
  }
  prefs.setAdultEnabled(on);
  SyncService.to.pushAdultSetting(on);
  if (Get.isRegistered<HomeScreenController>()) {
    final c = Get.find<HomeScreenController>();
    if (prefs.adultVisible) {
      c.fetchAdultFeed();
    } else {
      // Off: drop the Midnight rows and re-filter the regular feed.
      c.adultRows.clear();
      c.adultBanners.clear();
      c.fetchHomeFeed();
    }
  }
}

/// True when the 18+ rows may be shown now, asking for the PIN if needed.
Future<bool> requireAdultAccess() async {
  final prefs = AppPrefs.to;
  if (!prefs.adultEnabled.value) return false;
  if (prefs.adultVisible) return true;
  return unlockAdult();
}

Future<bool> unlockAdult() async {
  final pin = await _askPin('Enter your 18+ PIN');
  if (pin == null) return false;
  if (AppPrefs.to.checkAdultPin(pin)) {
    if (Get.isRegistered<HomeScreenController>()) Get.find<HomeScreenController>().fetchAdultFeed();
    return true;
  }
  Get.snackbar('Wrong PIN', 'Midnight stays locked.', snackPosition: SnackPosition.BOTTOM, colorText: Colors.white);
  return false;
}

Future<void> managePin() async {
  final prefs = AppPrefs.to;
  if (prefs.hasAdultPin) {
    final current = await _askPin('Enter your current PIN');
    if (current == null) return;
    if (!prefs.checkAdultPin(current)) {
      Get.snackbar('Wrong PIN', 'The PIN was not changed.', snackPosition: SnackPosition.BOTTOM, colorText: Colors.white);
      return;
    }
    final action = await Get.dialog<String>(SimpleDialog(
      backgroundColor: const Color(0xFF1F1F27),
      title: const Text('18+ PIN', style: TextStyle(color: Colors.white)),
      children: [
        SimpleDialogOption(
          onPressed: () => Get.back(result: 'change'),
          child: const Text('Change PIN', style: TextStyle(color: Colors.white, fontSize: 16)),
        ),
        SimpleDialogOption(
          onPressed: () => Get.back(result: 'remove'),
          child: const Text('Remove PIN', style: TextStyle(color: Colors.white, fontSize: 16)),
        ),
      ],
    ));
    if (action == 'remove') {
      prefs.setAdultPin(null);
      return;
    }
    if (action != 'change') return;
  }
  final first = await _askPin('Choose a 4-digit PIN');
  if (first == null) return;
  final second = await _askPin('Enter the PIN again');
  if (second == null) return;
  if (first != second) {
    Get.snackbar('PINs didn\'t match', 'Try again.', snackPosition: SnackPosition.BOTTOM, colorText: Colors.white);
    return;
  }
  prefs.setAdultPin(first);
  Get.snackbar('PIN set', 'Midnight is now locked with your PIN.',
      snackPosition: SnackPosition.BOTTOM, colorText: Colors.white);
}

Future<String?> _askPin(String title) {
  final ctrl = TextEditingController();
  return Get.dialog<String>(AlertDialog(
    backgroundColor: const Color(0xFF1F1F27),
    title: Text(title, style: const TextStyle(color: Colors.white)),
    content: TextField(
      controller: ctrl,
      autofocus: true,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 4,
      textAlign: TextAlign.center,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: Colors.white, fontSize: 28, letterSpacing: 16),
      decoration: const InputDecoration(counterText: '', hintText: '••••'),
      onSubmitted: (v) {
        if (v.length == 4) Get.back(result: v);
      },
    ),
    actions: [
      TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (ctrl.text.length == 4) Get.back(result: ctrl.text);
        },
        child: const Text('OK'),
      ),
    ],
  ));
}
