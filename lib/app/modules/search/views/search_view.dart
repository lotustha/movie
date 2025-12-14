import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:movie/app/modules/home_screen/views/video_thumbnail.dart';
import 'package:movie/app/modules/search/controllers/search_controller.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

// Assuming kPrimaryColor is defined elsewhere, e.g., in your theme file.
const kPrimaryColor = Colors.redAccent;

class SearchView extends GetView<SearchViewController> {
  const SearchView({super.key});

  @override
  Widget build(BuildContext context) {
    // Detect TV mode
    controller.isTv.value =
        MediaQuery.of(context).navigationMode == NavigationMode.directional &&
            !kIsWeb;

    // This is the main fix for the TV remote navigation.
    return WillPopScope(
      onWillPop: () async {
        // If the on-screen keyboard is focused...
        if (controller.isKeyboardFocused.value) {
          // ...explicitly unfocus the search input widget.
          controller.searchInputDisplayFocusNode.unfocus();
          // And prevent the app from closing.
          return false;
        }
        // Otherwise, allow the back button to pop the route.
        return true;
      },
      child: Shortcuts(
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.escape): const ActivateIntent(),
          LogicalKeySet(LogicalKeyboardKey.goBack): const ActivateIntent(),
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF141414),
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _SearchControlsPane()),
                Expanded(flex: 5, child: _SearchResultsPane()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Left Pane: Manages the search input display and on-screen keyboard.
class _SearchControlsPane extends GetView<SearchViewController> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Obx(() {
        final isNonTv = !controller.isTv.value;
        final showHistory = controller.searchQuery.value.isEmpty &&
            controller.searchHistory.isNotEmpty;
        final showSuggestions = controller.searchSuggestions.isNotEmpty;

        if (isNonTv) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StandardSearchTextField(),
              const SizedBox(height: 16),
              if (showSuggestions)
                Expanded(child: _SearchSuggestions())
              else if (showHistory)
                Expanded(child: _SearchHistory()),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SearchInputDisplay(),
            const SizedBox(height: 24),
            Expanded(
              child: Obx(() {
                if (showSuggestions) return _SearchSuggestions();
                if (controller.isKeyboardFocused.value) {
                  return _OnScreenKeyboard();
                }
                if (showHistory) return _SearchHistory();
                return const Center(
                  child: Text(
                    'Select the search bar to start typing.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }),
            ),
          ],
        );
      }),
    );
  }
}

/// Non-TV text field
class _StandardSearchTextField extends GetView<SearchViewController> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Search',
          style: Get.textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: controller.searchController,
          focusNode: controller.searchFocusNode,
          autofocus: true,
          onChanged: (_) => controller.loadSearchSuggestions(),
          onSubmitted: (_) => controller.submitSearch(),
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: InputDecoration(
            hintText: 'Search for titles, genres, people',
            hintStyle: const TextStyle(color: Colors.grey),
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            filled: true,
            fillColor: const Color(0xFF333333),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white, width: 2.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Right Pane
class _SearchResultsPane extends GetView<SearchViewController> {
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32.0, right: 32.0, bottom: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Obx(() {
            final hasQuery = controller.searchQuery.value.isNotEmpty;
            final hasResults = controller.subjectsList.isNotEmpty;
            String title;
            if (hasQuery) {
              title = 'Results for "${controller.searchQuery.value}"';
            } else if (hasResults) {
              title = 'Last Search Results';
            } else {
              title = 'Search';
            }
            return Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Get.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            );
          }),
          const SizedBox(height: 20),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value &&
                  controller.subjectsList.isEmpty) {
                return const Center(
                  child: CircularProgressIndicator(color: kPrimaryColor),
                );
              }
              if (controller.subjectsList.isEmpty &&
                  controller.searchQuery.isNotEmpty) {
                return Center(
                  child: Text(
                    'No results found for "${controller.searchQuery.value}".',
                    style: Get.textTheme.titleMedium
                        ?.copyWith(color: Colors.grey[400]),
                  ),
                );
              }
              if (controller.subjectsList.isEmpty) {
                return Center(
                  child: Text(
                    'Search for titles, genres, people.',
                    style: Get.textTheme.titleMedium
                        ?.copyWith(color: Colors.grey[400]),
                  ),
                );
              }
              return _buildResultsGrid();
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsGrid() {
    if (!controller.isTv.value) {
      return SmartRefresher(
        controller: controller.refreshController,
        enablePullDown: false,
        enablePullUp: true,
        onLoading: controller.loadMore,
        child: _buildGridView(),
      );
    }

    return Obx(() {
      final itemCount = controller.subjectsList.length +
          (controller.isMoreLoading.value ? 1 : 0);

      return GridView.builder(
        controller: _scrollController,
        gridDelegate:  SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: Get.width < 600 ? 2 : 4,
          childAspectRatio: 145 / 250,
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index >= controller.subjectsList.length) {
            return const Center(
                child: CircularProgressIndicator(color: kPrimaryColor));
          }
          final subject = controller.subjectsList[index];
          final isLastItem = index == controller.subjectsList.length - 1;

          return _FocusableGridItem(
            child: VideoThumbnail(subject: subject),
            onTap: () => controller.onResultTap(subject),
            onFocus: () {
              if (isLastItem) controller.loadMore();
              Scrollable.ensureVisible(
                context,
                duration: const Duration(milliseconds: 250),
                alignment: 0.3,
              );
            },
          );
        },
      );
    });
  }

  Widget _buildGridView() {
    return GridView.builder(
      controller: _scrollController,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 145 / 250,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: controller.subjectsList.length,
      itemBuilder: (context, index) {
        final subject = controller.subjectsList[index];
        return _FocusableGridItem(
          child: VideoThumbnail(subject: subject),
          onTap: () => controller.onResultTap(subject),
          onFocus: () {
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 250),
              alignment: 0.3,
            );
          },
        );
      },
    );
  }
}

