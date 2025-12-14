import 'package:movie/app/model/TrendingModel.dart';
class TrendingList {
  static const List<Map<String, String>> _trendingListMap = [
    {"name": "Trending", "id": "8610422883619422240"},
    {"name": "Toplist", "id": "1232643093049001320"},
    {"name":"In Cinema","id":"5692654647815587592"},
    {"name": "Movie", "id": "997144265920760504"},
    {"name": "Western TV", "id": "2540573817806670120"},
    {"name": "Black Drama", "id": "8505361996374835640"},
    {"name": "K-Drama", "id": "545163257435277640"},
    {"name": "C-Drama", "id": "173752404280836544"},
    {"name": "Anime", "id": "62133389738001440"},
    {"name": "Nollywood", "id": "2972333677344080512"},
    {"name": "Bollywood", "id": "414907768299210008"},
    {"name": "South Hindi", "id": "3859721901924910512"},
    {"name": "Animated Film", "id": "7132534597631837112"},
  ];
 static List<TrendingModel> trendingList=_trendingListMap.map((e)=>TrendingModel.fromJson(e)).toList();
}
