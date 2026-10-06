class StatusModel {
  final String? id;
  final String name;
  final String image;
  final DateTime time;
  final bool seen;
  final bool isVideo;
  final String? caption;
  final bool isMine;

  StatusModel({
    this.id,
    required this.name,
    required this.image,
    required this.time,
    this.seen = false,
    this.isVideo = false,
    this.caption,
    this.isMine = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name, 'image': image, 'time': time.toIso8601String(),
    'seen': seen, 'is_video': isVideo, 'caption': caption, 'is_mine': isMine,
  };

  factory StatusModel.fromJson(Map<String, dynamic> json) => StatusModel(
    id: json['id'] as String?,
    name: json['name'] as String? ?? 'Me',
    image: json['image'] as String? ?? '',
    time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
    seen: json['seen'] as bool? ?? false,
    isVideo: json['is_video'] as bool? ?? false,
    caption: json['caption'] as String?,
    isMine: json['is_mine'] as bool? ?? false,
  );
}
