import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../app_theme.dart';
import '../../services/auth_service.dart';
import '../settings/settings_view.dart' show signIn;

/// Phone side of TV sign-in: type the code the TV shows.
class LinkTvView extends StatefulWidget {
  const LinkTvView({super.key, this.code});
  final String? code;

  @override
  State<LinkTvView> createState() => _LinkTvViewState();
}

class _LinkTvViewState extends State<LinkTvView> {
  late final TextEditingController _code = TextEditingController(text: widget.code ?? '');
  bool _busy = false;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    final code = _code.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (code.length != 8) {
      setState(() => _error = 'Enter the 8-character code from your TV.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await AuthService.to.approveTvLink(code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      _done = err == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Sign in on a TV'),
      ),
      body: Obx(() {
        if (!AuthService.to.isSignedIn) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Sign in on this phone first, then approve your TV.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 15)),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => signIn(context), child: const Text('Sign in with Google')),
                ],
              ),
            ),
          );
        }
        if (_done) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF3DDC84), size: 72),
                SizedBox(height: 12),
                Text('TV approved', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text('It will sign in within a few seconds.', style: TextStyle(color: Colors.white60)),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.connected_tv_rounded, color: kBrandPurple, size: 56),
            const SizedBox(height: 16),
            const Text('On your TV, open NoonFlix → Settings → Sign in. Enter the code it shows:',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4)),
            const SizedBox(height: 22),
            TextField(
              controller: _code,
              autofocus: widget.code == null,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              maxLength: 9,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]'))],
              style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 6),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'ABCD-EFGH',
                errorText: _error,
                filled: true,
                fillColor: const Color(0xFF17171E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => _approve(),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _busy ? null : _approve,
                style: FilledButton.styleFrom(backgroundColor: kBrandRed),
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Approve TV', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        );
      }),
    );
  }
}
