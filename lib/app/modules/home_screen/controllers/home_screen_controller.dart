import 'dart:async'; // Required for Timer
import 'dart:convert'; // Required for jsonEncode
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart'; // Required for MethodChannel
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/intl.dart';
import 'package:movie/app/data/api_provider.dart';
import 'package:movie/app/data/user_data.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

import '../../../data/trending_list.dart';
import '../../../services/config.dart';
import '../../../model/subject_list.dart';
import '../../../model/operating_list_model.dart';
import '../../../model/TrendingModel.dart';

class HomeScreenController extends GetxController {
  final ApiProvider apiProvider = Get.find<ApiProvider>();
  final isSideNavVisible = false.obs;
  final RxList<Subject> subjectsList = <Subject>[].obs;
  final scrollController = ScrollController();

  // --- Netflix-style home feed (hero billboard + horizontal rows) ---
  final RxList<OperatingList> homeRows = <OperatingList>[].obs;
  final Rxn<Subject> heroSubject = Rxn<Subject>();
  final isFeedLoading = true.obs;

  // Vertical scroll offset of the home feed, drives the liquid-glass top bar
  // (transparent over the hero → frosted glass as you scroll).
  final feedScrollOffset = 0.0.obs;

  // Personalised rows (persisted locally in UserData).
  final RxList<Subject> continueWatching = <Subject>[].obs;
  final RxList<Subject> myList = <Subject>[].obs;

  void refreshUserRows() {
    continueWatching.assignAll(UserData.continueSubjects());
    myList.assignAll(UserData.myList());
    _updateWatchNext();
  }

