import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/mini_app_repositories.dart';
import '../../services/launcher_service.dart';
import 'clock/clock_theme.dart';
import 'mini_app_chrome.dart';
import 'mini_app_kit.dart';
import 'vault/vault_lock_screen.dart';
import 'vault/vault_settings_screen.dart';
import 'vault/vault_viewer_screen.dart';

/// The vault: a simple, monochrome (alarm-themed) encrypted file locker. One
/// default "All" folder; imports land there unless another folder is open.
/// Unlocking is a custom PIN/pattern + fingerprint (see [VaultLockScreen]).
class FileLockerScreen extends StatefulWidget {
  const FileLockerScreen({super.key});

  @override
  State<FileLockerScreen> createState() => _FileLockerScreenState();
}

class _FileLockerScreenState extends State<FileLockerScreen>
    with WidgetsBindingObserver {
  final _repo = VaultRepository();
  final _sec = VaultSecurityRepository();
  final _thumbs = <String, Future<Uint8List?>>{};
  var _unlocked = false;
  var _pendingImport = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_sec.isConfigured && _sec.withinGrace) {
      _unlocked = true;
      // Already-seeded users: refresh once the (idempotent) defaults/migration
      // settle so counts and any consolidated "All" folder are up to date.
      _repo.ensureDefaults().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Leaving the vault: drop any decrypted previews we wrote to cache.
    LauncherService.clearVaultViewCache();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    // Returning from the file picker: pick up whatever was imported.
    if (_pendingImport) {
      _pendingImport = false;
      _reconcile(VaultRepository.allAlbumId, 'All');
      return;
    }
    // Keep the current unlock while this screen is alive. Android also sends
    // resumed after file pickers and system prompts, so re-locking here makes
    // normal vault actions feel random.
  }

  Future<void> _onUnlocked() async {
    await _repo.ensureDefaults();
    if (mounted) setState(() => _unlocked = true);
  }

  Future<Uint8List?> _thumb(String id) =>
      _thumbs.putIfAbsent(id, () => LauncherService.vaultThumbnail(id));

  Future<void> _reconcile(String albumId, String label) async {
    final added = await _repo.reconcileNativeImports(albumId);
    if (!mounted) return;
    setState(() {});
    if (added > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Added $added item${added == 1 ? '' : 's'} to $label')),
      );
    }
  }

  Future<void> _import() async {
    _pendingImport = true;
    await LauncherService.pickVaultFiles(
      deleteOriginals: _sec.removeOriginals,
    );
  }

  Future<void> _newFolder() async {
    final name = await showMiniTextDialog(
      context,
      title: 'New folder',
      accent: Colors.white,
      hintText: 'Folder name',
      confirmLabel: 'Create',
    );
    if (name == null || !mounted) return;
    await _repo.addAlbum(name);
    if (mounted) setState(() {});
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const VaultSettingsScreen()))
        .then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openFolder(String id, String name) {
    Navigator.of(context)
        .push(MaterialPageRoute(
      builder: (_) => VaultFolderScreen(albumId: id, albumName: name),
    ))
        .then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _folderMenu(String id, String name) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: miniAppSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline,
                  color: Colors.white),
              title: const Text('Rename folder'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.white),
              title: const Text('Delete folder'),
              subtitle: const Text('Items move to All',
                  style: TextStyle(color: miniAppMuted)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') {
      final newName = await showMiniTextDialog(
        context,
        title: 'Rename folder',
        accent: Colors.white,
        initialValue: name,
        confirmLabel: 'Save',
      );
      if (newName != null) await _repo.renameAlbum(id, newName);
    } else if (action == 'delete') {
      await _repo.deleteAlbum(id);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_unlocked) {
      return VaultLockScreen(
        security: _sec,
        onUnlocked: _onUnlocked,
        onCancel: () => Navigator.of(context).pop(),
      );
    }

    final folders = _repo.albums();
    final total = _repo.items().length;
    return MiniAppScaffold(
      title: 'Vault',
      actions: [
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined, color: Colors.white),
          onPressed: _openSettings,
        ),
      ],
      child: Theme(
        data: clockThemeOf(context),
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              children: [
                ClockCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: miniAppSurface2,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(Icons.lock_outline,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        total == 0
                            ? 'Your vault is empty'
                            : '$total item${total == 1 ? '' : 's'} secured',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.92,
                  ),
                  itemCount: folders.length,
                  itemBuilder: (context, index) {
                    final folder = folders[index];
                    final id = folder['id'].toString();
                    final name = folder['name']?.toString() ?? 'Folder';
                    final isAll = id == VaultRepository.allAlbumId;
                    final cover = _repo.coverItem(id);
                    final coverId = cover?['id']?.toString();
                    return _FolderCard(
                      name: name,
                      count: _repo.countIn(id),
                      icon:
                          isAll ? Icons.inbox_outlined : Icons.folder_outlined,
                      coverThumbnail: coverId == null ? null : _thumb(coverId),
                      coverKind: cover?['kind']?.toString(),
                      onTap: () => _openFolder(id, name),
                      onLongPress: isAll ? null : () => _folderMenu(id, name),
                    );
                  },
                ),
              ],
            ),
            Positioned(
              right: 20,
              bottom: 26,
              child: MiniActionFab(
                color: miniAppSurface2,
                actions: [
                  MiniFabAction(
                    icon: Icons.add_photo_alternate_outlined,
                    tooltip: 'Import files',
                    onTap: _import,
                  ),
                  MiniFabAction(
                    icon: Icons.create_new_folder_outlined,
                    tooltip: 'New folder',
                    onTap: _newFolder,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contents of one folder (or "All"), with bulk selection, move and delete.
class VaultFolderScreen extends StatefulWidget {
  final String albumId;
  final String albumName;

  const VaultFolderScreen({
    super.key,
    required this.albumId,
    required this.albumName,
  });

  @override
  State<VaultFolderScreen> createState() => _VaultFolderScreenState();
}

class _VaultFolderScreenState extends State<VaultFolderScreen>
    with WidgetsBindingObserver {
  final _repo = VaultRepository();
  final _sec = VaultSecurityRepository();
  final _selected = <String>{};
  // Memoised decrypted previews so toggling selection doesn't re-decrypt.
  final _thumbs = <String, Future<Uint8List?>>{};
  var _selecting = false;
  var _pendingImport = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<Uint8List?> _thumb(String id) =>
      _thumbs.putIfAbsent(id, () => LauncherService.vaultThumbnail(id));

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted || !_pendingImport) {
      return;
    }
    _pendingImport = false;
    _reconcile();
  }

  List<Map<String, Object?>> get _items => _repo.itemsIn(widget.albumId);

  Future<void> _reconcile() async {
    final added = await _repo.reconcileNativeImports(widget.albumId);
    if (!mounted) return;
    setState(() {});
    if (added > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Added $added item${added == 1 ? '' : 's'} to ${widget.albumName}'),
        ),
      );
    }
  }

  Future<void> _import() async {
    _pendingImport = true;
    await LauncherService.pickVaultFiles(
      deleteOriginals: _sec.removeOriginals,
    );
  }

  void _openViewer(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VaultViewerScreen(items: _items, initialIndex: index),
      ),
    );
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selecting = false;
      } else {
        _selected.add(id);
      }
    });
  }

  void _enterSelection(String id) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(id);
    });
  }

  void _clearSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _moveSelected() async {
    final folders = _repo
        .albums()
        .where((f) => f['id'] != widget.albumId)
        .toList(growable: false);
    final target = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: miniAppSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Move to',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ),
            for (final folder in folders)
              ListTile(
                leading: Icon(
                  folder['id'] == VaultRepository.allAlbumId
                      ? Icons.inbox_outlined
                      : Icons.folder_outlined,
                  color: Colors.white,
                ),
                title: Text(folder['name']?.toString() ?? 'Folder'),
                onTap: () => Navigator.pop(context, folder['id'].toString()),
              ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    await _repo.moveItems(_selected, target);
    _clearSelection();
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: clockThemeOf(context),
        child: AlertDialog(
          backgroundColor: miniAppSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('Delete files?',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: Text(
            'Permanently delete $count item${count == 1 ? '' : 's'} from the vault.',
            style: const TextStyle(color: miniAppMuted, height: 1.3),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:
                  const Text('Cancel', style: TextStyle(color: miniAppMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    await _repo.deleteItems(_selected);
    _clearSelection();
  }

  Future<void> _exportSelected() async {
    final id = _selected.first;
    await LauncherService.exportLockedFile(id);
    if (mounted) _clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: MiniAppScaffold(
        title: _selecting ? '${_selected.length} selected' : widget.albumName,
        actions: _selecting
            ? [
                IconButton(
                  tooltip: 'Move',
                  icon: const Icon(Icons.drive_file_move_outline,
                      color: Colors.white),
                  onPressed: _selected.isEmpty ? null : _moveSelected,
                ),
                if (_selected.length == 1)
                  IconButton(
                    tooltip: 'Export',
                    icon: const Icon(Icons.ios_share, color: Colors.white),
                    onPressed: _exportSelected,
                  ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  onPressed: _selected.isEmpty ? null : _deleteSelected,
                ),
                IconButton(
                  tooltip: 'Cancel',
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: _clearSelection,
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Import files',
                  icon: const Icon(Icons.add, color: Colors.white),
                  onPressed: _import,
                ),
              ],
        child: Theme(
          data: clockThemeOf(context),
          child: items.isEmpty
              ? _EmptyFolder(
                  isAll: widget.albumId == VaultRepository.allAlbumId)
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final id = item['id'].toString();
                    return _FileCard(
                      name: item['name']?.toString() ?? 'File',
                      kind: item['kind']?.toString() ?? 'file',
                      thumbnail: _thumb(id),
                      selecting: _selecting,
                      selected: _selected.contains(id),
                      onTap: () {
                        if (_selecting) {
                          _toggle(id);
                        } else {
                          _openViewer(index);
                        }
                      },
                      onLongPress: () => _enterSelection(id),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  final String name;
  final int count;
  final IconData icon;
  final Future<Uint8List?>? coverThumbnail;
  final String? coverKind;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _FolderCard({
    required this.name,
    required this.count,
    required this.icon,
    this.coverThumbnail,
    this.coverKind,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: miniAppSurface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _cover(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count item${count == 1 ? '' : 's'}',
                    style: const TextStyle(color: miniAppMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover() {
    final thumbnail = coverThumbnail;
    if (thumbnail == null) {
      return _folderIconPreview();
    }
    return FutureBuilder<Uint8List?>(
      future: thumbnail,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return _folderIconPreview();
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(bytes, fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black26, Colors.transparent],
                ),
              ),
            ),
            if (coverKind == 'video')
              const Center(
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white70,
                  size: 42,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _folderIconPreview() {
    return Container(
      color: miniAppSurface2,
      alignment: Alignment.center,
      child: Icon(icon, size: 44, color: Colors.white),
    );
  }
}

class _FileCard extends StatelessWidget {
  final String name;
  final String kind;
  final Future<Uint8List?> thumbnail;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FileCard({
    required this.name,
    required this.kind,
    required this.thumbnail,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: miniAppSurface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _preview()),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (selecting)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? Colors.white : Colors.black45,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 18, color: Colors.black)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    return FutureBuilder<Uint8List?>(
      future: thumbnail,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          return Container(
            color: miniAppSurface2,
            alignment: Alignment.center,
            child: Icon(_fileIcon(name), color: Colors.white, size: 46),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(bytes, fit: BoxFit.cover),
            if (kind == 'video')
              const Center(
                child: Icon(Icons.play_circle_fill,
                    color: Colors.white70, size: 40),
              ),
          ],
        );
      },
    );
  }
}

class _EmptyFolder extends StatelessWidget {
  final bool isAll;

  const _EmptyFolder({required this.isAll});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.enhanced_encryption_outlined,
                color: Colors.white, size: 56),
            const SizedBox(height: 18),
            const Text(
              'Nothing here yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              isAll
                  ? 'Tap + to import private files into your vault.'
                  : 'Tap + to import files into this folder.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: miniAppMuted, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

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
