import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:windyomi/services/http/m_client.dart';

class StremioAddonClient {
  final _http = MClient.init(reqcopyWith: {'useDartHttpClient': true});

  Future<StremioManifest> fetchManifest(String inputUrl) async {
    final url = normalizeManifestUrl(inputUrl);
    final res = await _http.get(Uri.parse(url));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('No se pudo leer el manifest (${res.statusCode}).');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return StremioManifest.fromJson(json, manifestUrl: url);
  }

  Future<List<StremioMeta>> fetchCatalog(
    StremioManifest manifest,
    StremioCatalog catalog, {
    String? search,
    int? skip,
    Map<String, String> extraArgs = const {},
  }) async {
    final extras = <String, String>{...extraArgs};
    final trimmedSearch = search?.trim();
    if (catalog.supportsSearch &&
        trimmedSearch != null &&
        trimmedSearch.isNotEmpty) {
      extras['search'] = trimmedSearch;
    }
    if (skip != null && skip > 0) {
      extras['skip'] = skip.toString();
    }

    if (catalog.requiredExtras.any((e) => (extras[e.name] ?? '').isEmpty)) {
      return const [];
    }

    final url = _resourceUrl(
      manifest,
      'catalog',
      catalog.type,
      catalog.id,
      extras,
    );
    final res = await _http.get(Uri.parse(url));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('No se pudo leer el catalogo (${res.statusCode}).');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final metas = (json['metas'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => StremioMeta.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return metas;
  }

  Future<StremioMeta?> fetchMeta(
    StremioManifest manifest,
    StremioMeta meta,
  ) async {
    if (!manifest.supportsResource('meta')) return null;
    final url = _resourceUrl(manifest, 'meta', meta.type, meta.id, const {});
    final res = await _http.get(Uri.parse(url));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final rawMeta = json['meta'];
    if (rawMeta is! Map) return null;
    return StremioMeta.fromJson(Map<String, dynamic>.from(rawMeta));
  }

  Future<List<StremioStream>> fetchStreams(
    StremioManifest manifest, {
    required String type,
    required String videoId,
  }) async {
    if (!manifest.supportsResource('stream')) return const [];
    final url = _resourceUrl(manifest, 'stream', type, videoId, const {});
    final res = await _http.get(Uri.parse(url));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('No se pudieron leer streams (${res.statusCode}).');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return (json['streams'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => StremioStream.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.isPlayable || e.externalUrl != null)
        .toList();
  }

  String normalizeManifestUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) {
      throw const FormatException('Pega una URL de manifest.');
    }

    if (value.startsWith('stremio://')) {
      value = Uri.decodeComponent(
        value.replaceFirst(RegExp(r'^stremio:/*'), ''),
      );
      if (!value.startsWith('http://') && !value.startsWith('https://')) {
        value = 'https://$value';
      }
    }

    final uri = Uri.tryParse(value);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      throw const FormatException('La URL debe ser http, https o stremio.');
    }

    if (value.endsWith('/')) return '${value}manifest.json';
    if (!value.endsWith('/manifest.json')) return '$value/manifest.json';
    return value;
  }

  String _resourceUrl(
    StremioManifest manifest,
    String resource,
    String type,
    String id,
    Map<String, String> extras,
  ) {
    final base = manifest.manifestUrl.replaceFirst(
      RegExp(r'/manifest\.json$'),
      '',
    );
    final parts = [
      base,
      resource,
      Uri.encodeComponent(type),
      Uri.encodeComponent(id),
    ];
    if (extras.isNotEmpty) {
      parts.add(
        extras.entries
            .map(
              (e) =>
                  '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
            )
            .join('&'),
      );
    }
    return '${parts.join('/')}.json';
  }
}

class StremioAddonStore {
  Future<List<String>> loadManifestUrls() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    final json = jsonDecode(await file.readAsString());
    if (json is! List) return const [];
    return json.whereType<String>().toList();
  }

  Future<void> saveManifestUrls(List<String> urls) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final normalized = urls.map((e) => e.trim()).where((e) => e.isNotEmpty);
    await file.writeAsString(jsonEncode(normalized.toSet().toList()));
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'stremio_addons.json'));
  }
}