  /// Continue Watching → the Android TV launcher's "Play Next" row (the
  /// native side ignores this on phones).
  Future<void> _updateWatchNext() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final items = [
      for (final e in UserData.continueEntries().take(10))
        {
          'subjectId': e['subjectId'],
          'title': (e['subject'] as Map?)?['title'],
          'cover': ((e['subject'] as Map?)?['cover'] as Map?)?['url'],
          'subjectType': (e['subject'] as Map?)?['subjectType'],
          'season': e['season'],
          'episode': e['episode'],
          'positionSec': e['position'],
          'durationSec': e['duration'],
        },
    ];
    try {
      await _tvChannel.invokeMethod('updateWatchNext', {'itemsJson': jsonEncode(items)});
    } on PlatformException catch (e) {
      print("Failed to update Play Next: '${e.message}'.");
    } on MissingPluginException {
      // Not the Android app (e.g. a test host).
    }
  }

  final currentTime = ''.obs;
  final currentDate = ''.obs;
  late Timer _timer;

  final selectedSubjectId = ''.obs;
  final selectedSubjectName = 'Home'.obs;
  final RxInt page = 1.obs;

  final isLoading = true.obs;
  final isMoreLoading = false.obs;
  final RefreshController refreshController = RefreshController(initialRefresh: false);

  final GetStorage _storage = GetStorage();
  Timer? _debounce;

  // --- NEW: MethodChannel and ID for the "Trending" category ---
  static const _tvChannel = MethodChannel('com.lynoon.movie/tv_channel');
  String _trendingCategoryId = '';


  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(() {
      if (scrollController.position.pixels >=
          scrollController.position.maxScrollExtent - 50) {
        loadMore();
      }
    });
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateTime();
    });

    TrendingModel trendingModel = TrendingList.trendingList.first;
    // --- NEW: Store the ID of the main "Trending" list ---
    _trendingCategoryId = trendingModel.id ?? '';
    updateSelectedSubject(trendingModel.id ?? '', trendingModel.name ?? '');
    fetchHomeFeed();
    refreshUserRows();
  }

  static const _kFeedCache = 'home_feed_cache';

  /// Loads the MovieBox home feed (banner + themed rails) for the Netflix-style
  /// home. Shows the cached feed instantly, then refreshes in the background.
  Future<void> fetchHomeFeed() async {
    // 1. Instant paint from cache.
    final cached = _storage.read<List>(_kFeedCache);
    if (cached != null && homeRows.isEmpty) {
      _applyFeed(cached);
      isFeedLoading.value = false;
    }

    // 2. Refresh from the network.
    try {
      if (homeRows.isEmpty) isFeedLoading.value = true;
      final list = await apiProvider.fetchHomePage(); // operatingList
      if (list is List) {
        _storage.write(_kFeedCache, list);
        _applyFeed(list);
      }
    } catch (e) {
      print('fetchHomeFeed error: $e');
    } finally {
      isFeedLoading.value = false;
    }
  }

  void _applyFeed(List<dynamic> list) {
    final rows = list
        .map((e) => OperatingList.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    // Hero = first banner item that carries a full subject.
    final banner = rows.firstWhereOrNull(
      (o) => o.type == 'BANNER' && o.banner != null && o.banner!.items.isNotEmpty,
    );
    final heroItem =
        banner?.banner!.items.firstWhereOrNull((i) => i.subject != null);
    if (heroItem?.subject != null) heroSubject.value = heroItem!.subject;

    // TV billboard: every banner item with wide art and a full subject.
    banners.assignAll(banner?.banner!.items
            .where((i) => i.subject != null && i.image.url.isNotEmpty) ??
        const <BannerItem>[]);

    // Rows = rails that actually carry subjects.
    homeRows.assignAll(rows.where((o) => o.subjects.isNotEmpty).toList());
  }

  // --- 18+ ("Midnight") feed --------------------------------------------------
  // Loaded only once the user has opted in (AppPrefs.adultEnabled).

  final RxList<OperatingList> adultRows = <OperatingList>[].obs;
  final RxList<BannerItem> adultBanners = <BannerItem>[].obs;
  final isAdultLoading = false.obs;
  final adultFailed = false.obs;

  Future<void> fetchAdultFeed({bool force = false}) async {
    if (isAdultLoading.value || (adultRows.isNotEmpty && !force)) return;
    isAdultLoading.value = true;
    adultFailed.value = false;
    try {
      final list = await apiProvider.fetchTab(AppConfig.adultTabId);
      if (list is List) {
        final rows = list
            .map((e) => OperatingList.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        final banner = rows.firstWhereOrNull(
            (o) => o.type == 'BANNER' && o.banner != null && o.banner!.items.isNotEmpty);
        adultBanners.assignAll(banner?.banner!.items
                .where((i) => i.subject != null && i.image.url.isNotEmpty) ??
            const <BannerItem>[]);
        adultRows.assignAll(rows.where((o) => o.subjects.isNotEmpty));
      } else {
        adultFailed.value = true;
      }
    } finally {
      isAdultLoading.value = false;
    }
  }

  // --- TV home ---------------------------------------------------------------

  final RxList<BannerItem> banners = <BannerItem>[].obs;

  // The poster the D-pad is on; drives the TV info header.
  final Rxn<Subject> focusedSubject = Rxn<Subject>();

  // Ranking categories shown as TV rows, loaded once when their row is first
  // built. [rankingRowLoaded] flips true when the fetch finishes (even empty).
  final Map<String, RxList<Subject>> _rankingRows = {};
  final Map<String, RxBool> rankingRowLoaded = {};

  RxList<Subject> rankingRow(String id) {
    return _rankingRows.putIfAbsent(id, () {
      final row = <Subject>[].obs;
      final loaded = rankingRowLoaded[id] = false.obs;
      apiProvider.getRankingList(id: id, page: 1, perPage: 20).then((response) {
        final list = rankingSubjects(response);
        if (list is List) row.assignAll(list.map((e) => Subject.fromJson(e)));
      }).whenComplete(() => loaded.value = true);
      return row;
    });
  }

  // --- NEW: Method to send the trending list to the native side ---
  Future<void> _updateTvHomeScreenChannel(List<Subject> subjects) async {
    // A failed fetch comes back empty: keep the launcher row as it is.
    if (subjects.isEmpty || kIsWeb || !Platform.isAndroid) return;
    try {
      // WorkManager's Data has a hard 10240-byte limit, so send only what the
      // launcher shows, with short descriptions, and drop titles until it fits.
      final jsonList = subjects
          .where((s) => s.subjectId != null)
          .take(20)
          .map((s) => {
                'subjectId': s.subjectId,
                'title': s.title,
                'cover': {'url': s.cover?.url},
                'subjectType': s.subjectType,
                'releaseDate': s.releaseDate,
                'genre': s.genre,
                'description': (s.description ?? '').length > 110
                    ? '${s.description!.substring(0, 107)}...'
                    : s.description,
              })
          .toList();
      var moviesJson = jsonEncode(jsonList);
      while (utf8.encode(moviesJson).length > 9000 && jsonList.length > 1) {
        jsonList.removeLast();
        moviesJson = jsonEncode(jsonList);
      }

      await _tvChannel.invokeMethod('updateTrendingMovies', {
        'moviesJson': moviesJson,
        'apiBase': ApiProvider.apiOrigin,
        'rankingId': _trendingCategoryId,
      });
      print("Successfully requested TV home screen update.");
    } on PlatformException catch (e) {
      // Handle any errors that occur during the method call.
      print("Failed to update TV home screen: '${e.message}'.");
    }
  }

  void _cacheData(String subjectId, List<Subject> subjects) {
    final List<Map<String, dynamic>> jsonList =
    subjects.map((subject) => subject.toJson()).toList();
    _storage.write(subjectId, jsonList);
  }

  void _loadCachedData(String subjectId) {
    final cachedData = _storage.read<List>(subjectId);
    if (cachedData != null) {
      final newSubjects = cachedData
          .map((item) => Subject.fromJson(item as Map<String, dynamic>))
          .toList();
      subjectsList.assignAll(newSubjects);
    }
  }

  Future<void> getRankingList({bool isRefresh = false}) async {
    final String subjectIdForThisRequest = selectedSubjectId.value;

    if (isRefresh) {
      page.value = 1;
    }

    try {
      if (isRefresh) isLoading.value = true;
      isMoreLoading.value = !isRefresh;

      var response = await apiProvider.getRankingList(
        id: selectedSubjectId.value,
        page: page.value,
        perPage: 36,
      );

      if (subjectIdForThisRequest != selectedSubjectId.value) {
        return;
      }

      var data = response['data'];
      var mySubjectList = data['subjectList'] as List;
      var newSubjects =
      mySubjectList.map((e) => Subject.fromJson(e)).toList();

      // --- NEW: Check if this is the "Trending" list and send it to the home screen ---
      if (isRefresh && subjectIdForThisRequest == _trendingCategoryId) {
        _updateTvHomeScreenChannel(newSubjects);
      }
      // --- End of new logic ---

      if (isRefresh) {
        if (newSubjects.isNotEmpty) {
          _cacheData(selectedSubjectId.value, newSubjects);
        }
        subjectsList.clear();
      }

      subjectsList.addAll(newSubjects);

      if (isRefresh) {
        refreshController.refreshCompleted();
      }
      if (newSubjects.isEmpty) {
        refreshController.loadNoData();
      } else {
        page.value++;
        refreshController.loadComplete();
      }
    } catch (e) {
      if (isRefresh) {
        refreshController.refreshFailed();
      } else {
        refreshController.loadFailed();
      }
      Get.snackbar('Error', 'Failed to fetch data: ${e.toString()}');
    } finally {
      if (subjectIdForThisRequest == selectedSubjectId.value) {
        isLoading.value = false;
        isMoreLoading.value = false;
      }
    }
  }

  Future<void> refresh() async {
    await getRankingList(isRefresh: true);
  }

  Future<void> loadMore() async {
    await getRankingList();
  }

  @override
  void onClose() {
    _timer.cancel();
    _debounce?.cancel();
    refreshController.dispose();

    super.onClose();
  }

  void _updateTime() {
    final now = DateTime.now();
    currentTime.value = DateFormat('h:mm a').format(now);
    currentDate.value = DateFormat('MMM dd').format(now);
  }

  void updateSelectedSubject(String id, String name) {
    if (selectedSubjectId.value == id) return;

    _debounce?.cancel();

    selectedSubjectId.value = id;
    selectedSubjectName.value = name;
    subjectsList.clear();
    isLoading.value = true;
    refreshController.resetNoData();

    if (Get.width < 768) {
      closeSideNav();
    }

    _debounce = Timer(const Duration(milliseconds: 500), () {
      getRankingList(isRefresh: true);
    });
  }

  void openSideNav() {
    isSideNavVisible.value = true;
  }

  void closeSideNav() {
    isSideNavVisible.value = false;
  }

  void toggleSideNav() {
    isSideNavVisible.toggle();
  }
}
