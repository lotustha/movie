class StreamInfo {
  StreamInfo({
      this.format, 
      this.id, 
      this.url, 
      this.resolutions, 
      this.size, 
      this.duration, 
      this.codecName,
      this.fallbackUrl,
      this.headers,});

  StreamInfo.fromJson(dynamic json) {
    format = json['format'];
    id = json['id'];
    url = json['url'];
    resolutions = json['resolutions'];
    size = json['size'];
    duration = json['duration'];
    codecName = json['codecName'];
    fallbackUrl = json['fallbackUrl'];
    headers = (json['headers'] as Map?)?.map((k, v) => MapEntry('$k', '$v'));
  }
  String? format;
  String? id;
  String? url;
  String? resolutions;
  String? size;
  num? duration;
  String? codecName;
  // Proxied copy of [url], tried when the direct CDN request is refused.
  String? fallbackUrl;
  // Headers the CDN requires on [url] (Referer / User-Agent).
  Map<String, String>? headers;
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
  fallbackUrl: fallbackUrl,
  headers: headers,
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
    map['fallbackUrl'] = fallbackUrl;
    map['headers'] = headers;
    return map;
  }

}