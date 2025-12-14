import 'dart:convert';

// Helper function to decode the JSON string
DetailedApiResponse detailedApiResponseFromJson(String str) => DetailedApiResponse.fromJson(json.decode(str));
// Helper function to encode to a JSON string
String detailedApiResponseToJson(DetailedApiResponse data) => json.encode(data.toJson());

class DetailedApiResponse {
  final int? code;
  final String? message;
  final ApiData? data;

  DetailedApiResponse({
    this.code,
    this.message,
    this.data,
  });

  factory DetailedApiResponse.fromJson(Map<String, dynamic> json) => DetailedApiResponse(
    code: json["code"],
    message: json["message"],
    data: json["data"] == null ? null : ApiData.fromJson(json["data"]),
  );

  Map<String, dynamic> toJson() => {
    "code": code,
    "message": message,
    "data": data?.toJson(),
  };
}

class ApiData {
  final Subject? subject;
  final List<Star>? stars;
  final Metadata? metadata;
  final String? url;
  final String? referer;
  final bool? isForbid;
  final int? watchTimeLimit;

  ApiData({
    this.subject,
    this.stars,
    this.metadata,
    this.url,
    this.referer,
    this.isForbid,
    this.watchTimeLimit,
  });

  factory ApiData.fromJson(Map<String, dynamic> json) => ApiData(
    subject: json["subject"] == null ? null : Subject.fromJson(json["subject"]),
    stars: json["stars"] == null ? [] : List<Star>.from(json["stars"]!.map((x) => Star.fromJson(x))),
    metadata: json["metadata"] == null ? null : Metadata.fromJson(json["metadata"]),
    url: json["url"],
    referer: json["referer"],
    isForbid: json["isForbid"],
    watchTimeLimit: json["watchTimeLimit"],
  );

  Map<String, dynamic> toJson() => {
    "subject": subject?.toJson(),
    "stars": stars == null ? [] : List<dynamic>.from(stars!.map((x) => x.toJson())),
    "metadata": metadata?.toJson(),
    "url": url,
    "referer": referer,
    "isForbid": isForbid,
    "watchTimeLimit": watchTimeLimit,
  };
}

class Subject {
  final String? subjectId;
  final int? subjectType;
  final String? title;
  final String? description;
  final String? releaseDate;
  final int? duration;
  final String? genre;
  final Cover? cover;
  final String? countryName;
  final String? imdbRatingValue;
  final String? subtitles;
  final String? ops;
  final bool? hasResource;
  final Trailer? trailer;
  final String? detailPath;
  final List<dynamic>? staffList;
  final int? appointmentCnt;
  final String? appointmentDate;
  final String? corner;
  final int? imdbRatingCount;
  final Cover? stills;
  final String? postTitle;
  final Resource? resource;

