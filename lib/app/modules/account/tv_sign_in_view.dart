import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app_theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/tv_focusable.dart';

/// TV sign-in, like Netflix's "Sign in with your phone": scan the QR (or open
/// the link and type the code) on a phone or computer that's signed in, and
/// this screen signs itself in once that's approved.
class TvSignInView extends StatefulWidget {
  const TvSignInView({super.key});

  @override
  State<TvSignInView> createState() => _TvSignInViewState();
}

class _TvSignInViewState extends State<TvSignInView> {
  final AuthService auth = AuthService.to;
  TvLinkSession? _session;
  String? _error;
  Timer? _poll;
  Timer? _tick;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _start();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _poll?.cancel();
    setState(() {
      _session = null;
      _error = null;
    });
    final s = await auth.startTvLink();
    if (!mounted) return;
    if (s == null) {
      setState(() => _error = "Couldn't reach NoonFlix accounts. Check the connection and try again.");
      return;
    }
    setState(() => _session = s);
    _poll = Timer.periodic(s.interval, (_) => _check());
  }

  Future<void> _check() async {
    final s = _session;
    if (s == null || _done) return;
    if (DateTime.now().isAfter(s.expiresAt)) {
      _poll?.cancel();
      setState(() {});
      return;
    }
    final status = await auth.pollTvLink(s);
    if (!mounted) return;
    if (status == TvLinkStatus.approved) {
      _done = true;
      _poll?.cancel();
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 1400));
      if (mounted) Get.back();
    } else if (status == TvLinkStatus.expired) {
      _poll?.cancel();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final expired = s != null && DateTime.now().isAfter(s.expiresAt);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.7, -0.8),
            radius: 1.4,
            colors: [kBrandPurple.withValues(alpha: 0.28), Theme.of(context).scaffoldBackgroundColor],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppLogo(size: 30),
            const SizedBox(height: 28),
            Expanded(
              child: _done
                  ? _Success(name: auth.user.value?.displayName)
                  : _error != null || expired
                      ? _Retry(message: _error ?? 'This code expired.', onRetry: _start)
                      : s == null
                          ? const Center(child: CircularProgressIndicator())
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Sign in with your phone',
                                          style: TextStyle(
                                              color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 22),
                                      _Step(n: 1, text: 'Scan the QR code with your phone camera'),
                                      _Step(n: 2, text: 'or open ${_host(s.verifyUrl)} and enter the code'),
                                      const _Step(
                                          n: 3,
                                          text: 'In the NoonFlix app: Settings → Sign in on a TV'),
                                      const SizedBox(height: 26),
                                      _Code(code: s.userCode),
                                      const SizedBox(height: 14),
                                      Text('Code expires in ${_left(s.expiresAt)}',
                                          style: const TextStyle(color: Colors.white54, fontSize: 14)),
                                      const SizedBox(height: 28),
                                      TvFocusable(
                                        autofocus: true,
                                        onSelect: Get.back,
                                        builder: (context, focused) => AnimatedContainer(
                                          duration: const Duration(milliseconds: 140),
                                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                                          decoration: BoxDecoration(
                                            color: focused ? Colors.white : Colors.white12,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text('Not now',
                                              style: TextStyle(
                                                  color: focused ? Colors.black : Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 48),
                                Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(color: kBrandPurple.withValues(alpha: 0.45), blurRadius: 40),
                                    ],
                                  ),
                                  child: QrImageView(
                                    data: s.verifyUrlComplete,
                                    size: 260,
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
            ),
          ],
        ),
      ),
    );
  }

  static String _host(String url) => Uri.tryParse(url)?.let((u) => '${u.host}${u.path}') ?? url;

  static String _left(DateTime at) {
    final d = at.difference(DateTime.now());
    if (d.isNegative) return '0:00';
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: const BoxDecoration(gradient: kBrandGradient, shape: BoxShape.circle),
              child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 14),
            Flexible(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 18))),
          ],
        ),
      );
}

class _Code extends StatelessWidget {
  const _Code({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(code,
            style: const TextStyle(
                color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: 8)),
      );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: const TextStyle(color: Colors.white70, fontSize: 20)),
            const SizedBox(height: 20),
            TvFocusable(
              autofocus: true,
              onSelect: onRetry,
              builder: (context, focused) => AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                decoration: BoxDecoration(
                  color: focused ? Colors.white : Colors.white12,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Get a new code',
                    style: TextStyle(
                        color: focused ? Colors.black : Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );
}

class _Success extends StatelessWidget {
  const _Success({this.name});
  final String? name;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF3DDC84), size: 84),
            const SizedBox(height: 16),
            Text(name == null ? "You're signed in" : 'Welcome, $name',
                style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Your list and progress are syncing to this TV.',
                style: TextStyle(color: Colors.white60, fontSize: 17)),
          ],
        ),
      );
}
