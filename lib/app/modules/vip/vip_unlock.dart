import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/device.dart';
import '../../services/vip_service.dart';
import '../../widgets/tv_focusable.dart';

/// Gate before playback / downloads: true when the viewer may go ahead now,
/// else offers the unlock (a rewarded ad on a phone, the phone on a TV) and
/// returns whether it worked.
Future<bool> ensureVipAccess() async {
  final vip = VipService.to;
  if (vip.hasAccess) return true;
  await vip.refresh(); // the time may have been earned on another device
  if (vip.hasAccess) return true;
  if (Device.isTv) {
    await Get.dialog(const _TvUnlockDialog());
  } else {
    await showVipSheet();
  }
  return vip.hasAccess;
}

/// The phone's VIP sheet: time left, and "Watch an ad" for more.
Future<void> showVipSheet() {
  return Get.bottomSheet(
    const _VipSheet(),
    backgroundColor: const Color(0xFF1F1F27),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
  );
}

class _VipSheet extends StatefulWidget {
  const _VipSheet();

  @override
  State<_VipSheet> createState() => _VipSheetState();
}

class _VipSheetState extends State<_VipSheet> {
  final VipService vip = VipService.to;
  String? _error;

  Future<void> _watch() async {
    setState(() => _error = null);
    final err = await vip.watchAd();
    if (!mounted) return;
    if (err == null) {
      Get.back();
      Get.snackbar('VIP unlocked', '${vip.minutesPerAd.value} minutes added — enjoy!',
          snackPosition: SnackPosition.BOTTOM, colorText: Colors.white);
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Obx(() {
          final left = vip.remaining;
          final minutes = vip.minutesPerAd.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(gradient: kBrandGradient, shape: BoxShape.circle),
                child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 14),
              Text(left == null ? 'Unlock VIP to keep watching' : 'You have VIP',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                left == null
                    ? 'Watch one short ad to get $minutes minutes of unlimited movies and shows.'
                    : '${formatRemaining(left)} left. Watch another ad to reset it to $minutes minutes.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
              ),
              if (left != null && vip.subscribed.value == false) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (left.inSeconds / (minutes * 60)).clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation(kBrandPurple),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: vip.loadingAd.value ? null : _watch,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.white70,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  icon: vip.loadingAd.value
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54))
                      : const Icon(Icons.play_circle_fill_rounded),
                  label: Text(vip.loadingAd.value ? 'Loading ad…' : 'Watch ad · +$minutes min'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: kBrandRed, fontSize: 13)),
              ],
              const SizedBox(height: 12),
              Text(
                AuthService.to.isSignedIn
                    ? 'VIP time is saved to your account, so it works on your TV too.'
                    : 'Sign in to use your VIP time on your TV too.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// TVs can't show ads: the time is earned on the phone and shared through
/// the account. "Check again" picks it up.
class _TvUnlockDialog extends StatefulWidget {
  const _TvUnlockDialog();

  @override
  State<_TvUnlockDialog> createState() => _TvUnlockDialogState();
}

class _TvUnlockDialogState extends State<_TvUnlockDialog> {
  final VipService vip = VipService.to;
  bool _checking = false;
  bool _stillLocked = false;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _stillLocked = false;
    });
    await vip.refresh();
    if (!mounted) return;
    if (vip.hasAccess) {
      Get.back();
      return;
    }
    setState(() {
      _checking = false;
      _stillLocked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = AuthService.to.user.value?.email ?? AuthService.to.user.value?.displayName ?? 'your account';
    Widget button(String label, VoidCallback onSelect, {bool autofocus = false}) => TvFocusable(
          autofocus: autofocus,
          onSelect: onSelect,
          builder: (context, focused) => AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: focused ? Colors.white : Colors.white12,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: TextStyle(
                    color: focused ? Colors.black : Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        );
    return Dialog(
      backgroundColor: const Color(0xFF1F1F27),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(gradient: kBrandGradient, shape: BoxShape.circle),
                child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 16),
              const Text('Unlock VIP on your phone',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(
                'Open NoonFlix on your phone, signed in as $name, and watch one short ad '
                '(My NoonFlix → VIP). This TV gets the same ${vip.minutesPerAd.value} minutes.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.45),
              ),
              if (_stillLocked) ...[
                const SizedBox(height: 12),
                const Text('No VIP time on your account yet.', style: TextStyle(color: kBrandRed, fontSize: 14)),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  button(_checking ? 'Checking…' : 'I watched it — check again', _check, autofocus: true),
                  const SizedBox(width: 12),
                  button('Close', Get.back),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small "VIP · 23 min" pill (or "Get VIP") that opens the sheet.
class VipChip extends StatelessWidget {
  const VipChip({super.key});

  @override
  Widget build(BuildContext context) {
    final vip = VipService.to;
    return Obx(() {
      if (vip.paywall.value != true) return const SizedBox.shrink();
      final left = vip.remaining;
      final label = vip.subscribed.value
          ? 'VIP'
          : left == null
              ? 'Get VIP'
              : 'VIP · ${formatRemaining(left)}';
      return Semantics(
        button: true,
        label: left == null ? 'Get VIP time' : 'VIP, ${formatRemaining(left)} left',
        excludeSemantics: true,
        child: InkWell(
          onTap: Device.isTv ? () => Get.dialog(const _TvUnlockDialog()) : showVipSheet,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: left != null || vip.subscribed.value ? kBrandGradient : null,
              border: left == null && !vip.subscribed.value ? Border.all(color: kBrandPurple) : null,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 5),
                Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
    });
  }
}
