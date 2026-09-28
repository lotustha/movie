import '../../../services/prefs.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:movie/app/data/api_provider.dart';
import 'package:movie/app/data/trending_list.dart';
import 'package:movie/app/model/SearchSuggestWordModel.dart';
import 'package:movie/app/model/subject_list.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

class SearchViewController extends GetxController {
  // 18+-tagged titles only appear once 18+ is on (Settings).
  static bool _allowed(Subject s) => !AppPrefs.to.hideSubject(s);

  final ApiProvider apiProvider = Get.find<ApiProvider>();
  final _storage = GetStorage();

  // --- UI Controllers ---
  final TextEditingController searchController = TextEditingController();
  final RefreshController refreshController = RefreshController();

  // Focus Nodes
  final FocusNode searchFocusNode = FocusNode(); // Mobile & Web
  final FocusNode searchInputDisplayFocusNode = FocusNode(); // TV

  // --- Observables ---
  final isTv = false.obs;
  final isKeyboardFocused = false.obs; // For TV On-screen keyboard
  final isLoading = false.obs;
  final isMoreLoading = false.obs;

  // Data
  RxList<SearchSuggestWordModel> searchSuggestions = <SearchSuggestWordModel>[].obs;
  RxList<Subject> subjectsList = <Subject>[].obs;
  RxList<String> searchHistory = <String>[].obs;
  final RxString searchQuery = ''.obs;

  // Result filter: 0 = all, 1 = movies, 2 = TV shows (the API's subjectType).
  final RxInt searchType = 0.obs;

  // "Popular right now" — shown on TV before anything is typed.
  RxList<Subject> popularList = <Subject>[].obs;
  final isPopularLoading = false.obs;

  // --- Internals ---
  Timer? _debounce;
  String _currentQuery = '';
  int _currentPage = 1;
  int _searchRequest = 0;
  static const int _debounceTimeMs = 800; // Debounce delay
  bool _hasMoreData = true;

  @override
  void onInit() {
    super.onInit();
    _loadSearchHistory();
    _loadLastSearchResult();
    searchController.addListener(() {
      searchQuery.value = searchController.text;
    });
    _loadPopular();
  }

  Future<void> _loadPopular() async {
    final id = TrendingList.trendingList.first.id;
    if (id == null) return;
    isPopularLoading.value = true;
    try {
      final response = await apiProvider.getRankingList(id: id, page: 1, perPage: 24);
      final list = rankingSubjects(response);
      if (list is List) {
        popularList.assignAll(list.map((e) => Subject.fromJson(e)).where(_allowed));
      }
    } catch (_) {
    } finally {
      isPopularLoading.value = false;
    }
  }

  /// Switches the Movies / TV Shows filter and re-runs the current search.
  void setSearchType(int type) {
    if (searchType.value == type) return;
    searchType.value = type;
    final query = searchController.text.trim();
    if (query.isNotEmpty) {
      _debounce?.cancel();
      search(query);
    }
  }

  /// TV: pick a suggestion or recent search. Unlike [onSuggestionSelected] the
  /// list stays put, so the D-pad focus that picked it isn't left on a
  /// removed row.
  void onTvSuggestionSelected(String word) {
    _debounce?.cancel();
    searchController.text = word;
    search(word);
  }

  @override
  void onClose() {
    searchController.dispose();
    refreshController.dispose();
    searchFocusNode.dispose();
    searchInputDisplayFocusNode.dispose();
    _debounce?.cancel();
    super.onClose();
  }

  // --- CORE LOGIC: Type vs Click ---

