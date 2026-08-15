class AccountInfo {
  final String? cookie;
  final String name;
  final String? avatarUrl;
  final String? id;

  AccountInfo({this.cookie, required this.name, this.avatarUrl, this.id});

  Map<String, dynamic> toJson() => {
    'cookie': cookie,
    'name': name,
    'avatarUrl': avatarUrl,
    'id': id,
  };

  factory AccountInfo.fromJson(Map<String, dynamic> json) {
    return AccountInfo(
      cookie: json['cookie']?.toString(),
      name: json['name']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString(),
      id: json['id']?.toString(),
    );
  }
}
