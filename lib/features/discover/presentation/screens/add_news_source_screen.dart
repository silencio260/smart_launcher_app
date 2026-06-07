import 'package:flutter/material.dart';
import 'package:smart_launcher_app/features/discover/data/rss_source_store.dart';

/// Manage the Discover feed's RSS sources: add by URL, add a popular preset,
/// import an OPML document, or remove an existing source.
class AddNewsSourceScreen extends StatefulWidget {
  const AddNewsSourceScreen({super.key});

  @override
  State<AddNewsSourceScreen> createState() => _AddNewsSourceScreenState();
}

class _AddNewsSourceScreenState extends State<AddNewsSourceScreen> {
  final _store = RssSourceStore();
  final _urlController = TextEditingController();
  List<String> _sources = const [];

  @override
  void initState() {
    super.initState();
    _store.load().then((value) {
      if (mounted) setState(() => _sources = value);
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _add(String url) async {
    final updated = await _store.add(url);
    if (mounted) setState(() => _sources = updated);
  }

  Future<void> _remove(String url) async {
    final updated = await _store.remove(url);
    if (mounted) setState(() => _sources = updated);
  }

  Future<void> _importOpml() async {
    final controller = TextEditingController();
    final opml = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import OPML'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Paste OPML XML here…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Import')),
        ],
      ),
    );
    if (opml == null || opml.trim().isEmpty) return;
    final urls = RssSourceStore.parseOpml(opml);
    if (urls.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No feeds found in OPML')),
        );
      }
      return;
    }
    final updated = await _store.addAll(urls);
    if (mounted) {
      setState(() => _sources = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${urls.length} feeds')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add news source'),
        actions: [
          IconButton(
            tooltip: 'Import OPML',
            icon: const Icon(Icons.upload_file),
            onPressed: _importOpml,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: 'https://example.com/rss.xml',
                    labelText: 'Add RSS feed',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final url = _urlController.text.trim();
                  if (url.startsWith('http')) {
                    _add(url);
                    _urlController.clear();
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Popular', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in RssSourceStore.catalog)
                ActionChip(
                  avatar: Icon(
                    _sources.contains(p.url) ? Icons.check : Icons.add,
                    size: 18,
                  ),
                  label: Text(p.name),
                  onPressed:
                      _sources.contains(p.url) ? null : () => _add(p.url),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Your sources', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_sources.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No sources yet'),
            )
          else
            for (final url in _sources)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.rss_feed),
                title: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => _remove(url),
                ),
              ),
        ],
      ),
    );
  }
}
