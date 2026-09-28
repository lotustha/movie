import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app_theme.dart';
import '../../data/user_data.dart';
import '../../services/auth_service.dart';
import '../../services/download_service.dart';
import '../../services/prefs.dart';
import '../../services/sync_service.dart';
import '../../widgets/tv_focusable.dart';
import '../account/link_tv_view.dart';
import '../account/tv_sign_in_view.dart';
import '../downloads/downloads_view.dart';
import '../home_screen/controllers/home_screen_controller.dart';
import 'adult_gate.dart';

bool _isTvWidth(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

/// App settings, for touch and for the TV remote alike: every row is a
/// [TvFocusable], so the D-pad walks the list and OK toggles/opens.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final tv = _isTvWidth(context);
    final prefs = AppPrefs.to;
    final auth = AuthService.to;
    final maxW = tv ? 760.0 : 640.0;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Obx(() {
            final signedIn = auth.isSignedIn;
            final user = auth.user.value;
            return ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, tv ? 48 : 32),
              children: [
                const _Header('Account'),
                if (!signedIn)
                  _Tile(
                    autofocus: true,
                    icon: Icons.account_circle_outlined,
                    title: 'Sign in',
                    subtitle: 'Sync My List and Continue Watching between your phone and TV.',
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                    onTap: () => signIn(context),
                  )
                else ...[
                  _AccountCard(user: user),
                  _Tile(
                    autofocus: true,
                    icon: Icons.sync_rounded,
                    title: 'Sync',
                    subtitle: _syncedLabel(),
                    trailing: SyncService.to.syncing.value
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : null,
                    onTap: SyncService.to.syncNow,
                  ),
                  if (!tv)
                    _Tile(
                      icon: Icons.connected_tv_rounded,
                      title: 'Sign in on a TV',
                      subtitle: 'Enter the code shown on your TV.',
                      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                      onTap: () => Get.to(() => const LinkTvView(), transition: Transition.rightToLeft),
                    ),
                  _Tile(
                    icon: Icons.logout_rounded,
                    title: 'Sign out',
                    onTap: () async {
                      final ok = await _confirm('Sign out?',
                          'My List and Continue Watching stay on this device.');
                      if (ok) await auth.signOut();
                    },
                  ),
                ],
                const _Header('Viewing activity'),
                _Tile(
                  icon: Icons.history_toggle_off_rounded,
                  title: 'Clear Continue Watching',
                  subtitle: signedIn
                      ? 'Removes every title from Continue Watching on all your devices.'
                      : 'Removes every title from Continue Watching on this device.',
                  onTap: () => clearContinueWatching(),
                ),
                if (prefs.adultEnabled.value)
                  _Tile(
                    icon: Icons.nightlight_round,
                    title: 'Clear Midnight Continue Watching',
                    subtitle: 'Removes the 18+ titles you started.',
                    onTap: () => clearContinueWatching(adult: true),
                  ),
                const _Header('Playback'),
                _SwitchTile(
                  icon: Icons.skip_next_rounded,
                  title: 'Autoplay next episode',
                  value: prefs.autoplayNext.value,
                  onChanged: prefs.setAutoplay,
                ),
                if (DownloadService.supported && !tv) ...[
                  const _Header('Downloads'),
                  _Tile(
                    icon: Icons.download_for_offline_outlined,
                    title: 'My Downloads',
                    subtitle:
                        '${DownloadService.to.items.length} saved · ${formatBytes(DownloadService.to.usedBytes)} used',
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                    onTap: () => Get.to(() => const DownloadsView(), transition: Transition.rightToLeft),
                  ),
                  _SwitchTile(
                    icon: Icons.wifi_rounded,
                    title: 'Wi-Fi only',
                    subtitle: 'Wait for Wi-Fi before downloading.',
                    value: prefs.wifiOnlyDownloads.value,
                    onChanged: prefs.setWifiOnly,
                  ),
                  _SwitchTile(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Smart Downloads',
                    subtitle: 'After you finish a downloaded episode, delete it and download the next one.',
                    value: prefs.smartDownloads.value,
                    onChanged: prefs.setSmartDownloads,
                  ),
                  _Tile(
                    icon: Icons.high_quality_rounded,
                    title: 'Download video quality',
                    subtitle: prefs.downloadQuality.value == 'high'
                        ? 'Higher — best picture, uses more storage'
                        : 'Standard — downloads faster, uses less storage',
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                    onTap: () => _pickQuality(prefs),
                  ),
                  if (DownloadService.to.items.isNotEmpty)
                    _Tile(
                      icon: Icons.delete_sweep_outlined,
                      title: 'Delete all downloads',
                      onTap: () async {
                        if (await _confirm('Delete all downloads?',
                            'Everything you downloaded will be removed from this device.')) {
                          await DownloadService.to.deleteAll();
                        }
                      },
                    ),
                ],
                const _Header('Content'),
                _SwitchTile(
                  icon: Icons.nightlight_round,
                  title: 'Show 18+ content',
                  subtitle: 'Adds the Midnight section for adults. Off by default.',
                  value: prefs.adultEnabled.value,
                  onChanged: (on) => setAdultEnabled(on),
                ),
                if (prefs.adultEnabled.value) ...[
                  _Tile(
                    icon: prefs.hasAdultPin ? Icons.lock_rounded : Icons.lock_open_rounded,
                    title: prefs.hasAdultPin ? 'Change or remove 18+ PIN' : 'Lock 18+ with a PIN',
                    subtitle: prefs.hasAdultPin
                        ? 'Midnight asks for your PIN once each time the app opens.'
                        : 'Ask for a 4-digit PIN before showing Midnight.',
                    onTap: () => managePin(),
                  ),
                  if (prefs.hasAdultPin && !prefs.adultUnlocked.value)
                    _Tile(
                      icon: Icons.key_rounded,
                      title: 'Unlock Midnight',
                      subtitle: 'Enter your PIN to show 18+ rows until the app closes.',
                      onTap: () => unlockAdult(),
                    ),
                ],
                const _Header('About'),
                const _VersionTile(),
              ],
            );
          }),
        ),
      ),
    );
  }

  static String _syncedLabel() {
    final t = SyncService.to.lastSynced.value;
    // Sync runs by itself (on open, on return, a few seconds after a change);
    // the row forces one now.
    final when = t == null ? 'not yet on this device' : 'last at ${DateFormat('h:mm a').format(t)}';
    return 'Automatic — $when. Tap to sync now.';
  }
}