  Subject({
    this.subjectId,
    this.subjectType,
    this.title,
    this.description,
    this.releaseDate,
    this.duration,
    this.genre,
    this.cover,
    this.countryName,
    this.imdbRatingValue,
    this.subtitles,
    this.ops,
    this.hasResource,
    this.trailer,
    this.detailPath,
    this.staffList,
    this.appointmentCnt,
    this.appointmentDate,
    this.corner,
    this.imdbRatingCount,
    this.stills,
    this.postTitle,
    this.resource,
  });

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
    subjectId: json["subjectId"],
    subjectType: json["subjectType"],
    title: json["title"],
    description: json["description"],
    releaseDate: json["releaseDate"],
    duration: json["duration"],
    genre: json["genre"],
    cover: json["cover"] == null ? null : Cover.fromJson(json["cover"]),
    countryName: json["countryName"],
    imdbRatingValue: json["imdbRatingValue"],
    subtitles: json["subtitles"],
    ops: json["ops"],
    hasResource: json["hasResource"],
    trailer: json["trailer"] == null ? null : Trailer.fromJson(json["trailer"]),
    detailPath: json["detailPath"],
    staffList: json["staffList"] == null ? [] : List<dynamic>.from(json["staffList"]!.map((x) => x)),
    appointmentCnt: json["appointmentCnt"],
    appointmentDate: json["appointmentDate"],
    corner: json["corner"],
    imdbRatingCount: json["imdbRatingCount"],
    stills: json["stills"] == null ? null : Cover.fromJson(json["stills"]),
    postTitle: json["postTitle"],
    resource: json["resource"] == null ? null : Resource.fromJson(json["resource"]),
  );

  Map<String, dynamic> toJson() => {
    "subjectId": subjectId,
    "subjectType": subjectType,
    "title": title,
    "description": description,
    "releaseDate": releaseDate,
    "duration": duration,
    "genre": genre,
    "cover": cover?.toJson(),
    "countryName": countryName,
    "imdbRatingValue": imdbRatingValue,
    "subtitles": subtitles,
    "ops": ops,
    "hasResource": hasResource,
    "trailer": trailer?.toJson(),
    "detailPath": detailPath,
    "staffList": staffList == null ? [] : List<dynamic>.from(staffList!.map((x) => x)),
    "appointmentCnt": appointmentCnt,
    "appointmentDate": appointmentDate,
    "corner": corner,
    "imdbRatingCount": imdbRatingCount,
    "stills": stills?.toJson(),
    "postTitle": postTitle,
    "resource": resource?.toJson(),
  };
}

class Cover {
  final String? url;
  final int? width;
  final int? height;
  final int? size;
  final String? format;
  final String? thumbnail;
  final String? blurHash;
  final dynamic gif;
  final String? avgHueLight;
  final String? avgHueDark;
  final String? id;

  Cover({
    this.url,
    this.width,
    this.height,
    this.size,
    this.format,
    this.thumbnail,
    this.blurHash,
    this.gif,
    this.avgHueLight,
    this.avgHueDark,
    this.id,
  });

  factory Cover.fromJson(Map<String, dynamic> json) => Cover(
    url: json["url"],
    width: json["width"],
    height: json["height"],
    size: json["size"],
    format: json["format"],
    thumbnail: json["thumbnail"],
    blurHash: json["blurHash"],
    gif: json["gif"],
    avgHueLight: json["avgHueLight"],
    avgHueDark: json["avgHueDark"],
    id: json["id"],
  );

  Map<String, dynamic> toJson() => {
    "url": url,
    "width": width,
    "height": height,
    "size": size,
    "format": format,
    "thumbnail": thumbnail,
    "blurHash": blurHash,
    "gif": gif,
    "avgHueLight": avgHueLight,
    "avgHueDark": avgHueDark,
    "id": id,
  };
}

class Trailer {
  final VideoAddress? videoAddress;
  final Cover? cover;

  Trailer({
    this.videoAddress,
    this.cover,
  });

  factory Trailer.fromJson(Map<String, dynamic> json) => Trailer(
    videoAddress: json["videoAddress"] == null ? null : VideoAddress.fromJson(json["videoAddress"]),
    cover: json["cover"] == null ? null : Cover.fromJson(json["cover"]),
  );

  Map<String, dynamic> toJson() => {
    "videoAddress": videoAddress?.toJson(),
    "cover": cover?.toJson(),
  };
}

class VideoAddress {
  final String? videoId;
  final String? definition;
  final String? url;
  final int? duration;
  final int? width;
  final int? height;
  final int? size;
  final int? fps;
  final int? bitrate;
  final int? type;

  VideoAddress({
    this.videoId,
    this.definition,
    this.url,
    this.duration,
    this.width,
    this.height,
    this.size,
    this.fps,
    this.bitrate,
    this.type,
  });

