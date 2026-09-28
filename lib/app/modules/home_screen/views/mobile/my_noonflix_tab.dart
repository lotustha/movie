import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../../app_theme.dart';
import '../../../../widgets/app_logo.dart';
import '../../controllers/home_screen_controller.dart';
import 'mobile_common.dart';
import 'mobile_home.dart' show ContinueTile;
import '../../../../services/auth_service.dart';
import '../../../../services/download_service.dart';
import '../../../downloads/downloads_view.dart';
import '../../../settings/settings_view.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Netflix's "My Netflix": what you're watching and your list, both kept on
/// this device.
class MyNoonFlixTab extends StatelessWidget {
  const MyNoonFlixTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<HomeScreenController>();
    final top = MediaQuery.paddingOf(context).top;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 600 ? 5 : 3;
    return Obx(() {
      final continuing = c.continueWatching.toList();
      final mine = c.myList.toList();
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, top + 8, 4, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('My NoonFlix',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: 'Search',
                    onPressed: openSearchTab,
                    icon: const Icon(Icons.search_rounded, color: Colors.white, size: 27),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () => Get.to(() => const SettingsView(), transition: Transition.rightToLeft),
                    icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 25),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: _ProfileHeader()),
          if (DownloadService.supported) const SliverToBoxAdapter(child: _DownloadsEntry()),
          if (continuing.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: RailTitle(
                'Continue Watching (${continuing.length})',
                action: TextButton(
                  onPressed: () => clearContinueWatching(),
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  child: const Text('Clear'),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 162 + 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: continuing.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ContinueTile(subject: continuing[i]),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
          SliverToBoxAdapter(
            child: RailTitle(mine.isEmpty ? 'My List' : 'My List (${mine.length})'),
          ),
          if (mine.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
                child: Column(
                  children: [
                    Icon(Icons.add_circle_outline_rounded,
                        color: kBrandPurple.withValues(alpha: 0.8), size: 48),
                    const SizedBox(height: 12),
                    const Text('Add shows and movies to your list to find them here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, fontSize: 14)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2 / 3,
                ),
                itemCount: mine.length,
                itemBuilder: (_, i) => LayoutBuilder(
                  builder: (_, box) =>
                      PosterTile(subject: mine[i], width: box.maxWidth, height: box.maxHeight),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Who's signed in (or an invitation to sign in and sync).
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.to;
    return Obx(() {
      final user = auth.user.value;
      final img = user?.image;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(
          children: [
            if (auth.isSignedIn)
              CircleAvatar(
                radius: 36,
                backgroundColor: kBrandPurple.withValues(alpha: 0.4),
                backgroundImage: img != null && img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
                child: img == null || img.isEmpty
                    ? Text(user!.displayName.characters.first.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800))
                    : null,
              )
            else
              const AppLogo(size: 64, showWordmark: false),
            const SizedBox(height: 10),
            Text(auth.isSignedIn ? user!.displayName : 'Not signed in',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            if (auth.isSignedIn)
              const Text('Your list and progress sync to all your devices',
                  style: TextStyle(color: Colors.white54, fontSize: 13))
            else ...[
              const Text('Saved on this device only',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => signIn(context),
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                icon: const Icon(Icons.login_rounded, size: 20),
                label: const Text('Sign in to sync'),
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _DownloadsEntry extends StatelessWidget {
  const _DownloadsEntry();

  @override
  Widget build(BuildContext context) {
    final svc = DownloadService.to;
    return Obx(() {
      final active = svc.activeCount;
      final count = svc.items.length;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
        child: Material(
          color: const Color(0xFF17171E),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Get.to(() => const DownloadsView(), transition: Transition.rightToLeft),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(gradient: kBrandGradient, shape: BoxShape.circle),
                    child: const Icon(Icons.download_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Downloads',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        Text(
                          active > 0
                              ? 'Downloading $active · $count total'
                              : count == 0
                                  ? 'Watch without the internet'
                                  : '$count saved · ${formatBytes(svc.usedBytes)}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
