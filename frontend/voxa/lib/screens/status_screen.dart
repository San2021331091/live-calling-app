import 'package:flutter/material.dart';
import 'package:voxa/media/media_result.dart';
import 'package:voxa/pages/camerapage.dart';
import 'package:voxa/pages/statusviewer.dart';
import 'package:voxa/services/api_client.dart';
import 'package:voxa/services/media_upload_service.dart';
import 'package:voxa/status/statusmodel.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final List<StatusModel> statuses = [];
  bool _loading = true;
  bool _uploading = false;

  List<StatusModel> get _mine => statuses.where((status) => status.isMine).toList();
  List<StatusModel> get _recent => statuses.where((status) => !status.isMine && !status.seen).toList();
  List<StatusModel> get _viewed => statuses.where((status) => !status.isMine && status.seen).toList();

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    try {
      final loaded = await ApiClient.instance.loadStatuses();
      if (mounted) setState(() { statuses..clear()..addAll(loaded); _loading = false; });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load statuses: ${error.message}')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load statuses. Check your connection.')));
      }
    }
  }

  Future<void> _addStatus() async {
    final result = await Navigator.push<MediaResult>(context, MaterialPageRoute(builder: (_) => const CameraPage()));
    if (result == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final url = await MediaUploadService.upload(result.file, isVideo: result.isVideo);
      await ApiClient.instance.createStatus(image: url, isVideo: result.isVideo, caption: result.caption);
      await _loadStatuses();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status upload failed: $error')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _viewStatus(StatusModel status) async {
    if (!status.isMine && !status.seen && status.id != null) {
      try {
        await ApiClient.instance.markStatusViewed(status.id!);
        if (mounted) setState(() {
          final index = statuses.indexWhere((item) => item.id == status.id);
          if (index >= 0) {
            final old = statuses[index];
            statuses[index] = StatusModel(id: old.id, name: old.name, image: old.image, time: old.time,
              seen: true, isVideo: old.isVideo, caption: old.caption, isMine: old.isMine);
          }
        });
      } on ApiException catch (error) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => StatusViewer(status: status)));
    await _loadStatuses();
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    final recent = _recent;
    final viewed = _viewed;
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStatuses,
              child: ListView(
                children: [
                  _myStatusTile(mine),
                  if (mine.isNotEmpty) ...[
                    _sectionTitle('My updates'),
                    ...mine.map(_statusTile),
                  ],
                  if (recent.isNotEmpty) ...[
                    _sectionTitle('Recent updates'),
                    ...recent.map(_statusTile),
                  ],
                  if (viewed.isNotEmpty) ...[
                    _sectionTitle('Viewed updates'),
                    ...viewed.map(_statusTile),
                  ],
                  if (mine.isEmpty && recent.isEmpty && viewed.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(28, 44, 28, 24),
                      child: Text('No status updates yet. Share a photo or video to get started.', textAlign: TextAlign.center),
                    ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF25D366),
        onPressed: _uploading ? null : _addStatus,
        child: _uploading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.camera_alt, color: Colors.white),
      ),
    );
  }

  Widget _myStatusTile(List<StatusModel> mine) {
    final first = mine.isEmpty ? null : mine.first;
    return ListTile(
      leading: Stack(children: [
        CircleAvatar(
          radius: 26,
          backgroundImage: first != null && !first.isVideo ? NetworkImage(first.image) : null,
          child: first == null || first.isVideo ? const Icon(Icons.person) : null,
        ),
        const Positioned(bottom: 0, right: 0, child: CircleAvatar(radius: 10, backgroundColor: Color(0xFF25D366), child: Icon(Icons.add, size: 16, color: Colors.white))),
      ]),
      title: const Text('My status', style: TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(_uploading ? 'Uploading status...' : first == null ? 'Tap to add status update' : '${mine.length} update${mine.length == 1 ? '' : 's'} · Tap to view or add'),
      onTap: _uploading ? null : first == null ? _addStatus : () => _viewStatus(first),
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
  );

  Widget _statusTile(StatusModel status) => ListTile(
    leading: Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: status.seen ? Colors.grey : const Color(0xFF25D366), width: 3)),
      child: CircleAvatar(
        radius: 22,
        backgroundImage: status.isVideo ? null : NetworkImage(status.image),
        child: status.isVideo ? const Icon(Icons.videocam) : null,
      ),
    ),
    title: Text(status.name, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(_timeAgo(status.time)),
    onTap: () => _viewStatus(status),
  );

  String _timeAgo(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} minutes ago';
    if (difference.inHours < 24) return '${difference.inHours} hours ago';
    return '${difference.inDays} days ago';
  }
}