/// Signs in: Google on a phone, a code / QR on a TV.
Future<void> signIn(BuildContext context) async {
  if (_isTvWidth(context)) {
    await Get.to(() => const TvSignInView(), transition: Transition.fadeIn);
    return;
  }
  Get.dialog(const Center(child: CircularProgressIndicator()), barrierDismissible: false);
  final error = await AuthService.to.signInWithGoogle();
  if (Get.isDialogOpen ?? false) Get.back();
  if (error != null) {
    Get.snackbar('Sign-in', error, snackPosition: SnackPosition.BOTTOM, colorText: Colors.white);
  } else {
    Get.snackbar('Signed in', 'Welcome, ${AuthService.to.user.value?.displayName ?? ''}',
        snackPosition: SnackPosition.BOTTOM, colorText: Colors.white);
  }
}

/// Asks, then empties Continue Watching (regular or the 18+ one).
Future<void> clearContinueWatching({bool adult = false}) async {
  final ok = await _confirm(
    adult ? 'Clear Midnight Continue Watching?' : 'Clear Continue Watching?',
    'Titles you started will leave the row and start from the beginning next time.',
  );
  if (!ok) return;
  final n = UserData.clearContinue(adult: adult);
  if (Get.isRegistered<HomeScreenController>()) Get.find<HomeScreenController>().refreshUserRows();
  Get.snackbar('Continue Watching', n == 0 ? 'Nothing to clear.' : 'Cleared $n title${n == 1 ? '' : 's'}.',
      snackPosition: SnackPosition.BOTTOM, colorText: Colors.white);
}