class StremioManifest {
  final String manifestUrl;
  final String id;
  final String name;
  final String description;
  final String version;
  final List<String> resources;
  final List<String> types;
  final List<StremioCatalog> catalogs;
  final bool p2p;
  final bool adult;

  StremioManifest({
    required this.manifestUrl,
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.resources,
    required this.types,
    required this.catalogs,
    required this.p2p,
    required this.adult,
  });

  factory StremioManifest.fromJson(
    Map<String, dynamic> json, {
    required String manifestUrl,
  }) {
    return StremioManifest(
      manifestUrl: manifestUrl,
      id: json['id']?.toString() ?? manifestUrl,
      name: json['name']?.toString() ?? 'Stremio addon',
      description: json['description']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      resources: (json['resources'] as List? ?? const [])
          .map((e) => e is Map ? e['name']?.toString() : e.toString())
          .whereType<String>()
          .toSet()
          .toList(),
      types: (json['types'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      catalogs: (json['catalogs'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => StremioCatalog.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.type.isNotEmpty && e.id.isNotEmpty)
          .toList(),
      p2p: (json['behaviorHints'] as Map?)?['p2p'] == true,
      adult: (json['behaviorHints'] as Map?)?['adult'] == true,
    );
  }

  bool supportsResource(String resource) => resources.contains(resource);
}

class StremioCatalog {
  final String type;
  final String id;
  final String name;
  final List<StremioExtra> extra;

  StremioCatalog({
    required this.type,
    required this.id,
    required this.name,
    required this.extra,
  });

  factory StremioCatalog.fromJson(Map<String, dynamic> json) {
    return StremioCatalog(
      type: json['type']?.toString() ?? '',
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? json['id']?.toString() ?? 'Catalogo',
      extra: (json['extra'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => StremioExtra.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  bool get supportsSearch => extra.any((e) => e.name == 'search');
  bool get supportsSkip => extra.any((e) => e.name == 'skip');
  List<StremioExtra> get requiredExtras =>
      extra.where((e) => e.isRequired && e.name != 'search').toList();
  List<StremioExtra> get selectableExtras => extra
      .where(
        (e) => e.name != 'search' && e.name != 'skip' && e.options.isNotEmpty,
      )
      .toList();
  bool get requiresSearch =>
      extra.any((e) => e.isRequired && e.name == 'search');

  String get label => '$name ($type)';
}

class StremioExtra {
  final String name;
  final bool isRequired;
  final List<String> options;
  final String? defaultValue;

  StremioExtra({
    required this.name,
    required this.isRequired,
    required this.options,
    this.defaultValue,
  });

  factory StremioExtra.fromJson(Map<String, dynamic> json) {
    return StremioExtra(
      name: json['name']?.toString() ?? '',
      isRequired: json['isRequired'] == true,
      options: (json['options'] as List? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      defaultValue: json['default']?.toString(),
    );
  }
}

class StremioMeta {
  final String id;
  final String type;
  final String name;
  final String? poster;
  final String? description;
  final String? releaseInfo;
  final String? imdbRating;
  final List<String> genres;
  final List<StremioVideo> videos;

  StremioMeta({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.description,
    this.releaseInfo,
    this.imdbRating,
    required this.genres,
    required this.videos,
  });

  factory StremioMeta.fromJson(Map<String, dynamic> json) {
    return StremioMeta(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'movie',
      name: json['name']?.toString() ?? 'Sin titulo',
      poster: json['poster']?.toString(),
      description: json['description']?.toString(),
      releaseInfo: json['releaseInfo']?.toString(),
      imdbRating: json['imdbRating']?.toString(),
      genres: (json['genres'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      videos: (json['videos'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => StremioVideo.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList(),
    );
  }
}

class StremioVideo {
  final String id;
  final String title;
  final int? season;
  final int? episode;
  final String? thumbnail;

  StremioVideo({
    required this.id,
    required this.title,
    this.season,
    this.episode,
    this.thumbnail,
  });

  factory StremioVideo.fromJson(Map<String, dynamic> json) {
    return StremioVideo(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Episodio',
      season: _asInt(json['season']),
      episode: _asInt(json['episode']),
      thumbnail: json['thumbnail']?.toString(),
    );
  }

  String get label {
    if (season != null && episode != null) {
      return 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')} - $title';
    }
    return title;
  }
}

class StremioStream {
  final String? url;
  final String? externalUrl;
  final String? infoHash;
  final int? fileIdx;
  final String name;
  final String title;
  final String? filename;
  final List<String> sources;
  final Map<String, String>? requestHeaders;
  final List<StremioSubtitle> subtitles;

  StremioStream({
    this.url,
    this.externalUrl,
    this.infoHash,
    this.fileIdx,
    required this.name,
    required this.title,
    this.filename,
    required this.sources,
    this.requestHeaders,
    required this.subtitles,
  });

  factory StremioStream.fromJson(Map<String, dynamic> json) {
    final behaviorHints = json['behaviorHints'] as Map?;
    final proxyHeaders = behaviorHints?['proxyHeaders'] as Map?;
    final requestHeaders = proxyHeaders?['request'] as Map?;
    return StremioStream(
      url: json['url']?.toString(),
      externalUrl: json['externalUrl']?.toString(),
      infoHash: json['infoHash']?.toString(),
      fileIdx: _asInt(json['fileIdx']),
      name: json['name']?.toString() ?? '',
      title:
          json['title']?.toString() ??
          json['description']?.toString() ??
          json['filename']?.toString() ??
          '',
      filename:
          json['filename']?.toString() ??
          behaviorHints?['filename']?.toString(),
      sources: (json['sources'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      requestHeaders: requestHeaders?.map(
        (key, value) => MapEntry('$key', '$value'),
      ),
      subtitles: (json['subtitles'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => StremioSubtitle.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.url.isNotEmpty)
          .toList(),
    );
  }

  bool get isPlayable {
    final value = url;
    if (value != null &&
        (value.startsWith('http://') ||
            value.startsWith('https://') ||
            value.startsWith('magnet:?'))) {
      return true;
    }
    return infoHash != null && infoHash!.isNotEmpty;
  }

  bool get isTorrent {
    final value = (url ?? '').toLowerCase();
    return value.startsWith('magnet:?') ||
        value.endsWith('.torrent') ||
        (infoHash != null && infoHash!.isNotEmpty);
  }

  String get displayName {
    final parts = [
      name,
      title,
      filename,
    ].whereType<String>().where((e) => e.trim().isNotEmpty).toList();
    return parts.isEmpty ? 'Stream' : parts.join(' - ');
  }

  String torrentUrl({required String displayName}) {
    final directUrl = url;
    if (directUrl != null && directUrl.startsWith('magnet:?')) return directUrl;
    if (directUrl != null && directUrl.toLowerCase().endsWith('.torrent')) {
      return directUrl;
    }
    final hash = infoHash;
    if (hash == null || hash.isEmpty) {
      throw StateError('El stream no contiene infoHash.');
    }
    final trackers = sources
        .where((e) => e.startsWith('tracker:'))
        .map((e) => e.substring('tracker:'.length))
        .where((e) => e.isNotEmpty)
        .toList();
    return Uri(
      scheme: 'magnet',
      queryParameters: {
        'xt': hash.startsWith('urn:btih:') ? hash : 'urn:btih:$hash',
        'dn': filename ?? displayName,
        if (trackers.isNotEmpty) 'tr': trackers,
      },
    ).toString();
  }
}

class StremioSubtitle {
  final String url;
  final String? lang;

  StremioSubtitle({required this.url, this.lang});

  factory StremioSubtitle.fromJson(Map<String, dynamic> json) {
    return StremioSubtitle(
      url: json['url']?.toString() ?? '',
      lang: json['lang']?.toString(),
    );
  }
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