/// Search input display (TV)
class _SearchInputDisplay extends GetView<SearchViewController> {
  @override
  Widget build(BuildContext context) {
    // This `Focus` widget is the second part of the fix.
    return Focus(
      focusNode: controller.searchInputDisplayFocusNode, // Connect the node
      autofocus: true,
      onFocusChange: (hasFocus) {
        controller.isKeyboardFocused.value = hasFocus;
      },
      child: Obx(() {
        final bool hasFocus = controller.isKeyboardFocused.value;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF333333),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasFocus ? Colors.white : Colors.transparent,
              width: 2.5,
            ),
            boxShadow: [
              if (hasFocus)
                BoxShadow(
                  color: Colors.redAccent.withOpacity(0.8),
                  blurRadius: 20,
                  spreadRadius: 2,
                )
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  controller.searchController.text.isEmpty && !hasFocus
                      ? 'Search for titles, genres, people'
                      : controller.searchController.text,
                  style: TextStyle(
                    color: controller.searchController.text.isEmpty && !hasFocus
                        ? Colors.grey
                        : Colors.white,
                    fontSize: 18,
                  ),
                ),
              ),
              if (hasFocus &&
                  DateTime.now().millisecondsSinceEpoch % 1000 > 500)
                Container(width: 2, height: 20, color: Colors.white),
            ],
          ),
        );
      }),
    );
  }
}

/// Focusable grid item with glow + auto-scroll
class _FocusableGridItem extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onFocus;

  const _FocusableGridItem({
    required this.child,
    required this.onTap,
    this.onFocus,
  });

  @override
  __FocusableGridItemState createState() => __FocusableGridItemState();
}

class __FocusableGridItemState extends State<_FocusableGridItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onFocusChange: (hasFocus) {
        setState(() => _isFocused = hasFocus);
        if (hasFocus && widget.onFocus != null) widget.onFocus!();
      },
      actions: {
        ActivateIntent:
        CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap()),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.transparent,
              width: 3.0,
            ),
            boxShadow: [
              if (_isFocused)
                BoxShadow(
                  color: Colors.redAccent.withOpacity(0.9),
                  blurRadius: 25,
                  spreadRadius: 4,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// A custom on-screen keyboard optimized for D-pad navigation.
class _OnScreenKeyboard extends GetView<SearchViewController> {
  final List<List<String>> _keys = const [
    ['A', 'B', 'C', 'D', 'E', 'F', 'G'],
    ['H', 'I', 'J', 'K', 'L', 'M', 'N'],
    ['O', 'P', 'Q', 'R', 'S', 'T', 'U'],
    ['V', 'W', 'X', 'Y', 'Z', ' ', 'DEL'],
    ['1', '2', '3', '4', '5', '6', '7'],
    ['8', '9', '0', '-', '_', '.', 'CLR'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _keys.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((key) {
            return _KeyboardKey(
              label: key,
              onTap: () => controller.onKeyTapped(key),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}

/// A single, focusable key for the on-screen keyboard.
class _KeyboardKey extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _KeyboardKey({required this.label, required this.onTap});

  @override
  __KeyboardKeyState createState() => __KeyboardKeyState();
}

class __KeyboardKeyState extends State<_KeyboardKey> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final bool isSpecialKey = widget.label.length > 1;
    return FocusableActionDetector(
      onFocusChange: (hasFocus) => setState(() => _isFocused = hasFocus),
      actions: {
        ActivateIntent:
        CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap()),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.2 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            margin: const EdgeInsets.all(4),
            width: isSpecialKey ? 80 : 50,
            height: 50,
            decoration: BoxDecoration(
              color: _isFocused ? Colors.white : const Color(0xFF4D4D4D),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                widget.label,
                style: TextStyle(
                  color: _isFocused ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: isSpecialKey ? 16 : 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A widget to display the list of search suggestions.
class _SearchSuggestions extends GetView<SearchViewController> {
  @override
  Widget build(BuildContext context) {
    return Obx(
          () => ListView.builder(
        itemCount: controller.searchSuggestions.length,
        itemBuilder: (context, index) {
          final suggestion = controller.searchSuggestions[index];
          return _FocusableSuggestionItem(
            text: suggestion.word ?? '',
            onTap: () => controller.selectSuggestion(suggestion.word ?? ''),
          );
        },
      ),
    );
  }
}

/// A single, focusable item in the search suggestions list.
class _FocusableSuggestionItem extends StatefulWidget {
  final String text;
  final VoidCallback onTap;

  const _FocusableSuggestionItem({required this.text, required this.onTap});

  @override
  __FocusableSuggestionItemState createState() =>
      __FocusableSuggestionItemState();
}

class __FocusableSuggestionItemState extends State<_FocusableSuggestionItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onFocusChange: (hasFocus) => setState(() => _isFocused = hasFocus),
      actions: {
        ActivateIntent:
        CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap()),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
          color:
          _isFocused ? Colors.white.withOpacity(0.2) : Colors.transparent,
          child: Text(
            widget.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}

/// A new widget to display the list of recent searches.
class _SearchHistory extends GetView<SearchViewController> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Searches',
              style:
              Get.textTheme.titleMedium?.copyWith(color: Colors.grey[400]),
            ),
            TextButton(
              onPressed: controller.clearSearchHistory,
              child: const Text('Clear', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Obx(
                () => ListView.builder(
              itemCount: controller.searchHistory.length,
              itemBuilder: (context, index) {
                final query = controller.searchHistory[index];
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => controller.searchFromHistory(query),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12.0, horizontal: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              query,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(Icons.history, color: Colors.grey[600]),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
