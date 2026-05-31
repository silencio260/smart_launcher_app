import 'package:flutter/material.dart';

import '../../data/mini_app_repositories.dart';
import '../../services/launcher_service.dart';
import 'mini_app_chrome.dart';

class FileLockerScreen extends StatefulWidget {
  const FileLockerScreen({super.key});

  @override
  State<FileLockerScreen> createState() => _FileLockerScreenState();
}

class _FileLockerScreenState extends State<FileLockerScreen> {
  final _repo = VaultRepository();
  var _unlocked = false;
  var _selectedAlbum = 'photos';

  @override
  void initState() {
    super.initState();
    _unlock();
  }

  Future<void> _unlock() async {
    final ok = await LauncherService.authenticateDevice(
      title: 'Unlock File Locker',
      description: 'Open your encrypted private vault',
    );
    if (!mounted) return;
    if (!ok) {
      Navigator.pop(context);
      return;
    }
    await _repo.ensureDefaults();
    if (mounted) setState(() => _unlocked = true);
  }

  @override
  Widget build(BuildContext context) {
    return MiniAppScaffold(
      title: 'File Locker',
      actions: [
        IconButton(
          icon: const Icon(Icons.add, color: miniAppAccent),
          onPressed: _unlocked ? _importFile : null,
        ),
      ],
      child: !_unlocked
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => setState(() {}),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                children: [
                  _buildSecurityHeader(),
                  const SizedBox(height: 18),
                  _buildAlbumRail(),
                  const SizedBox(height: 18),
                  _buildVaultGrid(),
                  const SizedBox(height: 18),
                  _buildPrivacyTools(),
                ],
              ),
            ),
    );
  }

  Widget _buildSecurityHeader() {
    final count = _repo.items().length;
    return MiniCard(
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Color(0xFF06382F),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock, color: Color(0xFF3BE6C2)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Encrypted vault',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 4),
                Text(
                  '$count private item${count == 1 ? '' : 's'} secured',
                  style: const TextStyle(color: miniAppMuted),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: _importFile,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('Import'),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumRail() {
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final album = _repo.albums()[index];
          final id = album['id'].toString();
          final selected = id == _selectedAlbum;
          final count =
              _repo.items().where((item) => item['albumId'] == id).length;
          return InkWell(
            onTap: () => setState(() => _selectedAlbum = id),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 138,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected ? miniAppAccent : miniAppSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_albumIcon(id),
                      color: selected ? Colors.black : miniAppAccent),
                  const Spacer(),
                  Text(
                    album['name'].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '$count items',
                    style: TextStyle(
                      color: selected ? Colors.black54 : miniAppMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: _repo.albums().length,
      ),
    );
  }

  Widget _buildVaultGrid() {
    final items = _repo
        .items()
        .where((item) => item['albumId'] == _selectedAlbum)
        .toList(growable: false);
    if (items.isEmpty) {
      return const SizedBox(
        height: 260,
        child: EmptyMiniState(
          icon: Icons.enhanced_encryption_outlined,
          title: 'Nothing in this album',
          subtitle:
              'Import private photos, videos, or documents into the vault.',
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.92,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return MiniCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: miniAppSurface2,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  child: Icon(_fileIcon(item['name'].toString()),
                      color: miniAppAccent, size: 46),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item['name'].toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    PopupMenuButton<String>(
                      color: miniAppSurface,
                      onSelected: (value) => _handleItemAction(value, item),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'export', child: Text('Export')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPrivacyTools() {
    return Column(
      children: [
        PermissionPill(
          icon: Icons.warning_amber_rounded,
          label: 'Fake crash screen',
          value: 'Ready',
          onTap: () {},
        ),
        const SizedBox(height: 10),
        PermissionPill(
          icon: Icons.camera_alt_outlined,
          label: 'Break-in attempts',
          value: 'Capture',
          onTap: () {},
        ),
        const SizedBox(height: 10),
        PermissionPill(
          icon: Icons.restore_outlined,
          label: 'Recovery setup',
          value: 'Needed',
          onTap: () {},
        ),
      ],
    );
  }

  Future<void> _importFile() async {
    final data = await LauncherService.importLockedFileDetails();
    if (!mounted || data == null) return;
    await _repo.addNativeImport(data);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('File added to encrypted vault')),
    );
  }

  Future<void> _handleItemAction(
    String value,
    Map<String, Object?> item,
  ) async {
    final id = item['id'].toString();
    if (value == 'export') {
      await LauncherService.exportLockedFile(id);
      return;
    }
    if (value == 'delete') {
      await LauncherService.deleteLockedFile(id);
      await _repo.deleteItem(id);
      if (mounted) setState(() {});
    }
  }

  IconData _albumIcon(String id) => switch (id) {
        'photos' => Icons.photo_library_outlined,
        'videos' => Icons.video_library_outlined,
        'notes' => Icons.note_alt_outlined,
        _ => Icons.insert_drive_file_outlined,
      };

  IconData _fileIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    if (lower.endsWith('.mp4') || lower.endsWith('.mov')) {
      return Icons.play_circle_outline;
    }
    return Icons.description_outlined;
  }
}
