import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:windyomi/main.dart';
import 'package:windyomi/models/chapter.dart';
import 'package:windyomi/models/manga.dart';
import 'package:windyomi/services/stremio/stremio_addon_client.dart';

class StremioAddonsScreen extends StatefulWidget {
  const StremioAddonsScreen({super.key});

  @override
  State<StremioAddonsScreen> createState() => _StremioAddonsScreenState();
}

class _StremioAddonsScreenState extends State<StremioAddonsScreen> {
  final _client = StremioAddonClient();
  final _store = StremioAddonStore();
  final _manifestController = TextEditingController();
  final _searchController = TextEditingController();

  var _addons = <StremioManifest>[];
  var _metas = <StremioMeta>[];
  StremioManifest? _selectedAddon;
  StremioCatalog? _selectedCatalog;
  var _extraValues = <String, String>{};
  var _lastSearch = '';
  var _hasMore = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedAddons());
  }

  @override
  void dispose() {
    _manifestController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Stremio Addons')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _manifestController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Manifest URL',
                hintText: 'https://.../manifest.json',
                prefixIcon: Icon(Icons.extension_outlined),
              ),
              onSubmitted: (_) => _addAddon(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _addAddon,
              icon: const Icon(Icons.add),
              label: const Text('Anadir addon'),
            ),
            if (_addons.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<StremioManifest>(
                key: ValueKey(_selectedAddon?.manifestUrl ?? 'addon-empty'),
                initialValue: _selectedAddon,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Addon',
                  prefixIcon: Icon(Icons.hub_outlined),
                ),
                items: _addons
                    .map(
                      (addon) => DropdownMenuItem(
                        value: addon,
                        child: Text(
                          addon.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _loading ? null : _selectAddon,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<StremioCatalog>(
                key: ValueKey(
                  '${_selectedAddon?.manifestUrl}:${_selectedCatalog?.id}:catalog',
                ),
                initialValue: _selectedCatalog,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Catalogo',
                  prefixIcon: Icon(Icons.view_list_outlined),
                ),
                items: (_selectedAddon?.catalogs ?? const [])
                    .map(
                      (catalog) => DropdownMenuItem(
                        value: catalog,
                        child: Text(
                          catalog.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _loading ? null : _selectCatalog,
              ),
              ...(_selectedCatalog?.selectableExtras ?? const []).map(
                (extra) => Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(
                      '${_selectedCatalog?.id}:${extra.name}:${_extraValues[extra.name]}',
                    ),
                    initialValue: _extraValues[extra.name],
                    isExpanded: true,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: extra.name,
                      prefixIcon: const Icon(Icons.category_outlined),
                    ),
                    items: extra.options
                        .map(
                          (option) => DropdownMenuItem(
                            value: option,
                            child: Text(
                              option,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _loading
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _extraValues = {
                                ..._extraValues,
                                extra.name: value,
                              };
                              _metas = [];
                              _hasMore = false;
                            });
                            unawaited(_loadCatalog());
                          },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                enabled: _selectedCatalog?.supportsSearch ?? false,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Buscar',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    onPressed:
                        _loading || !(_selectedCatalog?.supportsSearch ?? false)
                        ? null
                        : _search,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loading ? null : () => _loadCatalog(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Catalogo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading || _selectedAddon == null
                        ? null
                        : _removeSelectedAddon,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Quitar'),
                  ),
                ],
              ),
            ],
            if (_loading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            ..._metas.map((meta) => _MetaTile(meta: meta, onTap: _openMeta)),
            if (_hasMore) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _loadCatalog(append: true),
                icon: const Icon(Icons.expand_more),
                label: const Text('Cargar mas'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _loadSavedAddons() async {
    try {
      final urls = await _store.loadManifestUrls();
      final addons = <StremioManifest>[];
      for (final url in urls) {
        try {
          addons.add(await _client.fetchManifest(url));
        } catch (_) {}
      }
      if (!mounted) return;
      final firstCatalog = addons.firstOrNull?.catalogs.firstOrNull;
      setState(() {
        _addons = addons;
        _selectedAddon = addons.firstOrNull;
        _selectedCatalog = firstCatalog;
        _extraValues = _defaultExtraValues(firstCatalog);
        _loading = false;
      });
      await _loadCatalog();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _addAddon() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final manifest = await _client.fetchManifest(_manifestController.text);
      final urls = {
        ..._addons.map((e) => e.manifestUrl),
        manifest.manifestUrl,
      }.toList();
      await _store.saveManifestUrls(urls);
      if (!mounted) return;
      setState(() {
        _addons = [
          ..._addons.where((e) => e.manifestUrl != manifest.manifestUrl),
          manifest,
        ];
        _selectedAddon = manifest;
        _selectedCatalog = manifest.catalogs.firstOrNull;
        _extraValues = _defaultExtraValues(_selectedCatalog);
        _lastSearch = '';
        _hasMore = false;
        _manifestController.clear();
      });
      await _loadCatalog();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _removeSelectedAddon() async {
    final selected = _selectedAddon;
    if (selected == null) return;
    final addons = _addons
        .where((e) => e.manifestUrl != selected.manifestUrl)
        .toList();
    await _store.saveManifestUrls(addons.map((e) => e.manifestUrl).toList());
    if (!mounted) return;
    final firstCatalog = addons.firstOrNull?.catalogs.firstOrNull;
    setState(() {
      _addons = addons;
      _selectedAddon = addons.firstOrNull;
      _selectedCatalog = firstCatalog;
      _extraValues = _defaultExtraValues(firstCatalog);
      _metas = [];
      _hasMore = false;
    });
    await _loadCatalog();
  }

  void _selectAddon(StremioManifest? addon) {
    final catalog = addon?.catalogs.firstOrNull;
    setState(() {
      _selectedAddon = addon;
      _selectedCatalog = catalog;
      _extraValues = _defaultExtraValues(catalog);
      _lastSearch = '';
      _searchController.clear();
      _metas = [];
      _hasMore = false;
      _error = null;
    });
    unawaited(_loadCatalog());
  }

  void _selectCatalog(StremioCatalog? catalog) {
    setState(() {
      _selectedCatalog = catalog;
      _extraValues = _defaultExtraValues(catalog);
      _lastSearch = '';
      _searchController.clear();
      _metas = [];
      _hasMore = false;
      _error = null;
    });
    unawaited(_loadCatalog());
  }

  Future<void> _search() async {
    _lastSearch = _searchController.text.trim();
    await _loadCatalog(search: _lastSearch);
  }

  Future<void> _loadCatalog({String? search, bool append = false}) async {
    final addon = _selectedAddon;
    final catalog = _selectedCatalog;
    if (addon == null || catalog == null) {
      setState(() => _loading = false);
      return;
    }

    final trimmedSearch = (search ?? _lastSearch).trim();
    if (catalog.requiresSearch && trimmedSearch.isEmpty) {
      setState(() {
        _loading = false;
        _metas = [];
        _hasMore = false;
        _error = null;
      });
      return;
    }

    final extraArgs = Map<String, String>.from(_extraValues)
      ..removeWhere((_, value) => value.trim().isEmpty);
    if (catalog.requiredExtras.any((e) => (extraArgs[e.name] ?? '').isEmpty)) {
      setState(() {
        _loading = false;
        _metas = [];
        _hasMore = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final metas = await _client.fetchCatalog(
        addon,
        catalog,
        search: trimmedSearch.isEmpty ? null : trimmedSearch,
        skip: append ? _metas.length : null,
        extraArgs: extraArgs,
      );
      if (!mounted) return;
      setState(() {
        _metas = append ? [..._metas, ...metas] : metas;
        _hasMore = catalog.supportsSkip && metas.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _openMeta(StremioMeta meta) async {
    final addon = _selectedAddon;
    if (addon == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detailed = await _client.fetchMeta(addon, meta) ?? meta;
      if (!mounted) return;
      setState(() => _loading = false);

      if (detailed.videos.isEmpty) {
        await _openStreams(
          detailed,
          videoId: detailed.id,
          label: detailed.name,
        );
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            child: ListView(
              children: detailed.videos
                  .map(
                    (video) => ListTile(
                      leading: const Icon(Icons.play_circle_outline),
                      title: Text(video.label),
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(
                          _openStreams(
                            detailed,
                            videoId: video.id,
                            label: video.label,
                          ),
                        );
                      },
                    ),
                  )
                  .toList(),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _openStreams(
    StremioMeta meta, {
    required String videoId,
    required String label,
  }) async {
    final addon = _selectedAddon;
    if (addon == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final streams = await _client.fetchStreams(
        addon,
        type: meta.type,
        videoId: videoId,
      );
      if (!mounted) return;
      setState(() => _loading = false);

      if (streams.isEmpty) {
        setState(() => _error = 'No hay streams para esta entrada.');
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            child: ListView(
              children: streams
                  .map(
                    (stream) => ListTile(
                      leading: Icon(
                        stream.externalUrl != null
                            ? Icons.open_in_browser
                            : stream.isTorrent
                            ? Icons.hub_outlined
                            : Icons.play_arrow,
                      ),
                      title: Text(stream.displayName),
                      subtitle: stream.isTorrent
                          ? const Text('Torrent')
                          : stream.externalUrl != null
                          ? const Text('Externo')
                          : const Text('Directo'),
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(_playStream(meta, label, stream));
                      },
                    ),
                  )
                  .toList(),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _playStream(
    StremioMeta meta,
    String label,
    StremioStream stream,
  ) async {
    final externalUrl = stream.externalUrl;
    if (externalUrl != null && externalUrl.isNotEmpty) {
      await launchUrl(
        Uri.parse(externalUrl),
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final isTorrent = stream.isTorrent;
    final source = isTorrent ? 'torrent' : 'stremio-direct';
    final streamUrl = isTorrent
        ? stream.torrentUrl(displayName: meta.name)
        : stream.url ?? '';
    final chapterPayload = jsonEncode({
      'headers': stream.requestHeaders,
      'subtitles': stream.subtitles
          .map((e) => {'file': e.url, 'label': e.lang ?? 'Subtitles'})
          .toList(),
      'fileIdx': stream.fileIdx,
      'filename': stream.filename,
    });

    final manga = Manga(
      favorite: true,
      source: source,
      author: '',
      itemType: ItemType.anime,
      genre: meta.genres,
      imageUrl: meta.poster ?? '',
      lang: '',
      link: meta.id,
      name: meta.name,
      dateAdded: now,
      lastUpdate: now,
      status: Status.unknown,
      description: meta.description ?? '',
      isLocalArchive: isTorrent,
      artist: '',
      updatedAt: now,
      sourceId: null,
    );

    late Chapter chapter;
    await isar.writeTxn(() async {
      await isar.mangas.put(manga);
      chapter = Chapter(
        name: label,
        url: streamUrl,
        mangaId: manga.id,
        description: chapterPayload,
        thumbnailUrl: meta.poster,
        updatedAt: now,
      )..manga.value = manga;
      await isar.chapters.put(chapter);
      await chapter.manga.save();
    });

    if (!mounted) return;
    context.push('/animePlayerView', extra: chapter.id);
  }

  Map<String, String> _defaultExtraValues(StremioCatalog? catalog) {
    final values = <String, String>{};
    for (final extra in catalog?.selectableExtras ?? const <StremioExtra>[]) {
      final defaultValue = extra.defaultValue;
      if (defaultValue != null && extra.options.contains(defaultValue)) {
        values[extra.name] = defaultValue;
      } else if (extra.isRequired && extra.options.isNotEmpty) {
        values[extra.name] = extra.options.first;
      }
    }
    return values;
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('FormatException')) {
      return message.replaceFirst('FormatException: ', '');
    }
    if (message.contains('SocketException')) {
      return 'No se pudo conectar con el addon.';
    }
    return message.replaceFirst('Bad state: ', '');
  }
}

class _MetaTile extends StatelessWidget {
  final StremioMeta meta;
  final ValueChanged<StremioMeta> onTap;

  const _MetaTile({required this.meta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.all(8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 56,
            height: 84,
            child: meta.poster == null || meta.poster!.isEmpty
                ? const ColoredBox(
                    color: Colors.black12,
                    child: Icon(Icons.movie_outlined),
                  )
                : Image.network(
                    meta.poster!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Colors.black12,
                      child: Icon(Icons.movie_outlined),
                    ),
                  ),
          ),
        ),
        title: Text(meta.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            if (meta.releaseInfo != null) meta.releaseInfo,
            if (meta.imdbRating != null) 'IMDb ${meta.imdbRating}',
          ].whereType<String>().join('  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => onTap(meta),
      ),
    );
  }
}
