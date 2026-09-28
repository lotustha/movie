import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../../app_theme.dart';
import '../../../../data/api_provider.dart';
import '../../../../model/subject_list.dart';
import '../../../../services/prefs.dart';
import '../../controllers/home_screen_controller.dart';
import 'mobile_common.dart';

/// The site's browse facets (themoviebox.xyz /web/film and /web/tv-series).
class _Facet {
  const _Facet(this.key, this.label, this.options);
  final String key; // query parameter for /filter
  final String label;
  final List<String> options; // first is the "any" value
}

const _genres = [
  'All', 'Action', 'Adventure', 'Animation', 'Biography', 'Comedy', 'Crime', 'Documentary',
  'Drama', 'Family', 'Fantasy', 'Film-Noir', 'Game-Show', 'History', 'Horror', 'Music',
  'Musical', 'Mystery', 'News', 'Reality-TV', 'Romance', 'Sci-Fi', 'Short', 'Sport',
  'Talk-Show', 'Thriller', 'War', 'Western', 'Other',
];
const _countries = [
  'All', 'United States', 'United Kingdom', 'Korea', 'Japan', 'Bangladesh', 'China', 'Egypt',
  'France', 'Germany', 'India', 'Indonesia', 'Iraq', 'Italy', 'Ivory Coast', 'Kenya', 'Lebanon',
  'Mexico', 'Morocco', 'Nigeria', 'Pakistan', 'Philippines', 'Russia', 'Saudi Arabia',
  'South Africa', 'Spain', 'Syria', 'Thailand', 'Malaysia', 'Turkey', 'Other',
];
const _years = [
  'All', '2026', '2025', '2024', '2023', '2022', '2021', '2020', '2010s', '2000s', '1990s',
  '1980s', 'Other',
];
const _languages = [
  'All', 'English dub', 'French dub', 'Hindi dub', 'Bengali dub', 'Urdu dub', 'Punjabi dub',
  'Tamil dub', 'Telugu dub', 'Malayalam dub', 'Kannada dub', 'Arabic dub', 'Arabic sub',
  'Tagalog dub', 'Indonesian dub', 'Russian dub', 'Kurdish sub', 'Spanish dub', 'Spanish sub',
  'SpanishLatam dub',
];
const _sorts = ['ForYou', 'Hottest', 'Latest', 'Rating'];
const _sortLabels = {'ForYou': 'For You', 'Hottest': 'Hottest', 'Latest': 'Latest', 'Rating': 'Top Rated'};

const _facets = [
  _Facet('genre', 'Genre', _genres),
  _Facet('country', 'Country', _countries),
  _Facet('year', 'Year', _years),
  _Facet('classify', 'Language', _languages),
];

enum _Kind { all, movie, tv }

