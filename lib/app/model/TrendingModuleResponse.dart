// trending_response.dart

import 'dart:convert';

import 'package:movie/app/model/subject_list.dart';

TrendingModuleResponse trendingModuleResponseFromJson(String str) => TrendingModuleResponse.fromJson(json.decode(str));

String trendingModuleResponseToJson(TrendingModuleResponse data) => json.encode(data.toJson());

class TrendingModuleResponse {
  num? code;
  String? message;
  Data? data;

  TrendingModuleResponse({
    this.code,
    this.message,
    this.data,
  });

  factory TrendingModuleResponse.fromJson(Map<String, dynamic> json) => TrendingModuleResponse(
    code: json['code'],
    message: json['message'],
    data: json['data'] != null ? Data.fromJson(json['data']) : null,
  );

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    'data': data?.toJson(),
  };
}

class Data {
  String? title;
  List<Subject>? subjectList;
  Pager? pager;

  Data({
    this.title,
    this.subjectList,
    this.pager,
  });

  factory Data.fromJson(Map<String, dynamic> json) => Data(
    title: json['title'],
    subjectList: json['subjectList'] != null
        ? List<Subject>.from(json['subjectList'].map((x) => Subject.fromJson(x)))
        : null,
    pager: json['pager'] != null ? Pager.fromJson(json['pager']) : null,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'subjectList': subjectList != null ? List<dynamic>.from(subjectList!.map((x) => x.toJson())) : null,
    'pager': pager?.toJson(),
  };
}

class Pager {
  bool? hasMore;
  String? nextPage;
  String? page;
  num? perPage;
  num? totalCount;

  Pager({
    this.hasMore,
    this.nextPage,
    this.page,
    this.perPage,
    this.totalCount,
  });

  factory Pager.fromJson(Map<String, dynamic> json) => Pager(
    hasMore: json['hasMore'],
    nextPage: json['nextPage'],
    page: json['page'],
    perPage: json['perPage'],
    totalCount: json['totalCount'],
  );

  Map<String, dynamic> toJson() => {
    'hasMore': hasMore,
    'nextPage': nextPage,
    'page': page,
    'perPage': perPage,
    'totalCount': totalCount,
  };
}

