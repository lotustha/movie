import 'dart:async'; // Required for Timer
import 'dart:convert'; // Required for jsonEncode
import 'package:flutter/services.dart'; // Required for MethodChannel
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/intl.dart';
import 'package:movie/app/data/api_provider.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

import '../../../data/trending_list.dart';
import '../../../model/subject_list.dart';
import '../../../model/TrendingModel.dart';

class HomeScreenController extends GetxController {
  final ApiProvider apiProvider = Get.find<ApiProvider>();
  final isSideNavVisible = false.obs;
  final RxList<Subject> subjectsList = <Subject>[].obs;

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
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateTime();
    });

    TrendingModel trendingModel = TrendingList.trendingList.first;
    // --- NEW: Store the ID of the main "Trending" list ---
    _trendingCategoryId = trendingModel.id ?? '';
    updateSelectedSubject(trendingModel.id ?? '', trendingModel.name ?? '');
  }

  // --- NEW: Method to send the trending list to the native side ---
  Future<void> _updateTvHomeScreenChannel(List<Subject> subjects) async {
    try {
      // Convert the list of Subject objects to a JSON string.
      final List<Map<String, dynamic>> jsonList =
      subjects.map((subject) => subject.toJson()).toList();
      final String moviesJson = jsonEncode(jsonList);

      // Invoke the method on the native side, passing the JSON data.
      await _tvChannel.invokeMethod('updateTrendingMovies', {
        'moviesJson': moviesJson,
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
