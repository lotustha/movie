class SearchSuggestWordModel {
  SearchSuggestWordModel({
      this.type, 
      this.word,});

  SearchSuggestWordModel.fromJson(dynamic json) {
    type = json['type'];
    word = json['word'];
  }
  num? type;
  String? word;
SearchSuggestWordModel copyWith({  num? type,
  String? word,
}) => SearchSuggestWordModel(  type: type ?? this.type,
  word: word ?? this.word,
);
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['type'] = type;
    map['word'] = word;
    return map;
  }

}