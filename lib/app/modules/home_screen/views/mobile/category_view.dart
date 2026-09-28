import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../data/api_provider.dart';
import '../../../../data/trending_list.dart';
import '../../../../model/subject_list.dart';
import 'mobile_common.dart';

String _clean(String? name) => (name ?? '').replaceAll(RegExp(r'[\[\]]'), '');

/// Netflix's full-screen Categories list, built from the ranking categories.
Future<void> showCategoryPicker(BuildContext context) {
  return Get.generalDialog(
    barrierDismissible: true,
    barrierLabel: 'Categories',
    barrierColor: Colors.black.withValues(alpha: 0.88),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => const _CategoryPicker(),
    transitionBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
  );
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker();

  @override
  Widget build(BuildContext context) {
    final cats = TrendingList.trendingList.where((c) => c.id != null).toList();
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Stack(
          children: [
            ListView.builder(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 120),
              itemCount: cats.length,
              itemBuilder: (_, i) => InkWell(
                onTap: () {
                  Get.back();
                  Get.to(() => CategoryView(id: cats[i].id!, name: _clean(cats[i].name)),
                      transition: Transition.rightToLeft);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(_clean(cats[i].name),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 19, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Center(
                child: IconButton.filled(
                  tooltip: 'Close',
                  onPressed: Get.back,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: kInk,
                    minimumSize: const Size(60, 60),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One ranking category as a poster grid, paging in as you scroll.
class CategoryView extends StatefulWidget {
  const CategoryView({super.key, required this.id, required this.name});
  final String id;
  final String name;

  @override
  State<CategoryView> createState() => _CategoryViewState();
}

class _CategoryViewState extends State<CategoryView> {
  final ApiProvider _api = Get.find<ApiProvider>();
  final ScrollController _scroll = ScrollController();
  final List<Subject> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _done = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || (_done && !reset)) return;
    setState(() {
      _loading = true;
      _failed = false;
      if (reset) {
        _page = 1;
        _done = false;
      }
    });
    final response = await _api.getRankingList(id: widget.id, page: _page, perPage: 30);
    if (!mounted) return;
    final list = rankingSubjects(response);
    setState(() {
      _loading = false;
      if (response is Map && response['code'] != 0) {
        _failed = true;
        return;
      }
      if (reset) _items.clear();
      final fresh = (list ?? const []).map((e) => Subject.fromJson(Map<String, dynamic>.from(e as Map)));
      final before = _items.length;
      _items
        ..addAll(fresh)
        ..replaceRange(0, _items.length, dedupeTitles(_items));
      if (_items.length == before) _done = true;
      _page++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 600 ? 5 : 3;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Search',
            onPressed: () => Get.toNamed('/search'),
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: _items.isEmpty
            ? ListView(
                children: [
                  SizedBox(
                    height: 360,
                    child: Center(
                      child: _loading
                          ? const CircularProgressIndicator()
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_failed ? "Couldn't load this category." : 'Nothing here yet.',
                                    style: const TextStyle(color: Colors.white60)),
                                if (_failed)
                                  TextButton(onPressed: () => _load(reset: true), child: const Text('Retry')),
                              ],
                            ),
                    ),
                  ),
                ],
              )
            : GridView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2 / 3,
                ),
                itemCount: _items.length + (_done ? 0 : 1),
                itemBuilder: (context, i) {
                  if (i >= _items.length) {
                    return Center(
                      child: _failed
                          ? IconButton(
                              tooltip: 'Retry',
                              onPressed: _load,
                              icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
                            )
                          : const SizedBox(
                              width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  return LayoutBuilder(
                    builder: (_, box) => PosterTile(
                        subject: _items[i], width: box.maxWidth, height: box.maxHeight),
                  );
                },
              ),
      ),
    );
  }
}
