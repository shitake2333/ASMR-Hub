class ASMRSource {
  final String id;
  final String name;
  final String url;
  final String sourceTypeId;
  final List<String> tags;
  final DateTime addedDate;

  ASMRSource({
    required this.id,
    required this.name,
    required this.url,
    required this.sourceTypeId,
    this.tags = const [],
    required this.addedDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'sourceTypeId': sourceTypeId,
      'tags': tags,
      'addedDate': addedDate.toIso8601String(),
    };
  }

  factory ASMRSource.fromJson(Map<String, dynamic> json) {
    return ASMRSource(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      sourceTypeId: json['sourceTypeId']?.toString() ?? 'local',
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          [],
      addedDate:
          DateTime.tryParse(json['addedDate']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
