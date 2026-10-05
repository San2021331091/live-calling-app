enum CallType { incoming, outgoing, missed }
enum CallMedia { audio, video }

class CallModel {
  final String id;
  final String name;
  final String avatar;
  final DateTime time;
  final CallType type;
  final CallMedia media;
  final String? peerId;
  final String? status;

  CallModel({
    required this.id,
    required this.name,
    required this.avatar,
    required this.time,
    required this.type,
    required this.media,
    this.peerId,
    this.status,
  });

  factory CallModel.fromJson(
    Map<String, dynamic> json, {
    String currentUserId = '',
  }) {
    final startedAt = DateTime.tryParse(json['started_at'] as String? ?? '') ?? DateTime.now();
    final kind = json['kind'] as String? ?? 'audio';
    final status = json['status'] as String? ?? 'started';
    final callerId = json['caller_id'] as String? ?? '';
    final calleeId = json['callee_id'] as String? ?? '';
    final peerId = (json['peer_id'] as String?) ?? (currentUserId == callerId ? calleeId : callerId);
    final displayName = (json['peer_name'] as String?) ?? 'Unknown contact';
    final normalizedType = status == 'missed'
        ? CallType.missed
        : currentUserId == callerId
        ? CallType.outgoing
        : CallType.incoming;

    return CallModel(
      id: json['id'] as String? ?? '',
      name: displayName,
      avatar: 'https://i.pravatar.cc/150?u=$peerId',
      time: startedAt,
      type: normalizedType,
      media: kind == 'video' ? CallMedia.video : CallMedia.audio,
      peerId: peerId,
      status: status,
    );
  }
}
