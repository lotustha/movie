import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:get/get.dart';
import 'package:movie/app/model/subject_list.dart';


class ApiProvider extends GetConnect {
  final Dio _dio = Dio();
  @override
  void onInit() {
    _dio.options.baseUrl = 'https://moviebox.ph/wefeed-h5-bff/web/';

  }
  Future fetchPlaybackInfoWithCookieManager(
      {required Subject subject,required  String season,required  String episode}) async {
    // 1. Setup Dio and the automatic Cookie Manager
    final dio = Dio();
    final cookieJar = CookieJar();
    dio.interceptors.add(CookieManager(cookieJar));
    const String playUrl = 'https://fmoviesunblocked.net/wefeed-h5-bff/web/subject/play';
    final String refererUrl = 'https://fmoviesunblocked.net/spa/videoPlayPage/movies/${subject.detailPath}?id=${subject.subjectId}&type=/movie/detail&lang=en';
    print(refererUrl);
    final queryParams = {
      'subjectId': subject.subjectId,
      'se': season,
      'ep': episode,
    };
    print(queryParams);
    final Map<String, dynamic> headers = {
      'accept': 'application/json',
      'referer': refererUrl, // The referer is still important
      'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
      'x-client-info': jsonEncode({"timezone": "Asia/Katmandu"}),
    };

    try {
      // 3. [Optional but Recommended] Make a "warm-up" request to the referer page.
      // This populates our cookie jar with the latest valid session cookies.
      print('🚀 Making warm-up request to get fresh cookies...');
      await dio.get(refererUrl, options: Options(headers: headers));
      print('🍪 Cookies received and stored!');

      // 4. Now, make the main request for the playback info.
      // The CookieManager will AUTOMATICALLY add the correct 'Cookie' header.
      print('▶️ Requesting playback info...');
      final response = await dio.get(
        playUrl,
        queryParameters: queryParams,
        options: Options(headers: headers), // Headers WITHOUT the cookie
      );

      if (response.statusCode == 200) {
        print('✅ Success! Playback data received:');
        return response.data;
      } else {
        print('⚠️ Request failed with status code: ${response.statusCode}');
      }
    return null;
    } on DioException catch (e) {
      print('❌ An error occurred: $e');
      if (e.response != null) {
        print('Error Response Data: ${e.response?.data}');
      }
    }
  }
  Future fetchHomePage() async{
    try{
      final response = await _dio.get('home');
      if(response.statusCode==200 && response.data!=null&& response.data['code']==0){
        var data=response.data['data'];
        return data['operatingList'];
      }

    }catch(error){
      print(error);
    }
  }

  Future fetchSubject(String id) async{
    try{
      String url='subject/detail?subjectId=$id';
      print(url);
      final response = await _dio.get(url);
      if(response.statusCode==200 && response.data!=null&& response.data['code']==0){
        var data=response.data['data'];

        return data;
      }

    }catch(error){
      print(error);
    }
  }
  Future getRankingList({required String id,required int page, int perPage=12}) async {
    try {
      final response = await _dio.get('ranking-list/content?id=$id&page=$page&perPage=$perPage');
      return response.data;

    } catch (error) {
      print("Error fetching trending movies: $error");
      return [];
    }
  }

  Future fetchSubtitlesForStream({required String streamId, required String subjectId}) async {
    try {
      final response = await _dio.get('subject/caption?format=MP4&id=$streamId&subjectId=$subjectId');
     return response.data;

    } catch (error) {
      print("Error fetching trending movies: $error");
      return [];
    }
  }

  Future searchMovies(
      String keyword, {
        int page = 1,
        int perPage = 24,
        int subjectType = 0,
      }) async {
    final safeKeyword = Uri.encodeComponent(keyword);
    try {
      final response = await _dio.post(
        'https://moviebox.ph/wefeed-h5-bff/web/subject/search',
        data: {
          "keyword": safeKeyword,
          "page": page,
          "perPage": perPage,
          "subjectType": subjectType,
        },
        options: Options(
          headers: {
            "accept": "application/json",
            "content-type": "application/json",
            "origin": "https://moviebox.ph",
            "referer": "https://moviebox.ph/web/searchResult?keyword=$keyword",
            "user-agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
            "x-client-info": '{"timezone":"Asia/Katmandu"}',
          },
        ),
      );

      if (response.data != null && response.data['data'] != null) {
        return response.data['data']['items'] ?? [];
      }
      return [];
    } catch (error) {
      print("❌ Error searching movies: $error");
      return [];
    }
  }
  Future searchSuggestion(
      String keyword, {
        int perPage = 12,
      }) async {
    try {
      final response = await _dio.post(
        'https://moviebox.ph/wefeed-h5-bff/web/subject/search-suggest',
        data: {
          "keyword": keyword,
          "perPage": perPage,
        },
        options: Options(
          headers: {
            "accept": "application/json",
            "content-type": "application/json",
            "origin": "https://moviebox.ph",
            "referer": "https://moviebox.ph/web/searchResult?keyword=$keyword",
            "user-agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
            "x-client-info": '{"timezone":"Asia/Katmandu"}',
          },
        ),
      );

      if (response.data != null && response.data['data'] != null) {
        return response.data['data']['items'] ?? [];
      }
      return [];
    } catch (error) {
      print("❌ Error searching movies: $error");
      return [];
    }
  }
}
