// operating_list_model.dart

import 'package:movie/app/model/subject_list.dart';

class OperatingList {
  final String type;
  final int position;
  final String title;
  final List<Subject> subjects;
  final Banner? banner;
  final String opId;
  final String url;
  final List<LiveMatch> liveList;
  final List<Filter> filters;
  final CustomData? customData;
  final String path;

  OperatingList({
    required this.type,
    required this.position,
    required this.title,
    required this.subjects,
    this.banner,
    required this.opId,
    required this.url,
    required this.liveList,
    required this.filters,
    this.customData,
    required this.path,
  });

  factory OperatingList.fromJson(Map<String, dynamic> json) {
    return OperatingList(
      type: json['type'] ?? '',
      position: json['position'] ?? 0,
      title: json['title'] ?? '',
      subjects: (json['subjects'] as List<dynamic>?)
          ?.map((e) => Subject.fromJson(e as Map<String, dynamic>))
          .toList() ??
          [],
      banner: json['banner'] != null
          ? Banner.fromJson(json['banner'] as Map<String, dynamic>)
          : null,
      opId: json['opId'] ?? '',
      url: json['url'] ?? '',
      liveList: (json['liveList'] as List<dynamic>?)
          ?.map((e) => LiveMatch.fromJson(e as Map<String, dynamic>))
          .toList() ??
          [],
      filters: (json['filters'] as List<dynamic>?)
          ?.map((e) => Filter.fromJson(e as Map<String, dynamic>))
          .toList() ??
          [],
      customData: json['customData'] != null
          ? CustomData.fromJson(json['customData'] as Map<String, dynamic>)
          : null,
      path: json['path'] ?? '',
    );
  }
}

class Banner {
  final List<BannerItem> items;

  Banner({required this.items});

  factory Banner.fromJson(Map<String, dynamic> json) {
    return Banner(
      items: (json['items'] as List<dynamic>?)
          ?.map((e) => BannerItem.fromJson(e as Map<String, dynamic>))
          .toList() ??
          [],
    );
  }
}

class BannerItem {
  final String id;
  final String title;
  final ImageModel image;
  final String url;
  final String subjectId;
  final int subjectType;
  final Subject? subject;
  final String detailPath;

  BannerItem({
    required this.id,
    required this.title,
    required this.image,
    required this.url,
    required this.subjectId,
    required this.subjectType,
    this.subject,
    required this.detailPath,
  });

  factory BannerItem.fromJson(Map<String, dynamic> json) {
    return BannerItem(
      id: json['id'] ?? '0',
      title: json['title'] ?? '',
      image: ImageModel.fromJson(json['image'] as Map<String, dynamic>),
      url: json['url'] ?? '',
      subjectId: json['subjectId'] ?? '0',
      subjectType: json['subjectType'] ?? 0,
      subject: json['subject'] != null
          ? Subject.fromJson(json['subject'] as Map<String, dynamic>)
          : null,
      detailPath: json['detailPath'] ?? '',
    );
  }
}


class ImageModel {
  final String url;
  final int width;
  final int height;
  final String id;

  ImageModel({
    required this.url,
    required this.width,
    required this.height,
    required this.id,
  });

  factory ImageModel.fromJson(Map<String, dynamic> json) {
    return ImageModel(
      url: json['url'] ?? '',
      width: json['width'] ?? 0,
      height: json['height'] ?? 0,
      id: json['id'] ?? '0',
    );
  }
}

class Filter {
  final String title;
  final String url;
  final ImageModel image;

  Filter({
    required this.title,
    required this.url,
    required this.image,
  });

  factory Filter.fromJson(Map<String, dynamic> json) {
    return Filter(
      title: json['title'] ?? '',
      url: json['url'] ?? '',
      image: ImageModel.fromJson(json['image'] as Map<String, dynamic>),
    );
  }
}

class LiveMatch {
  final String matchId;
  final Team team1;
  final Team team2;
  final String startTime;
  final String content;
  final String status;
  final String url;
  final ImageModel image;

  LiveMatch({
    required this.matchId,
    required this.team1,
    required this.team2,
    required this.startTime,
    required this.content,
    required this.status,
    required this.url,
    required this.image,
  });

  factory LiveMatch.fromJson(Map<String, dynamic> json) {
    return LiveMatch(
      matchId: json['matchId'] ?? '0',
      team1: Team.fromJson(json['team1'] as Map<String, dynamic>),
      team2: Team.fromJson(json['team2'] as Map<String, dynamic>),
      startTime: json['startTime'] ?? '',
      content: json['content'] ?? '',
      status: json['status'] ?? '',
      url: json['url'] ?? '',
      image: ImageModel.fromJson(json['image'] as Map<String, dynamic>),
    );
  }
}

class Team {
  final String id;
  final String name;
  final String score;
  final String avatar;
  final String voteCount;

  Team({
    required this.id,
    required this.name,
    required this.score,
    required this.avatar,
    required this.voteCount,
  });

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      id: json['id'] ?? '0',
      name: json['name'] ?? '',
      score: json['score'] ?? '0',
      avatar: json['avatar'] ?? '',
      voteCount: json['voteCount'] ?? '0',
    );
  }
}

class CustomData {
  final int rowCount;
  final List<CustomDataItem> items;
  final bool? hiddenTitle;

  CustomData({
    required this.rowCount,
    required this.items,
    this.hiddenTitle,
  });

  factory CustomData.fromJson(Map<String, dynamic> json) {
    return CustomData(
      rowCount: json['rowCount'] ?? 1,
      items: (json['items'] as List<dynamic>?)
          ?.map((e) => CustomDataItem.fromJson(e as Map<String, dynamic>))
          .toList() ??
          [],
      hiddenTitle: json['hiddenTitle'],
    );
  }
}

class CustomDataItem {
  final String id;
  final String title;
  final ImageModel image;
  final String url;
  final String subjectId;
  final int subjectType;
  final Subject? subject;
  final String detailPath;

  CustomDataItem({
    required this.id,
    required this.title,
    required this.image,
    required this.url,
    required this.subjectId,
    required this.subjectType,
    this.subject,
    required this.detailPath,
  });

  factory CustomDataItem.fromJson(Map<String, dynamic> json) {
    return CustomDataItem(
      id: json['id'] ?? '0',
      title: json['title'] ?? '',
      image: ImageModel.fromJson(json['image'] as Map<String, dynamic>),
      url: json['url'] ?? '',
      subjectId: json['subjectId'] ?? '0',
      subjectType: json['subjectType'] ?? 0,
      subject: json['subject'] != null
          ? Subject.fromJson(json['subject'] as Map<String, dynamic>)
          : null,
      detailPath: json['detailPath'] ?? '',
    );
  }
}