  /// 1. User Types: Load suggestions instantly, Debounce the Search
  void onSearchInputChanged(String query) {
    if (query.isEmpty) {
      searchSuggestions.clear();
      subjectsList.clear();
      return;
    }

    // Always fetch suggestions immediately
    _fetchSuggestions(query);

    // Debounce the actual "Result" search
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: _debounceTimeMs), () {
      if (query.trim().isNotEmpty) {
        search(query.trim());
      }
    });
  }

  /// 2. User Clicks Suggestion: Cancel debounce, replace text, search immediately
  void onSuggestionSelected(String word) {
    // Cancel the "Typing" timer
    _debounce?.cancel();

    // Update Text
    searchController.text = word;
    searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: searchController.text.length),
    );

    // Clear suggestions to show results view
    searchSuggestions.clear();

    // Dismiss keyboard on mobile/tablet (keep focus on Web if needed, but usually dismiss)
    if (!isTv.value) searchFocusNode.unfocus();

    // Immediate Search
    search(word);
  }

  /// 3. User Presses Enter
  void submitSearch() {
    searchSuggestions.clear();
    if (!isTv.value) searchFocusNode.unfocus();
    final query = searchController.text.trim();
    if (query.isNotEmpty) {
      _debounce?.cancel();
      search(query);
    }
  }

  // --- API ---

  Future<void> _fetchSuggestions(String query) async {
    try {
      var response = await apiProvider.searchSuggestion(query);
      // One request fires per keystroke; drop answers for text that has
      // since changed so a slow "ba" can't overwrite "batman".
      if (query != searchController.text) return;
      if (response != null) {
        final list = (response as List)
            .map((e) => SearchSuggestWordModel.fromJson(e))
            .toList();
        searchSuggestions.assignAll(list);
      }
    } catch (_) {}
  }

  Future<void> search(String query) async {
    final int request = ++_searchRequest;
    _currentQuery = query;
    _currentPage = 1;
    _hasMoreData = true;
    isLoading.value = true;
    subjectsList.clear();

    try {
      final data = await apiProvider.searchMovies(query,
          page: _currentPage, subjectType: searchType.value);
      // A newer search (other text or filter) started while this one was in
      // flight; it owns the results and the spinner.
      if (request != _searchRequest) return;
      List<Subject> results = (data as List).map((e) => Subject.fromJson(e)).where(_allowed).toList();
      subjectsList.assignAll(results);

      if (results.isNotEmpty) {
        _addToHistory(query);
        _saveLastSearchResult(query, results);
      }
    } catch (e) {
      if (request == _searchRequest) Get.snackbar('Error', 'Search failed');
    } finally {
      if (request == _searchRequest) isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isMoreLoading.value || !_hasMoreData || _currentQuery.isEmpty) return;
    isMoreLoading.value = true;
    final nextPage = _currentPage + 1;
    try {
      final data = await apiProvider.searchMovies(_currentQuery,
          page: nextPage, subjectType: searchType.value);
      final List<Subject> more =
          (data as List).map((e) => Subject.fromJson(e)).where(_allowed).toList();

      // MovieBox's tokenless search is server-rendered and ignores the page
      // param — every page returns the same set. Append only subjects we
      // haven't shown yet; when a page brings nothing new, there is no more
      // data, so stop instead of looping on duplicates forever.
      final existingIds = subjectsList.map((s) => s.subjectId).toSet();
      final fresh = more.where((s) => existingIds.add(s.subjectId)).toList();

      if (fresh.isEmpty) {
        _hasMoreData = false;
        refreshController.loadNoData();
      } else {
        _currentPage = nextPage;
        subjectsList.addAll(fresh);
        refreshController.loadComplete();
      }
    } catch (e) {
      refreshController.loadFailed();
    } finally {
      isMoreLoading.value = false;
    }
  }

  // --- History & TV Helpers ---
  void _loadSearchHistory() {
    List? stored = _storage.read<List>('searchHistory');
    if (stored != null) searchHistory.assignAll(stored.cast<String>());
  }

  void _addToHistory(String query) {
    searchHistory.remove(query);
    searchHistory.insert(0, query);
    if (searchHistory.length > 10) searchHistory.removeLast();
    _storage.write('searchHistory', searchHistory.toList());
  }

  void clearSearchHistory() {
    searchHistory.clear();
    _storage.remove('searchHistory');
  }

  void _saveLastSearchResult(String query, List<Subject> results) {
    _storage.write('lastSearchQuery', query);
    _storage.write('lastSearchResults', results.map((s) => s.toJson()).toList());
  }

  void _loadLastSearchResult() {
    final q = _storage.read<String>('lastSearchQuery');
    final r = _storage.read<List>('lastSearchResults');
    if (q != null && r != null) {
      _currentQuery = q;
      subjectsList.assignAll(r.map((d) => Subject.fromJson(d)).where(_allowed).toList());
    }
  }

  void onTvKeyTapped(String key) {
    final text = searchController.text;
    if (key == 'DEL') {
      if (text.isNotEmpty) searchController.text = text.substring(0, text.length - 1);
    } else if (key == 'CLR') {
      searchController.clear();
    } else if (key == ' ') {
      searchController.text = '$text ';
    } else {
      searchController.text = text + key;
    }
    onSearchInputChanged(searchController.text);
  }
}