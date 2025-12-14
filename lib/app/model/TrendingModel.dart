class TrendingModel {
  TrendingModel({
      this.name, 
      this.id,});

  TrendingModel.fromJson(dynamic json) {
    name = json['name'];
    id = json['id'];
  }
  String? name;
  String? id;
TrendingModel copyWith({  String? name,
  String? id,
}) => TrendingModel(  name: name ?? this.name,
  id: id ?? this.id,
);
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['name'] = name;
    map['id'] = id;
    return map;
  }

}