  factory VideoAddress.fromJson(Map<String, dynamic> json) => VideoAddress(
    videoId: json["videoId"],
    definition: json["definition"],
    url: json["url"],
    duration: json["duration"],
    width: json["width"],
    height: json["height"],
    size: json["size"],
    fps: json["fps"],
    bitrate: json["bitrate"],
    type: json["type"],
  );

  Map<String, dynamic> toJson() => {
    "videoId": videoId,
    "definition": definition,
    "url": url,
    "duration": duration,
    "width": width,
    "height": height,
    "size": size,
    "fps": fps,
    "bitrate": bitrate,
    "type": type,
  };
}

class Metadata {
  final String? title;
  final String? description;
  final String? keyWords;
  final String? image;
  final String? url;
  final String? referer;

  Metadata({
    this.title,
    this.description,
    this.keyWords,
    this.image,
    this.url,
    this.referer,
  });

  factory Metadata.fromJson(Map<String, dynamic> json) => Metadata(
    title: json["title"],
    description: json["description"],
    keyWords: json["keyWords"],
    image: json["image"],
    url: json["url"],
    referer: json["referer"],
  );

  Map<String, dynamic> toJson() => {
    "title": title,
    "description": description,
    "keyWords": keyWords,
    "image": image,
    "url": url,
    "referer": referer,
  };
}

class Resource {
  final List<SeasonResource>? seasons;
  final String? source;
  final String? uploadBy;

  Resource({
    this.seasons,
    this.source,
    this.uploadBy,
  });

  factory Resource.fromJson(Map<String, dynamic> json) => Resource(
    seasons: json["seasons"] == null ? [] : List<SeasonResource>.from(json["seasons"]!.map((x) => SeasonResource.fromJson(x))),
    source: json["source"],
    uploadBy: json["uploadBy"],
  );

  Map<String, dynamic> toJson() => {
    "seasons": seasons == null ? [] : List<dynamic>.from(seasons!.map((x) => x.toJson())),
    "source": source,
    "uploadBy": uploadBy,
  };
}

class SeasonResource {
  final int? se;
  final int? maxEp;
  final String? allEp;
  final List<Resolution>? resolutions;

  SeasonResource({
    this.se,
    this.maxEp,
    this.allEp,
    this.resolutions,
  });

  factory SeasonResource.fromJson(Map<String, dynamic> json) => SeasonResource(
    se: json["se"],
    maxEp: json["maxEp"],
    allEp: json["allEp"],
    resolutions: json["resolutions"] == null ? [] : List<Resolution>.from(json["resolutions"]!.map((x) => Resolution.fromJson(x))),
  );

  Map<String, dynamic> toJson() => {
    "se": se,
    "maxEp": maxEp,
    "allEp": allEp,
    "resolutions": resolutions == null ? [] : List<dynamic>.from(resolutions!.map((x) => x.toJson())),
  };
}

class Resolution {
  final int? resolution;
  final int? epNum;

  Resolution({
    this.resolution,
    this.epNum,
  });

  factory Resolution.fromJson(Map<String, dynamic> json) => Resolution(
    resolution: json["resolution"],
    epNum: json["epNum"],
  );

  Map<String, dynamic> toJson() => {
    "resolution": resolution,
    "epNum": epNum,
  };
}

class Star {
  final String? staffId;
  final int? staffType;
  final String? name;
  final String? character;
  final String? avatarUrl;
  final String? detailPath;

  Star({
    this.staffId,
    this.staffType,
    this.name,
    this.character,
    this.avatarUrl,
    this.detailPath,
  });

  factory Star.fromJson(Map<String, dynamic> json) => Star(
    staffId: json["staffId"],
    staffType: json["staffType"],
    name: json["name"],
    character: json["character"],
    avatarUrl: json["avatarUrl"],
    detailPath: json["detailPath"],
  );

  Map<String, dynamic> toJson() => {
    "staffId": staffId,
    "staffType": staffType,
    "name": name,
    "character": character,
    "avatarUrl": avatarUrl,
    "detailPath": detailPath,
  };
}