/// Netflix's Search tab, with the site's filters: type, genre, country, year,
/// language and sort. With words it searches (and narrows the results by the
/// filters); with only filters it browses the whole catalogue.
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final ApiProvider _api = Get.find<ApiProvider>();
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;

  _Kind _kind = _Kind.all;
  final Map<String, String> _picked = {}; // facet key → value (absent = All)
  String _sort = 'ForYou';

  final List<Subject> _results = [];
  bool _loading = false;
  bool _hasMore = false;
  int _page = 1;
  int _request = 0; // drops answers to superseded queries

  String get _query => _text.text.trim();
  bool get _filtering => _picked.isNotEmpty || _kind != _Kind.all || _sort != 'ForYou';
  bool get _idle => _query.isEmpty && !_filtering;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _load(more: true);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load());
    setState(() {});
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_loading || !_hasMore)) return;
    if (_idle) {
      setState(() {
        _results.clear();
        _hasMore = false;
      });
      return;
    }
    final req = ++_request;
    setState(() {
      _loading = true;
      if (!more) {
        _page = 1;
        _results.clear();
      }
    });
    final page = more ? _page + 1 : 1;
    List<Subject> items;
    bool hasMore;
    if (_query.isNotEmpty) {
      final raw = await _api.searchMovies(_query,
          page: page, subjectType: switch (_kind) { _Kind.movie => 1, _Kind.tv => 2, _Kind.all => 0 });
      items = [for (final e in (raw as List)) Subject.fromJson(Map<String, dynamic>.from(e as Map))]
          .where(_matchesFacets)
          .toList();
      hasMore = (raw).length >= 20;
      items = _sorted(items);
    } else {
      // Browse: the filter endpoint is per type, so "All" merges both.
      final types = switch (_kind) { _Kind.movie => ['movie'], _Kind.tv => ['tv'], _Kind.all => ['movie', 'tv'] };
      final pages = await Future.wait(types.map((t) => _api.browse(
            type: t,
            genre: _picked['genre'],
            country: _picked['country'],
            year: _picked['year'],
            classify: _picked['classify'],
            sort: _sort == 'ForYou' ? null : _sort,
            page: page,
            perPage: types.length == 1 ? 24 : 12,
          )));
      items = [];
      final longest = pages.fold<int>(0, (m, p) => p.items.length > m ? p.items.length : m);
      for (var i = 0; i < longest; i++) {
        for (final p in pages) {
          if (i < p.items.length) items.add(p.items[i]);
        }
      }
      hasMore = pages.any((p) => p.hasMore);
    }
    if (!mounted || req != _request) return;
    final prefs = AppPrefs.to;
    setState(() {
      _loading = false;
      _page = page;
      _hasMore = hasMore && items.isNotEmpty;
      _results.addAll(dedupeTitles(items.where((s) => !prefs.hideSubject(s))
          .where((s) => !_results.any((r) => r.subjectId == s.subjectId))));
    });
  }

  /// Keyword results narrowed by the chosen facets (the search API itself
  /// only filters by type).
  bool _matchesFacets(Subject s) {
    final g = _picked['genre'];
    if (g != null && !(s.genre ?? '').toLowerCase().contains(g.toLowerCase())) return false;
    final c = _picked['country'];
    if (c != null && (s.countryName ?? '') != c) return false;
    final y = _picked['year'];
    if (y != null) {
      final year = int.tryParse((s.releaseDate ?? '').split('-').first) ?? 0;
      final ok = switch (y) {
        '2010s' => year >= 2010 && year <= 2019,
        '2000s' => year >= 2000 && year <= 2009,
        '1990s' => year >= 1990 && year <= 1999,
        '1980s' => year >= 1980 && year <= 1989,
        'Other' => year > 0 && year < 1980,
        _ => '$year' == y,
      };
      if (!ok) return false;
    }
    return true;
  }

  List<Subject> _sorted(List<Subject> list) {
    switch (_sort) {
      case 'Latest':
        return list..sort((a, b) => (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''));
      case 'Rating':
        double r(Subject s) => double.tryParse(s.imdbRatingValue ?? '') ?? 0;
        return list..sort((a, b) => r(b).compareTo(r(a)));
      default:
        return list;
    }
  }

  Future<void> _pickFacet(_Facet f) async {
    final current = _picked[f.key] ?? f.options.first;
    final choice = await _optionsSheet(f.label, f.options, current, (o) => o);
    if (choice == null) return;
    setState(() => choice == f.options.first ? _picked.remove(f.key) : _picked[f.key] = choice);
    _load();
  }

  Future<void> _pickSort() async {
    final choice = await _optionsSheet('Sort by', _sorts, _sort, (o) => _sortLabels[o] ?? o);
    if (choice == null) return;
    setState(() => _sort = choice);
    _load();
  }

  void _reset() {
    setState(() {
      _picked.clear();
      _kind = _Kind.all;
      _sort = 'ForYou';
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 600 ? 5 : 3;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, top + 10, 16, 8),
          child: TextField(
            controller: _text,
            onChanged: (_) => _changed(),
            onSubmitted: (_) => _load(),
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            cursorColor: kBrandPurple,
            decoration: InputDecoration(
              hintText: 'Search shows, movies, genres…',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
              suffixIcon: _text.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _text.clear();
                        _changed();
                      },
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                    ),
              filled: true,
              fillColor: const Color(0xFF26262E),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            children: [
              for (final k in _Kind.values) ...[
                _FilterChip(
                  label: switch (k) { _Kind.all => 'All', _Kind.movie => 'Movies', _Kind.tv => 'TV Shows' },
                  selected: _kind == k,
                  onTap: () {
                    setState(() => _kind = k);
                    _load();
                  },
                ),
                const SizedBox(width: 6),
              ],
              for (final f in _facets) ...[
                _FilterChip(
                  label: _picked[f.key] ?? f.label,
                  selected: _picked.containsKey(f.key),
                  dropdown: true,
                  onTap: () => _pickFacet(f),
                ),
                const SizedBox(width: 6),
              ],
              _FilterChip(
                label: _sort == 'ForYou' ? 'Sort' : _sortLabels[_sort]!,
                selected: _sort != 'ForYou',
                dropdown: true,
                icon: Icons.sort_rounded,
                onTap: _pickSort,
              ),
              if (_filtering) ...[
                const SizedBox(width: 6),
                _FilterChip(label: 'Reset', icon: Icons.restart_alt_rounded, onTap: _reset),
              ],
            ],
          ),
        ),
        Expanded(
          child: _idle
              ? const _TopSearches()
              : _results.isEmpty
                  ? Center(
                      child: _loading
                          ? const CircularProgressIndicator()
                          : Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                _query.isEmpty
                                    ? 'No titles match these filters.'
                                    : 'No results for "$_query"${_filtering ? ' with these filters' : ''}.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white54, fontSize: 15),
                              ),
                            ),
                    )
                  : GridView.builder(
                      controller: _scroll,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2 / 3,
                      ),
                      itemCount: _results.length + (_hasMore ? 1 : 0),
                      itemBuilder: (_, i) => i >= _results.length
                          ? const Center(
                              child: SizedBox(
                                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                          : LayoutBuilder(
                              builder: (_, box) =>
                                  PosterTile(subject: _results[i], width: box.maxWidth, height: box.maxHeight),
                            ),
                    ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.dropdown = false,
    this.icon,
  });
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool dropdown;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? Colors.white : const Color(0xFF26262E),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: selected ? kInk : Colors.white70),
                  const SizedBox(width: 4),
                ],
                Text(label,
                    style: TextStyle(
                        color: selected ? kInk : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                if (dropdown)
                  Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: selected ? kInk : Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A bottom sheet of options as chips; returns the one picked.
Future<String?> _optionsSheet(
    String title, List<String> options, String current, String Function(String) label) {
  return Get.bottomSheet<String>(
    SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in options)
                      _FilterChip(label: label(o), selected: o == current, onTap: () => Get.back(result: o)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    backgroundColor: const Color(0xFF1F1F27),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
  );
}

/// Netflix's idle search screen: what's popular, as wide rows.
class _TopSearches extends StatelessWidget {
  const _TopSearches();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<HomeScreenController>();
    return Obx(() {
      final list = dedupeTitles(c.subjectsList).take(20).toList();
      if (list.isEmpty) {
        return Center(
          child: c.isLoading.value
              ? const CircularProgressIndicator()
              : const Text('Search for a title, or pick a filter.', style: TextStyle(color: Colors.white54)),
        );
      }
      return ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: list.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('Top Searches',
                  style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
            );
          }
          final s = list[i - 1];
          // The poster: a trailer's first frame is often just a studio card.
          final still = s.cover?.url ?? s.trailer?.cover?.url;
          return InkWell(
            onTap: () => showPreviewSheet(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 140,
                    height: 76,
                    child: still == null
                        ? const ColoredBox(color: kCard)
                        : CachedNetworkImage(
                            imageUrl: posterUrl(still, width: 320),
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const ColoredBox(color: kCard),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(s.title ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: 'Play',
                    onPressed: () => openDetail(s, resume: true),
                    icon: const Icon(Icons.play_circle_outline_rounded, color: Colors.white, size: 34),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          );
        },
      );
    });
  }
}
