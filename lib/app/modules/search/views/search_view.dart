import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:movie/app/modules/home_screen/views/video_thumbnail.dart';
import 'package:movie/app/modules/search/controllers/search_controller.dart';
import 'package:movie/app/modules/search/views/search_tv_layout.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'dart:ui';

const kPrimaryColor = Color(0xFFE50914);
const kBackgroundColor = Color(0xFF141414);
const kSurfaceColor = Color(0xFF262626);
const kHeaderColor = Color(0xFF1A1A1A); // Slightly lighter than bg

class SearchView extends GetView<SearchViewController> {
  const SearchView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 1. TV Mode. Many Android TVs (e.g. BRAVIA) don't report
            // directional navigation, so a large Android screen counts too.
            final bool isTv = !kIsWeb &&
                (MediaQuery.of(context).navigationMode ==
                        NavigationMode.directional ||
                    (defaultTargetPlatform == TargetPlatform.android &&
                        constraints.maxWidth >= 900));
            controller.isTv.value = isTv;

            if (isTv) {
              return SearchTvLayout(controller: controller);
            }

            // 2. Desktop / Web Mode
            if (constraints.maxWidth >= 900) {
              return _DesktopWebLayout(controller: controller);
            }

            // 3. Mobile / Tablet Mode
            return _MobileLayout(controller: controller);
          },
        ),
      ),
    );
  }
}

// =============================================================================
// 1. DESKTOP / WEB LAYOUT (Stable Column Structure)
// =============================================================================
class _DesktopWebLayout extends StatefulWidget {
  final SearchViewController controller;
  const _DesktopWebLayout({required this.controller});

  @override
  State<_DesktopWebLayout> createState() => _DesktopWebLayoutState();
}

