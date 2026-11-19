import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/device.dart';
import '../../services/vip_service.dart';
import '../../widgets/tv_focusable.dart';
import '../account/tv_sign_in_view.dart';

/// Gate before playback / downloads: true when the viewer may go ahead now,
/// else offers the unlock (a rewarded ad on a phone, the phone on a TV) and
/// returns whether it worked.
Future<bool> ensureVipAccess() async {
  final vip = VipService.to;
  // First launch: the server hasn't said yet whether playback is gated. Ask
  // (briefly) rather than assume it is free.
  if (vip.paywall.value == null) {
    await vip.refresh().timeout(const Duration(seconds: 6), onTimeout: () {});
  }
  if (vip.hasAccess) return true;
  await vip.refresh(); // the time may have been earned on another device
  if (vip.hasAccess) return true;

  if (Device.isTv) {
    // A TV can't show ads: its time comes from the account, so it needs one.
    if (!AuthService.to.isSignedIn) {
      await Get.to(() => const TvSignInView(), transition: Transition.fadeIn);
      if (!AuthService.to.isSignedIn) return false;
      await vip.refresh();
      if (vip.hasAccess) return true;
    }
    await Get.dialog(const _TvUnlockDialog());
  } else {
    // A phone earns its time right here, with or without an account; the
    // sheet stays up through the ad and closes itself once it is earned.
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
  Timer? _tick;
  DateTime _now = DateTime.now();
  String? _error;

  /// Plays one rewarded ad with the sheet still up (the ad covers it), so a
  /// failure is shown here, and whoever opened the sheet (the Play button's
  /// gate) carries on only once the time is really earned.
  Future<void> _watch() async {
    if (vip.loadingAd.value) return;
    setState(() => _error = null);
    final err = await vip.watchAd();
    if (!mounted) return;
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Get.back();
    Get.snackbar('VIP unlocked', '${vip.minutesPerAd.value} minutes added. Enjoy!',
        snackPosition: SnackPosition.BOTTOM, colorText: Colors.white);
  }

  @override
  void initState() {
    super.initState();
    // One-second tick for the live countdown. VipService.remaining is the
    // source of truth; this just forces a rebuild each second so the digits
    // move. Cancelled in dispose so we never leak.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Live remaining derived from the service's `until` and our local clock.
  /// Mirrors VipService.remaining but uses the sheet's own tick so the UI
  /// updates every second instead of the service's 30 s cadence.
  Duration? get _remaining {
    final u = vip.until;
    if (u == null) return null;
    final left = u.difference(_now);
    return left.isNegative ? null : left;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Obx(() {
          // Subscribe to vip.now so a server refresh or an ad grant wakes us
          // even between our own ticks.
          vip.now.value;
          final left = _remaining;
          final subscribed = vip.subscribed.value;
          final hasTime = left != null;
          final loading = vip.loadingAd.value;
          final adIcon = loading
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
              : const Icon(Icons.play_circle_outline_rounded, size: 20);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 24),
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(gradient: kBrandGradient, shape: BoxShape.circle),
                child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 18),
              Text(subscribed ? 'VIP subscriber' : hasTime ? 'VIP active' : 'VIP',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
              if (subscribed)
                const Text('Your subscription is active.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4))
              else if (hasTime)
                _TimerDisplay(left)
              else ...[
                const Text('No VIP time right now.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: loading ? null : _watch,
                  icon: adIcon,
                  label: Text(loading ? 'Loading ad…' : 'Watch ad for ${vip.minutesPerAd.value} min'),
                  style: FilledButton.styleFrom(
                    backgroundColor: kBrandPurple,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: kBrandPurple.withValues(alpha: 0.5),
                    disabledForegroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
              if (hasTime && !subscribed) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (left.inSeconds / (vip.minutesPerAd.value * 60)).clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation(kBrandPurple),
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: loading ? null : _watch,
                  icon: adIcon,
                  label: Text(loading ? 'Loading ad…' : 'Reset to ${vip.minutesPerAd.value} min'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: kBrandRed, fontSize: 13)),
              ],
              const SizedBox(height: 20),
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

/// Large monospace countdown (H:MM:SS or MM:SS) with a subtle glow that
/// matches the brand gradient. Purely presentational — reads its duration
/// from the parent, no state of its own.
class _TimerDisplay extends StatelessWidget {
  const _TimerDisplay(this.duration);
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    final text = h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return ShaderMask(
      shaderCallback: (bounds) => kBrandGradient.createShader(bounds),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 42,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
            letterSpacing: 2,
            height: 1.1,
          )),
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
