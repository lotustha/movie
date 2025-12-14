import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:movie/app/data/api_provider.dart';
import 'package:movie/app/model/SearchSuggestWordModel.dart';
import 'package:movie/app/model/subject_list.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

class SearchViewController extends GetxController {
  final ApiProvider apiProvider = Get.find<ApiProvider>();
  final _storage = GetStorage();
  RxList<SearchSuggestWordModel> searchSuggestions =
      <SearchSuggestWordModel>[].obs;
  // --- UI Controllers ---
  final TextEditingController searchController = TextEditingController();
  final RefreshController refreshController = RefreshController();
  final FocusNode searchFocusNode = FocusNode(); // For non-TV text field
  final FocusNode searchInputDisplayFocusNode =
  FocusNode(); // For TV search input

  // --- Reactive State ---
  final isKeyboardFocused = false.obs;
  final RxList<Subject> subjectsList = <Subject>[].obs;
  final isLoading = false.obs;
  final isMoreLoading = false.obs;
  final RxString searchQuery = ''.obs;
  final isTv = true.obs;
  final RxList<String> searchHistory = <String>[].obs;

  // --- Internal State ---
  Timer? _debounce;
  String _currentQuery = '';
  int _currentPage = 1;
  static const int _debounceTimeMs = 500;
  bool _hasMoreData = true;

  @override
  void onInit() {
    super.onInit();
    _loadSearchHistory();
    _loadLastSearchResult();

    // Listener for text changes.
    searchController.addListener(() {
      searchQuery.value = searchController.text;
      onSearchChanged(searchController.text);
    });

    // Listener for focus changes on the non-TV text field to trigger search.
    searchFocusNode.addListener(() {
      if (!searchFocusNode.hasFocus) {
        submitSearch();
      }
    });
  }

  @override
  void onClose() {
    searchController.dispose();
    refreshController.dispose();
    searchFocusNode.dispose();
    searchInputDisplayFocusNode.dispose(); // Ensure disposal
    _debounce?.cancel();
    super.onClose();
  }

  // --- Search History & Cache Logic ---
  void loadSearchSuggestions() async {
    var response = await apiProvider.searchSuggestion(searchController.text);
    if (response == null) return;
    final List<SearchSuggestWordModel> myList = (response as List)
        .map((e) => SearchSuggestWordModel.fromJson(e as Map<String, dynamic>))
        .toList();
    searchSuggestions.assignAll(myList);
  }

  void _loadSearchHistory() {
    List<dynamic>? storedHistory = _storage.read<List>('searchHistory');
    if (storedHistory != null) {
      searchHistory.assignAll(storedHistory.cast<String>());
    }
  }

  void _loadLastSearchResult() {
    final lastQuery = _storage.read<String>('lastSearchQuery');
    final lastResultsData = _storage.read<List>('lastSearchResults');

    if (lastQuery != null && lastResultsData != null) {
      try {
        final lastResults = lastResultsData
            .map((data) => Subject.fromJson(data as Map<String, dynamic>))
            .toList();
        subjectsList.assignAll(lastResults);
        _currentQuery = lastQuery;
      } catch (e) {
        // Clear corrupted data
        _storage.remove('lastSearchQuery');
        _storage.remove('lastSearchResults');
      }
    }
  }

  void _saveSearchQuery(String query) {
    searchHistory.remove(query);
    searchHistory.insert(0, query);
    if (searchHistory.length > 10) {
      searchHistory.removeLast();
    }
    _storage.write('searchHistory', searchHistory.toList());
  }

  void searchFromHistory(String query) {
    searchController.text = query;
    if (!isTv.value) {
      submitSearch();
    }
  }

  void clearSearchHistory() {
    searchHistory.clear();
    _storage.remove('searchHistory');
  }

  void onKeyTapped(String key) {
    final currentText = searchController.text;
    switch (key) {
      case 'DEL':
        if (currentText.isNotEmpty) {
          searchController.text = currentText.substring(
            0,
            currentText.length - 1,
          );
        }
        break;
      case 'CLR':
        searchController.clear();
        break;
      case ' ':
        searchController.text = '$currentText ';
        break;
      default:
        searchController.text = currentText + key;
    }
  }

  void onSearchChanged(String query) {
    if (!isTv.value) return;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: _debounceTimeMs), () {
      if (query.trim().isEmpty) {
        subjectsList.clear();
        _currentQuery = '';
        _hasMoreData = true;
      } else if (query.trim() != _currentQuery) {
        search(query.trim());
      }
    });
  }

  void submitSearch() {
    final query = searchController.text.trim();
    if (query == _currentQuery) return;

    if (query.isEmpty) {
      subjectsList.clear();
      _currentQuery = '';
      _hasMoreData = true;
      return;
    }
    _debounce?.cancel();
    search(query);
  }

  Future<void> search(String query) async {
    _currentQuery = query;
    _currentPage = 1;
    _hasMoreData = true;
    isLoading.value = true;
    subjectsList.clear();

    try {
      final data = await apiProvider.searchMovies(query, page: _currentPage);
      List<Subject> tempSubjects = (data as List)
          .map((e) => Subject.fromJson(e as Map<String, dynamic>))
          .toList();

      subjectsList.assignAll(tempSubjects);

      if (tempSubjects.isEmpty) {
        _hasMoreData = false;
      } else {
        _saveSearchQuery(query);
        _storage.write('lastSearchQuery', query);
        _storage.write(
          'lastSearchResults',
          tempSubjects.map((s) => s.toJson()).toList(),
        );
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to perform search: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isMoreLoading.value || !_hasMoreData || _currentQuery.isEmpty) {
      if (!_hasMoreData) refreshController.loadNoData();
      return;
    }

    isMoreLoading.value = true;
    _currentPage++;

    try {
      final data =
      await apiProvider.searchMovies(_currentQuery, page: _currentPage);

      if (data.isEmpty) {
        _hasMoreData = false;
        refreshController.loadNoData();
      } else {
        List<Subject> tempSubjects = (data as List)
            .map((e) => Subject.fromJson(e as Map<String, dynamic>))
            .toList();
        subjectsList.addAll(tempSubjects);
        refreshController.loadComplete();
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to load more results: $e');
      _currentPage--;
      refreshController.loadFailed();
    } finally {
      isMoreLoading.value = false;
    }
  }

  void onResultTap(Subject subject) {
    // Example navigation, replace with your actual navigation logic
    //Get.to(() => SubjectDetailView(), arguments: subject);
    Get.snackbar('Navigate', 'Tapped on ${subject.title}');
  }

  void selectSuggestion(String s) {
    searchController.text = s;
    submitSearch();
  }
}
