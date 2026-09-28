import 'package:movie/app/model/TrendingModel.dart';

/// The ranking-list categories shown as chips on the home screen.
///
/// Names and ids are taken verbatim from moviebox.pk's own ranking-list
/// payload (the bracketed studio labels like "[MARVEL]" are theirs) and each
/// id is a live `ranking-list/content` list. Order matches the home chip bar.
class TrendingList {
  static const List<Map<String, String>> _trendingListMap = [
    {"name": "Popular", "id": "997144265920760504"},
    {"name": "Nollywood", "id": "8216283712045280"},
    {"name": "Action", "id": "6050680843129996568"},
    {"name": "Horror", "id": "8614980535946986176"},
    {"name": "Romance", "id": "9139789616411735224"},
    {"name": "Comedy", "id": "8599868521717400352"},
    {"name": "Adventure", "id": "7486582804437256712"},
    {"name": "Fantasy", "id": "6081207125081048720"},
    {"name": "Animation", "id": "7132534597631837112"},
    {"name": "BoxOffice TOP200", "id": "8049887023940913872"},
    {"name": "Bollywood", "id": "414907768299210008"},
    {"name": "South Hindi", "id": "3859721901924910512"},
    {"name": "Yoruba", "id": "5618472934214884040"},
    {"name": "[MARVEL]", "id": "5938715630600946768"},
    {"name": "[DC]", "id": "8981852519202701864"},
    {"name": "[Pixar]", "id": "8300357620121175440"},
    {"name": "[Disney]", "id": "4893929859782771488"},
    {"name": "[Illumination]", "id": "4704823205654053416"},
    {"name": "[DreamWorks]", "id": "6498477964521783328"},
    {"name": "IMDB TOP250", "id": "6831003342882626360"},
  ];
  static List<TrendingModel> trendingList =
      _trendingListMap.map((e) => TrendingModel.fromJson(e)).toList();
}
