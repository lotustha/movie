class CaptionApiResponse {
  CaptionApiResponse({
      this.code, 
      this.message, 
      this.data,});

  CaptionApiResponse.fromJson(dynamic json) {
    code = json['code'];
    message = json['message'];
    data = json['data'] != null ? Data.fromJson(json['data']) : null;
  }
  num? code;
  String? message;
  Data? data;
CaptionApiResponse copyWith({  num? code,
  String? message,
  Data? data,
}) => CaptionApiResponse(  code: code ?? this.code,
  message: message ?? this.message,
  data: data ?? this.data,
);
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['code'] = code;
    map['message'] = message;
    if (data != null) {
      map['data'] = data?.toJson();
    }
    return map;
  }

}

class Data {
  Data({
      this.captions,});

  Data.fromJson(dynamic json) {
    if (json['captions'] != null) {
      captions = [];
      json['captions'].forEach((v) {
        captions?.add(Captions.fromJson(v));
      });
    }
  }
  List<Captions>? captions;
Data copyWith({  List<Captions>? captions,
}) => Data(  captions: captions ?? this.captions,
);
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (captions != null) {
      map['captions'] = captions?.map((v) => v.toJson()).toList();
    }
    return map;
  }

}

class Captions {
  Captions({
      this.id, 
      this.lan, 
      this.lanName, 
      this.url, 
      this.size, 
      this.delay,});

  Captions.fromJson(dynamic json) {
    id = json['id'];
    lan = json['lan'];
    lanName = json['lanName'];
    url = json['url'];
    size = json['size'];
    delay = json['delay'];
  }
  String? id;
  String? lan;
  String? lanName;
  String? url;
  String? size;
  num? delay;
Captions copyWith({  String? id,
  String? lan,
  String? lanName,
  String? url,
  String? size,
  num? delay,
}) => Captions(  id: id ?? this.id,
  lan: lan ?? this.lan,
  lanName: lanName ?? this.lanName,
  url: url ?? this.url,
  size: size ?? this.size,
  delay: delay ?? this.delay,
);
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['id'] = id;
    map['lan'] = lan;
    map['lanName'] = lanName;
    map['url'] = url;
    map['size'] = size;
    map['delay'] = delay;
    return map;
  }

}