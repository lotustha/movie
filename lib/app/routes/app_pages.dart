import 'package:get/get.dart';

import '../modules/Subject_Detail/bindings/subject_detail_binding.dart';
import '../modules/Subject_Detail/views/subject_detail_view.dart';
import '../modules/home_screen/bindings/home_screen_binding.dart';
import '../modules/home_screen/views/home_screen_view.dart';
import '../modules/search/bindings/search_binding.dart';
import '../modules/search/views/search_view.dart';
import '../modules/season_view/bindings/season_view_binding.dart';
import '../modules/season_view/views/season_view_view.dart';
import '../modules/video_player/bindings/video_player_binding.dart';
import '../modules/video_player/views/video_player_view.dart';

part 'app_routes.dart';

class AppPages {
  AppPages._();

  static const INITIAL = Routes.HOME_SCREEN;

  static final routes = [

    GetPage(
      name: _Paths.SUBJECT_DETAIL,
      page: () => const SubjectDetailView(),
      binding: SubjectDetailBinding(),
    ),
    GetPage(
      name: _Paths.VIDEO_PLAYER,
      page: () => const VideoPlayerView(),
      binding: VideoPlayerBinding(),
    ),
    GetPage(
      name: _Paths.SEASON_VIEW,
      page: () => const SeasonView(),
      binding: SeasonViewBinding(),
    ),
    GetPage(
      name: _Paths.HOME_SCREEN,
      page: () => const HomeScreenView(),
      binding: HomeScreenBinding(),
    ),
    GetPage(
      name: _Paths.SEARCH,
      page: () => const SearchView(),
      binding: SearchBinding(),
    ),
  ];
}
