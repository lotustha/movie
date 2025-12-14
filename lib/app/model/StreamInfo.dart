class StreamInfo {
  StreamInfo({
      this.format, 
      this.id, 
      this.url, 
      this.resolutions, 
      this.size, 
      this.duration, 
      this.codecName,});

  StreamInfo.fromJson(dynamic json) {
    format = json['format'];
    id = json['id'];
    url = json['url'];
    resolutions = json['resolutions'];
    size = json['size'];
    duration = json['duration'];
    codecName = json['codecName'];
  }
  String? format;
  String? id;
  String? url;
  String? resolutions;
  String? size;
  num? duration;
  String? codecName;
StreamInfo copyWith({  String? format,
  String? id,
  String? url,
  String? resolutions,
  String? size,
  num? duration,
  String? codecName,
}) => StreamInfo(  format: format ?? this.format,
  id: id ?? this.id,
  url: url ?? this.url,
  resolutions: resolutions ?? this.resolutions,
  size: size ?? this.size,
  duration: duration ?? this.duration,
  codecName: codecName ?? this.codecName,
);
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['format'] = format;
    map['id'] = id;
    map['url'] = url;
    map['resolutions'] = resolutions;
    map['size'] = size;
    map['duration'] = duration;
    map['codecName'] = codecName;
    return map;
  }

}