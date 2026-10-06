import 'package:flutter/material.dart';
import 'package:voxa/media/media_result.dart';
import 'package:voxa/pages/camerapage.dart';
import 'package:voxa/pages/statusviewer.dart';
import 'package:voxa/services/api_client.dart';
import 'package:voxa/services/status_upload_service.dart';
import 'package:voxa/status/statusmodel.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  StatusScreenState createState() => StatusScreenState();
}

class StatusScreenState extends State<StatusScreen> {
  static const _ink = Color(0xFF17251F);
  static const _muted = Color(0xFF75827B);
  static const _green = Color(0xFF168A62);
  static const _surface = Color(0xFFF5F7F5);

  final List<StatusModel> statuses = [];
  bool _loading = true;
  bool _uploading = false;

  List<StatusModel> get _mine => statuses.where((item) => item.isMine).toList();
  List<StatusModel> get _recent =>
      statuses.where((item) => !item.isMine && !item.seen).toList();
  List<StatusModel> get _viewed =>
      statuses.where((item) => !item.isMine && item.seen).toList();

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    try {
      final loaded = await ApiClient.instance.loadStatuses();
      if (mounted) {
        setState(() {
          statuses
            ..clear()
            ..addAll(loaded);
          _loading = false;
        });
      }

    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        _showMessage('Could not load updates: ${error.message}');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        _showMessage('Could not load updates. Check your connection.');
      }
    }
  }

  Future<void> refresh() => _loadStatuses();

  Future<void> _addStatus() async {
    final result = await Navigator.push<MediaResult>(
      context,
      MaterialPageRoute(builder: (_) => const CameraPage()),
    );
    if (result == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await StatusUploadService.publish(result);
      await _loadStatuses();
      if (mounted) _showMessage('Your update is live');
    } catch (error) {
      if (mounted) _showMessage('Upload failed: $error');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _viewStatus(StatusModel status) async {
    if (!status.isMine && !status.seen && status.id != null) {
      try {
        await ApiClient.instance.markStatusViewed(status.id!);
        if (mounted) {
          setState(() {
            final index = statuses.indexWhere((item) => item.id == status.id);
            if (index >= 0) {
              final old = statuses[index];
              statuses[index] = StatusModel(
                id: old.id,
                name: old.name,
                image: old.image,
                time: old.time,
                seen: true,
                isVideo: old.isVideo,
                caption: old.caption,
                isMine: old.isMine,
              );
            }
          });
        }
      } on ApiException catch (error) {
        if (mounted) _showMessage(error.message);
      }
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StatusViewer(status: status)),
    );
    await _loadStatuses();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    final recent = _recent;
    final viewed = _viewed;
    return Scaffold(
      backgroundColor: _surface,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : RefreshIndicator(
              color: _green,
              onRefresh: _loadStatuses,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 96),
                children: [
                  _pageHeading(),
                  const SizedBox(height: 20),
                  _myStatusCard(mine),
                  if (recent.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _sectionHeading('New updates', '${recent.length}'),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 116,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: recent.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 16),
                        itemBuilder: (_, index) => _storyBubble(recent[index]),
                      ),
                    ),
                  ],
                  if (mine.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _sectionHeading('Your updates', '${mine.length}'),
                    const SizedBox(height: 12),
                    _updatesCard(mine),
                  ],
                  if (viewed.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _sectionHeading('Viewed', '${viewed.length}'),
                    const SizedBox(height: 12),
                    _updatesCard(viewed),
                  ],
                  if (mine.isEmpty && recent.isEmpty && viewed.isEmpty) ...[
                    const SizedBox(height: 34),
                    _emptyState(),
                  ],
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: _uploading ? null : _addStatus,
        icon: _uploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.add_a_photo_outlined),
        label: Text(_uploading ? 'Uploading' : 'Add update'),
      ),
    );
  }

  Widget _pageHeading() => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your moments',
              style: TextStyle(
                fontSize: 25,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: _ink,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Photos and videos disappear after 24 hours',
              style: TextStyle(fontSize: 12.5, color: _muted),
            ),
          ],
        ),
      ),
      Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: 'Refresh updates',
          onPressed: _loadStatuses,
          icon: const Icon(Icons.refresh_rounded, color: _ink),
        ),
      ),
    ],
  );

  Widget _myStatusCard(List<StatusModel> mine) {
    final latest = mine.isEmpty ? null : mine.first;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: _uploading
            ? null
            : latest == null
            ? _addStatus
            : () => _viewStatus(latest),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              _avatar(latest, size: 56, addBadge: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'My status',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _uploading
                          ? 'Uploading your update…'
                          : latest == null
                          ? 'Share a photo or a short video'
                          : '${_timeAgo(latest.time)} · ${mine.length} update${mine.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: _muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeading(String title, String count) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFE6F3ED),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          count,
          style: const TextStyle(
            color: _green,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );

  Widget _storyBubble(StatusModel status) => SizedBox(
    width: 72,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _viewStatus(status),
      child: Column(
        children: [
          _avatar(status, size: 62),
          const SizedBox(height: 8),
          Text(
            status.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _timeAgo(status.time),
            maxLines: 1,
            style: const TextStyle(fontSize: 9.5, color: _muted),
          ),
        ],
      ),
    ),
  );

  Widget _avatar(
    StatusModel? status, {
    required double size,
    bool addBadge = false,
  }) {
    final seen = status?.seen ?? false;
    final isVideo = status?.isVideo ?? false;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: status == null
                ? const LinearGradient(
                    colors: [Color(0xFF46BD8A), Color(0xFF168A62)],
                  )
                : seen
                ? const LinearGradient(
                    colors: [Color(0xFFCBD2CE), Color(0xFF9AA49E)],
                  )
                : const LinearGradient(
                    colors: [
                      Color(0xFF45C88D),
                      Color(0xFF14855E),
                      Color(0xFF7BD8A8),
                    ],
                  ),
          ),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: status != null && !isVideo
                  ? Image.network(
                      status.image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _avatarPlaceholder(),
                    )
                  : _avatarPlaceholder(video: isVideo),
            ),
          ),
        ),
        if (addBadge)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 21,
              height: 21,
              decoration: BoxDecoration(
                color: _green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.add, size: 15, color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _avatarPlaceholder({bool video = false}) => Container(
    color: const Color(0xFFEAF2ED),
    child: Icon(
      video ? Icons.videocam_rounded : Icons.person_rounded,
      color: _green,
    ),
  );

  Widget _updatesCard(List<StatusModel> items) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _updateRow(items[index]),
          if (index < items.length - 1)
            const Divider(height: 1, indent: 78, endIndent: 16),
        ],
      ],
    ),
  );

  Widget _updateRow(StatusModel status) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: () => _viewStatus(status),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      child: Row(
        children: [
          _avatar(status, size: 48),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status.caption?.isNotEmpty == true
                      ? status.caption!
                      : status.isVideo
                      ? 'Video update'
                      : 'Photo update',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _timeAgo(status.time),
            style: const TextStyle(fontSize: 10, color: _muted),
          ),
        ],
      ),
    ),
  );

  Widget _emptyState() => Container(
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE7F5ED), Color(0xFFF7FAF8)],
      ),
    ),
    child: Column(
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.auto_awesome_mosaic_rounded,
            size: 30,
            color: _green,
          ),
        ),
        const SizedBox(height: 17),
        const Text(
          'A little update goes a long way',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Share a moment with people you chat with. Your update stays up for 24 hours.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.5, color: _muted),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _uploading ? null : _addStatus,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Create an update'),
          style: FilledButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );

  String _timeAgo(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inMinutes < 1) return 'Now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m';
    if (difference.inHours < 24) return '${difference.inHours}h';
    return '${difference.inDays}d';
  }
}