Future<void> _pickQuality(AppPrefs prefs) async {
  final choice = await Get.dialog<String>(SimpleDialog(
    backgroundColor: const Color(0xFF1F1F27),
    title: const Text('Download video quality', style: TextStyle(color: Colors.white)),
    children: [
      for (final (value, label, sub) in const [
        ('standard', 'Standard', 'Downloads faster and uses less storage'),
        ('high', 'Higher', 'Best picture, uses more storage'),
      ])
        SimpleDialogOption(
          onPressed: () => Get.back(result: value),
          child: ListTile(
            leading: Icon(
              prefs.downloadQuality.value == value ? Icons.radio_button_checked : Icons.radio_button_off,
              color: kBrandPurple,
            ),
            title: Text(label, style: const TextStyle(color: Colors.white)),
            subtitle: Text(sub, style: const TextStyle(color: Colors.white60)),
          ),
        ),
    ],
  ));
  if (choice != null) prefs.setDownloadQuality(choice);
}

Future<bool> _confirm(String title, String body) async {
  final ok = await Get.dialog<bool>(AlertDialog(
    backgroundColor: const Color(0xFF1F1F27),
    title: Text(title, style: const TextStyle(color: Colors.white)),
    content: Text(body, style: const TextStyle(color: Colors.white70)),
    actions: [
      TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
      FilledButton(autofocus: true, onPressed: () => Get.back(result: true), child: const Text('OK')),
    ],
  ));
  return ok == true;
}

// ─── Pieces ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.autofocus = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        button: true,
        label: title,
        child: TvFocusable(
          autofocus: autofocus && _isTvWidth(context),
          onSelect: onTap,
          builder: (context, focused) => AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: focused ? Colors.white : const Color(0xFF17171E),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(icon, color: focused ? kInkDark : Colors.white70, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: focused ? kInkDark : Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            style: TextStyle(
                                color: focused ? Colors.black54 : Colors.white54, fontSize: 12.5)),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  IconTheme(
                    data: IconThemeData(color: focused ? kInkDark : Colors.white54),
                    child: trailing!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const Color kInkDark = Color(0xFF111114);

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Tile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => onChanged(!value),
      trailing: ExcludeFocus(
        child: Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: kBrandPurple,
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user});
  final AccountUser? user;

  @override
  Widget build(BuildContext context) {
    final img = user?.image;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          kBrandPurple.withValues(alpha: 0.35),
          kBrandRed.withValues(alpha: 0.25),
        ]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white24,
            backgroundImage: img != null && img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
            child: img == null || img.isEmpty
                ? Text((user?.displayName ?? '?').characters.first.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user?.displayName ?? 'Signed in',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                if (user?.email != null)
                  Text(user!.email!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionTile extends StatelessWidget {
  const _VersionTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) => _Tile(
        icon: Icons.info_outline_rounded,
        title: 'Noon Flix',
        subtitle: snap.hasData ? 'Version ${snap.data!.version} (${snap.data!.buildNumber})' : null,
        onTap: () {},
      ),
    );
  }
}

/// Make sure a key press on a settings tile never reaches the page behind.
class SettingsShortcuts extends StatelessWidget {
  const SettingsShortcuts({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
        shortcuts: const {SingleActivator(LogicalKeyboardKey.select): ActivateIntent()},
        child: child,
      );
}

/// Loads the 18+ rows as soon as they may be shown.
void ensureAdultFeed() {
  if (AppPrefs.to.adultVisible && Get.isRegistered<HomeScreenController>()) {
    Get.find<HomeScreenController>().fetchAdultFeed();
  }
}
