import 'package:flutter/material.dart';

import '../../services/launcher_service.dart';

class FileLockerScreen extends StatefulWidget {
  const FileLockerScreen({super.key});

  @override
  State<FileLockerScreen> createState() => _FileLockerScreenState();
}

class _FileLockerScreenState extends State<FileLockerScreen> {
  late Future<List<Map<String, dynamic>>> _filesFuture;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _filesFuture = Future.value(const []);
    _unlock();
  }

  void _reload() {
    _filesFuture = LauncherService.listLockedFiles();
  }

  Future<void> _unlock() async {
    final ok = await LauncherService.authenticateDevice(
      title: 'Unlock File Locker',
      description: 'Confirm your device lock to view locked files',
    );
    if (!mounted) return;
    if (!ok) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _unlocked = true;
      _reload();
    });
  }

  Future<void> _importFile() async {
    final ok = await LauncherService.importLockedFile();
    if (!mounted) return;
    setState(_reload);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File added to locker')),
      );
    }
  }

  Future<void> _exportFile(String id) async {
    await LauncherService.exportLockedFile(id);
  }

  Future<void> _deleteFile(String id) async {
    final ok = await LauncherService.deleteLockedFile(id);
    if (!mounted) return;
    if (ok) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('File Locker')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _unlocked ? _importFile : null,
        icon: const Icon(Icons.add),
        label: const Text('Add file'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _filesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!_unlocked) {
            return const Center(child: CircularProgressIndicator());
          }
          final files = snapshot.data ?? const [];
          if (files.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No locked files yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: files.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final file = files[index];
              final id = file['id']?.toString() ?? '';
              final name = file['name']?.toString() ?? 'Locked file';
              final size = file['size'] as int? ?? 0;
              return ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_formatSize(size)),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'export') _exportFile(id);
                    if (value == 'delete') _deleteFile(id);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'export',
                      child: Text('Export'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}
