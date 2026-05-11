import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:windyomi/main.dart';
import 'package:windyomi/models/chapter.dart';
import 'package:windyomi/models/manga.dart';
import 'package:windyomi/models/video.dart';
import 'package:windyomi/services/torrent_server.dart';

class TorrentStreamScreen extends StatefulWidget {
  const TorrentStreamScreen({super.key});

  @override
  State<TorrentStreamScreen> createState() => _TorrentStreamScreenState();
}

class _TorrentStreamScreenState extends State<TorrentStreamScreen> {
  final _urlController = TextEditingController();
  final _torrentServer = MTorrentServer();

  var _videos = <Video>[];
  var _loading = false;
  String? _error;
  String? _resolvedUrl;
  String? _resolvedFilePath;
  String? _resolvedInfoHash;

  @override
  void dispose() {
    unawaited(_clearResolvedTorrent());
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Torrents')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _urlController,
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Magnet o URL .torrent',
                hintText:
                    'magnet:?xt=urn:btih:... o https://.../archivo.torrent',
                prefixIcon: Icon(Icons.link),
              ),
              onSubmitted: (_) => _loadFromUrl(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _loading ? null : _loadFromUrl,
                  icon: const Icon(Icons.playlist_play),
                  label: const Text('Cargar videos'),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _pickTorrentFile,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Archivo .torrent'),
                ),
              ],
            ),
            if (_loading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (_videos.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  const Icon(Icons.movie_outlined),
                  const SizedBox(width: 8),
                  Text(
                    'Videos encontrados',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._videos.map(
                (video) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.play_circle_outline),
                    title: Text(
                      _cleanVideoName(video.quality),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : () => _createEntry(play: true),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Anadir y reproducir'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _createEntry(play: false),
                icon: const Icon(Icons.library_add),
                label: const Text('Solo anadir a biblioteca'),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Usa solo torrents legales o contenido que tengas permiso de reproducir.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadFromUrl() async {
    final input = _urlController.text.trim();
    try {
      final url = _validateTorrentUrl(input);
      await _resolveTorrent(url: url);
    } catch (e) {
      _setError(_friendlyError(e));
    }
  }

  Future<void> _pickTorrentFile() async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['torrent'],
      );
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) return;
      await _resolveTorrent(filePath: path);
    } catch (e) {
      _setError(_friendlyError(e));
    }
  }

  Future<void> _resolveTorrent({String? url, String? filePath}) async {
    await _clearResolvedTorrent();
    setState(() {
      _loading = true;
      _error = null;
      _videos = [];
      _resolvedUrl = url;
      _resolvedFilePath = filePath;
      _resolvedInfoHash = null;
    });

    try {
      final (videos, infoHash) = await _torrentServer.getTorrentPlaylist(
        url,
        filePath,
      );
      if (!mounted) return;
      if (videos.isEmpty) {
        throw StateError('No se encontro ningun video reproducible.');
      }
      setState(() {
        _videos = videos;
        _resolvedInfoHash = infoHash;
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

  Future<void> _createEntry({required bool play}) async {
    if (_videos.isEmpty) {
      await _loadFromUrl();
      if (_videos.isEmpty) return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final title = _titleFromSource();
    final manga = Manga(
      favorite: true,
      source: 'torrent',
      author: '',
      itemType: ItemType.anime,
      genre: const [],
      imageUrl: '',
      lang: '',
      link: _resolvedUrl ?? _resolvedFilePath ?? '',
      name: title,
      dateAdded: now,
      lastUpdate: now,
      status: Status.unknown,
      description: '',
      isLocalArchive: true,
      artist: '',
      updatedAt: now,
      sourceId: null,
    );

    late Chapter chapter;
    await isar.writeTxn(() async {
      await isar.mangas.put(manga);
      chapter = Chapter(
        name: title,
        url: _resolvedUrl ?? '',
        archivePath: _resolvedFilePath ?? '',
        mangaId: manga.id,
        updatedAt: now,
      )..manga.value = manga;
      await isar.chapters.put(chapter);
      await chapter.manga.save();
    });

    await _clearResolvedTorrent();
    if (!mounted) return;

    if (play) {
      context.push('/animePlayerView', extra: chapter.id);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torrent anadido a la biblioteca')),
      );
    }
  }

  String _validateTorrentUrl(String value) {
    if (value.isEmpty) {
      throw const FormatException('Pega un magnet o una URL .torrent.');
    }
    if (value.startsWith('magnet:?')) return value;

    final uri = Uri.tryParse(value);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      throw const FormatException('La URL debe ser magnet, http o https.');
    }
    return uri.toString();
  }

  String _titleFromSource() {
    final filePath = _resolvedFilePath;
    if (filePath != null && filePath.isNotEmpty) {
      return p.basenameWithoutExtension(filePath);
    }

    final url = _resolvedUrl;
    if (url != null && url.startsWith('magnet:?')) {
      final displayName = Uri.tryParse(url)?.queryParameters['dn'];
      if (displayName != null && displayName.trim().isNotEmpty) {
        return displayName.trim();
      }
    }

    if (url != null) {
      final uri = Uri.tryParse(url);
      final lastSegment = uri?.pathSegments.isNotEmpty == true
          ? uri!.pathSegments.last
          : '';
      if (lastSegment.isNotEmpty) {
        return p.basenameWithoutExtension(Uri.decodeComponent(lastSegment));
      }
    }

    return _cleanVideoName(_videos.first.quality);
  }

  String _cleanVideoName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Video';
    final withoutQuery = trimmed.split('?').first;
    return p.basenameWithoutExtension(withoutQuery).isEmpty
        ? trimmed
        : p.basenameWithoutExtension(withoutQuery);
  }

  void _setError(String message) {
    setState(() {
      _error = message;
      _loading = false;
      _videos = [];
    });
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('SocketException')) {
      return 'No se pudo conectar con el torrent o tracker.';
    }
    if (message.contains('FormatException')) {
      return message.replaceFirst('FormatException: ', '');
    }
    if (message.contains('No se encontro')) {
      return message.replaceFirst('Bad state: ', '');
    }
    return 'No se pudo cargar el torrent. Revisa que tenga seeds y videos reproducibles.';
  }

  Future<void> _clearResolvedTorrent() async {
    final infoHash = _resolvedInfoHash;
    _resolvedInfoHash = null;
    if (infoHash == null || infoHash.isEmpty) return;
    await _torrentServer.removeTorrent(infoHash);
  }
}
