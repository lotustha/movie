import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:movie/app/model/subject_list.dart';

/// The `subjectList` of a [ApiProvider.getRankingList] response, or null.
List<dynamic>? rankingSubjects(dynamic response) {
  if (response is! Map) return null;
  final data = response['data'];
  if (data is! Map) return null;
  final list = data['subjectList'];
  return list is List ? list : null;
}

/// Every call goes to the Mugen API (D:\nextjs\animeapi, `movie-tv/moviebox`),
/// which owns the MovieBox session token and the CDN Referer the video host
/// insists on. When MovieBox changes, the fix lands there, not in the app.
///
/// Home, ranking, detail and suggest come back in MovieBox's own shape, so
/// the models parse them as before. Build with
/// `--dart-define=MUGEN_API=http://<host>:<port>` to point at another server.
class ApiProvider extends GetConnect {
  /// API origin, shared with the native TV-channel refresh.
  static String get apiOrigin => _mugenApi;

  static const String _mugenApi = String.fromEnvironment(
    'MUGEN_API',
    defaultValue: 'https://api.mugenstream.fun',
  );

  final Dio _dio = Dio(BaseOptions(
    baseUrl: '$_mugenApi/movie-tv/moviebox/',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    // 4xx answers carry a JSON message; let callers read them instead of throwing.
    validateStatus: (s) => s != null && s < 500,
  ));

  // Subtitles come back with the streams from /watch; kept here so the player's
  // separate subtitle fetch can be answered without a second round trip.
  final Map<String, List<Map<String, dynamic>>> _captionsByStream = {};

  /// Streams for a movie (season/episode 0) or one TV episode.
  /// Returns the legacy MovieBox shape `{data: {streams: [...]}}` the screens parse.
  Future fetchPlaybackInfoWithCookieManager(
      {required Subject subject,required  String season,required  String episode}) async {
    if (subject.detailPath == null) return null;
    try {
      final response = await _dio.get(
        'watch/${Uri.encodeComponent(subject.detailPath!)}',
        queryParameters: {'season': season, 'episode': episode},
      );
      final data = response.data;
      if (response.statusCode != 200 || data is! Map || data['sources'] is! List) {
        print('watch ${subject.detailPath} S${season}E$episode: HTTP ${response.statusCode}');
        return {'data': {'streams': []}};
      }

      final headers = (data['headers'] as Map?)?.map((k, v) => MapEntry('$k', '$v'));
      final captions = (data['subtitles'] as List? ?? [])
          .map((c) => {
                'id': c['langCode'],
                'lan': c['langCode'],
                'lanName': c['label'],
                'url': c['url'],
              })
          .toList();

      final streams = <Map<String, dynamic>>[];
      for (final source in data['sources'] as List) {
        final proxied = source['url'] as String;
        // Play straight from the CDN with the upstream's headers; the proxied
        // URL is the fallback if the direct request is refused.
        final direct = Uri.tryParse(proxied)?.queryParameters['url'];
        final id = '${subject.subjectId}-$season-$episode-${source['quality']}';
        _captionsByStream[id] = captions;
        streams.add({
          'id': id,
          'format': 'MP4',
          'url': direct ?? proxied,
          'fallbackUrl': direct == null ? null : proxied,
          'headers': headers,
          'resolutions': '${source['quality']}',
          'size': source['sizeBytes']?.toString(),
          'codecName': source['codec'],
        });
      }
      return {'data': {'streams': streams}};
    } on DioException catch (e) {
      print('❌ watch error: $e');
      return null;
    }
  }

  /// Home rows (`operatingList`).
  Future fetchHomePage() async {
    try {
      final response = await _dio.get('home');
      if (response.statusCode == 200 && response.data is Map) {
        return response.data['operatingList'];
      }
    } catch (error) {
      print(error);
    }
  }

  /// A site tab's rows (`operatingList`), e.g. the 18+ tab (9).
  Future fetchTab(int tabId) async {
    try {
      final response = await _dio.get('tab/$tabId');
      if (response.statusCode == 200 && response.data is Map) {
        return response.data['operatingList'];
      }
    } catch (error) {
      print('fetchTab($tabId) error: $error');
    }
    return null;
  }

  /// A title's detail (`subject`, `resource`, `stars`, …), or null when the
  /// catalog doesn't have it.
  Future fetchSubject(String id) async {
    try {
      final response = await _dio.get('detail/${Uri.encodeComponent(id)}');
      if (response.statusCode == 200 && response.data is Map) {
        return response.data;
      }
    } catch (error) {
      print('fetchSubject($id) error: $error');
    }
    return null;
  }

  /// One ranking list, in the legacy `{code, data: {subjectList, …}}` shape.
  Future getRankingList({required String id,required int page, int perPage=12}) async {
    try {
      final response = await _dio.get(
        'ranking/${Uri.encodeComponent(id)}',
        queryParameters: {'page': page, 'perPage': perPage},
      );
      if (response.statusCode == 200 && response.data is Map) {
        return {'code': 0, 'data': response.data};
      }
      return {'code': response.statusCode, 'data': {'subjectList': []}};
    } catch (error) {
      print("Error fetching ranking list: $error");
      return {'code': -1, 'data': {'subjectList': []}};
    }
  }

  /// Subtitles for a stream returned by [fetchPlaybackInfoWithCookieManager],
  /// in the legacy `{code, data: {captions}}` shape.
  Future fetchSubtitlesForStream({required String streamId, required String subjectId}) async {
    return {
      'code': 0,
      'data': {'captions': _captionsByStream[streamId] ?? []},
    };
  }

  /// Search, mapped to the MovieBox subject shape ([Subject.fromJson]) the
  /// search and detail screens expect.
  Future searchMovies(
      String keyword, {
        int page = 1,
        int perPage = 24,
        int subjectType = 0,
      }) async {
    try {
      final type = subjectType == 1 ? 'movie' : subjectType == 2 ? 'tv' : 'all';
      final response = await _dio.get(
        'search/${Uri.encodeComponent(keyword)}',
        queryParameters: {'page': page, 'type': type},
      );
      final results = response.data is Map ? response.data['results'] as List? : null;
      return (results ?? [])
          .map<Map<String, dynamic>>((r) => {
                'subjectId': r['subjectId'],
                'subjectType': r['type'] == 'tv' ? 2 : 1,
                'title': r['title'],
                'detailPath': r['id'],
                'cover': r['poster'] == null ? null : {'url': r['poster']},
                'releaseDate': r['releaseDate'],
                'genre': (r['genres'] as List? ?? []).join(','),
                'countryName': r['country'],
                'imdbRatingValue': r['rating'],
              })
          .toList();
    } catch (error) {
      print("❌ Error searching movies: $error");
      return [];
    }
  }

  /// Search-as-you-type words (`items`).
  Future searchSuggestion(
      String keyword, {
        int perPage = 12,
      }) async {
    try {
      final response = await _dio.get(
        'suggest/${Uri.encodeComponent(keyword)}',
        queryParameters: {'perPage': perPage},
      );
      if (response.statusCode == 200 && response.data is Map) {
        return response.data['items'] ?? [];
      }
      return [];
    } catch (error) {
      print("❌ Error fetching suggestions: $error");
      return [];
    }
  }
}