class _DesktopWebLayoutState extends State<_DesktopWebLayout> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Request focus on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      if (currentScroll >= maxScroll - 200) {
        widget.controller.loadMore();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // --- 1. Distinct Top Header ---
        Container(
          height: 80,
          color: kHeaderColor,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            children: [
              // Back Button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Get.back(),
                  borderRadius: BorderRadius.circular(50),
                  hoverColor: Colors.white10,
                  child: const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Icon(Icons.arrow_back, color: Colors.white70),
                  ),
                ),
              ),
              const SizedBox(width: 24),

              // Search Bar Container
              Expanded(
                // Wrap in TapRegion with groupId 1 to keep suggestions open when clicking here
                child: TapRegion(
                  groupId: 1,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: kSurfaceColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        const Icon(Icons.search, color: Colors.grey),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: widget.controller.searchController,
                            focusNode: _inputFocusNode,
                            autofocus: true,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16),
                            cursorColor: kPrimaryColor,
                            decoration: const InputDecoration(
                              hintText: 'Search titles, genres, people...',
                              hintStyle: TextStyle(color: Colors.grey),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onChanged: widget.controller.onSearchInputChanged,
                            onSubmitted: (_) {
                              widget.controller.submitSearch();
                              widget.controller.searchSuggestions.clear();
                            },
                          ),
                        ),
                        Obx(() => widget.controller.searchQuery.isNotEmpty
                            ? IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.grey, size: 20),
                          onPressed: () {
                            widget.controller.searchController.clear();
                            widget.controller.onSearchInputChanged('');
                            _inputFocusNode.requestFocus();
                          },
                        )
                            : const SizedBox.shrink()),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 40), // Balance spacing
            ],
          ),
        ),

        // --- 2. Main Content Area ---
        Expanded(
          child: Stack(
            clipBehavior: Clip.none, // Allow suggestions to overlap/float
            fit: StackFit.expand,
            children: [
              // Layer A: Results / History
              _buildResultsArea(),

              // Layer B: Suggestions Overlay (Floats on top)
              Obx(() {
                if (widget.controller.searchSuggestions.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  // Positioning logic:
                  // Header is 80px. Search bar is 48px high, centered.
                  // Search bar bottom is at y=64.
                  // This Stack starts at y=80.
                  // To touch the search bar bottom (y=64), we need top: -16.
                  // Added slight margin for aesthetics (-14).
                  top: -14,
                  // Left offset: 40 (pad) + 48 (back btn) + 24 (gap) = 112
                  left: 112,
                  right: 40,
                  child: TapRegion(
                    groupId: 1,
                    onTapOutside: (_) {
                      // Dismiss when clicking outside the group (Search Bar + Suggestions)
                      widget.controller.searchSuggestions.clear();
                      FocusManager.instance.primaryFocus?.unfocus();
                    },
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 400),
                      decoration: BoxDecoration(
                        color: kSurfaceColor,
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(8)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 12,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: widget.controller.searchSuggestions.length,
                        separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Colors.white10),
                        itemBuilder: (context, index) {
                          final item =
                          widget.controller.searchSuggestions[index];
                          return ListTile(
                            hoverColor: Colors.white10,
                            leading: const Icon(Icons.search,
                                color: Colors.grey, size: 20),
                            title: Text(
                              item.word ?? '',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 15),
                            ),
                            onTap: () {
                              widget.controller
                                  .onSuggestionSelected(item.word ?? '');
                              widget.controller.searchSuggestions.clear();
                            },
                          );
                        },
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultsArea() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Obx(() {
        // Loading Initial
        if (widget.controller.isLoading.value &&
            widget.controller.subjectsList.isEmpty) {
          return const Center(
              child: CircularProgressIndicator(color: kPrimaryColor));
        }

        // Empty Query (Show History)
        if (widget.controller.searchQuery.isEmpty &&
            widget.controller.subjectsList.isEmpty) {
          if (widget.controller.searchHistory.isNotEmpty) {
            return Padding(
              padding: const EdgeInsets.only(left: 60, top: 40),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: _ModernHistoryList(
                      controller: widget.controller, isTv: false),
                ),
              ),
            );
          }
          return _EmptyStatePlaceholder();
        }

        // No Results
        if (widget.controller.subjectsList.isEmpty &&
            widget.controller.searchQuery.isNotEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.search_off, size: 64, color: Colors.white24),
                const SizedBox(height: 16),
                Text(
                  "No results for '${widget.controller.searchQuery.value}'",
                  style: const TextStyle(color: Colors.grey, fontSize: 18),
                ),
              ],
            ),
          );
        }

        // Grid Content
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                "Results",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 60),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    childAspectRatio: 2 / 3,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: widget.controller.subjectsList.length,
                  itemBuilder: (context, index) {
                    final subject = widget.controller.subjectsList[index];
                    return _HoverablePoster(
                      subject: subject,
                      onTap: () => Get.toNamed('/subject-detail', arguments: subject.subjectId),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

// =============================================================================
// 3. MOBILE LAYOUT (Simple & Fast)
// =============================================================================
class _MobileLayout extends StatelessWidget {
  final SearchViewController controller;
  const _MobileLayout({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // App Bar
        Container(
          color: kBackgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: [
              const BackButton(color: Colors.white),
              Expanded(
                child: Container(
                  height: 45,
                  decoration: BoxDecoration(
                    color: kSurfaceColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: controller.searchController,
                    focusNode: controller.searchFocusNode,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search,
                          color: Colors.grey, size: 20),
                      suffixIcon: Obx(() =>
                      controller.searchQuery.value.isNotEmpty
                          ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: Colors.grey, size: 18),
                        onPressed: () {
                          controller.searchController.clear();
                          controller.onSearchInputChanged('');
                        },
                      )
                          : const SizedBox.shrink()),
                      hintText: 'Search...',
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                      border: InputBorder.none,
                      contentPadding:
                      const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: controller.onSearchInputChanged,
                    onSubmitted: (_) => controller.submitSearch(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),

        // Content
        Expanded(
          child: Obx(() {
            // Suggestions
            if (controller.searchSuggestions.isNotEmpty) {
              return ListView.separated(
                itemCount: controller.searchSuggestions.length,
                separatorBuilder: (_, __) =>
                const Divider(color: Colors.white10, height: 1),
                itemBuilder: (context, index) {
                  final item = controller.searchSuggestions[index];
                  return ListTile(
                    leading: const Icon(Icons.search, color: Colors.grey),
                    title: Text(item.word ?? '',
                        style: const TextStyle(color: Colors.white)),
                    onTap: () =>
                        controller.onSuggestionSelected(item.word ?? ''),
                  );
                },
              );
            }

            // Loading
            if (controller.isLoading.value) {
              return const Center(
                  child: CircularProgressIndicator(color: kPrimaryColor));
            }

            // History / Empty
            if (controller.subjectsList.isEmpty) {
              if (controller.searchHistory.isNotEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _ModernHistoryList(
                      controller: controller, isTv: false),
                );
              }
              return _EmptyStatePlaceholder();
            }

            // Results Grid
            return SmartRefresher(
              controller: controller.refreshController,
              enablePullDown: false,
              enablePullUp: true,
              onLoading: controller.loadMore,
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.62,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: controller.subjectsList.length,
                itemBuilder: (context, index) {
                  final subject = controller.subjectsList[index];
                  return GestureDetector(
                    onTap: () => Get.toNamed('/subject-detail', arguments: subject.subjectId),
                    child: VideoThumbnail(subject: subject),
                  );
                },
              ),
            );
          }),
        ),
      ],
    );
  }
}

// =============================================================================
// SHARED COMPONENTS
// =============================================================================

class _ModernHistoryList extends StatelessWidget {
  final SearchViewController controller;
  final bool isTv;
  const _ModernHistoryList({required this.controller, required this.isTv});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Searches',
                style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1),
              ),
              TextButton(
                onPressed: controller.clearSearchHistory,
                child: Text('CLEAR ALL',
                    style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: controller.searchHistory.length,
          itemBuilder: (context, index) {
            final query = controller.searchHistory[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history, color: Colors.white54),
              title: Text(query,
                  style: const TextStyle(color: Colors.white70, fontSize: 16)),
              onTap: () => controller.onSuggestionSelected(query),
              hoverColor: Colors.white10,
              focusColor: Colors.white10,
            );
          },
        ),
      ],
    );
  }
}

class _EmptyStatePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.movie_filter_outlined, size: 80, color: Colors.grey[800]),
          const SizedBox(height: 16),
          Text(
            "Search for your next favorite.",
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _HoverablePoster extends StatefulWidget {
  final dynamic subject;
  final VoidCallback onTap;

  const _HoverablePoster({required this.subject, required this.onTap});

  @override
  State<_HoverablePoster> createState() => _HoverablePosterState();
}

class _HoverablePosterState extends State<_HoverablePoster> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: _isHovered
                  ? [
                BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 15,
                    offset: const Offset(0, 10))
              ]
                  : null,
            ),
            child: VideoThumbnail(subject: widget.subject),
          ),
        ),
      ),
    );
  }
}