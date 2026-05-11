import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:windyomi/models/chapter.dart';
import 'package:windyomi/models/video.dart';
import 'package:windyomi/modules/more/settings/browse/providers/browse_state_provider.dart';
import 'package:windyomi/providers/storage_provider.dart';
import 'package:windyomi/services/isolate_service.dart';
import 'package:windyomi/services/torrent_server.dart';
import 'package:windyomi/utils/utils.dart';
import 'package:windyomi/utils/extensions/string_extensions.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:path/path.dart' as p;

import '../models/source.dart';
part 'get_video_list.g.dart';

@riverpod
Future<(List<Video>, bool, List<String>, Directory?)> getVideoList(
  Ref ref, {
  required Chapter episode,
}) async {
  (List<Video>, bool, List<String>, Directory?) result;
  final keepAlive = ref.keepAlive();
  try {
    final storageProvider = StorageProvider();
    final mpvDirectory = await storageProvider.getMpvDirectory();
    List<String> infoHashes = [];
    final episodePayload = _decodeEpisodePayload(episode.description);
    if (episode.manga.value!.source == "stremio-direct") {
      final url = episode.url ?? "";
      if (url.isEmpty) {
        throw StateError("El stream directo no contiene URL.");
      }
      final headers = _decodeHeaders(episodePayload["headers"]);
      final subtitles = _decodeTracks(episodePayload["subtitles"]);
      final title = episode.name ?? episode.manga.value!.name ?? "Stream";
      keepAlive.close();
      return (
        [Video(url, title, url, headers: headers, subtitles: subtitles)],
        false,
        infoHashes,
        mpvDirectory,
      );
    }
    final mangaDirectory = await storageProvider.getMangaMainDirectory(episode);
    final isLocalArchive =
        episode.manga.value!.isLocalArchive! &&
        episode.manga.value!.source != "torrent";
    final mp4animePath = p.join(
      mangaDirectory!.path,
      "${episode.name!.replaceForbiddenCharacters(' ')}.mp4",
    );
    if (await File(mp4animePath).exists() || isLocalArchive) {
      final animeDir =
          episode.archivePath != null && episode.manga.value?.source == "local"
          ? Directory(p.dirname(episode.archivePath!))
          : null;
      final chapterDirectory = (await storageProvider.getMangaChapterDirectory(
        episode,
        mangaMainDirectory: animeDir ?? mangaDirectory,
      ))!;
      final path = isLocalArchive ? episode.archivePath : mp4animePath;
      final subtitlesDir = Directory(
        p.join('${chapterDirectory.path}_subtitles'),
      );
      List<Track> subtitles = [];
      if (subtitlesDir.existsSync()) {
        for (var element in subtitlesDir.listSync()) {
          if (element is File) {
            final subtitle = Track(
              label: element.uri.pathSegments.last.replaceAll('.srt', ''),
              file: element.uri.toString(),
            );
            subtitles.add(subtitle);
          }
        }
      }
      keepAlive.close();
      return (
        [Video(path!, episode.name!, path, subtitles: subtitles)],
        true,
        infoHashes,
        mpvDirectory,
      );
    }
    final source = getSource(
      episode.manga.value!.lang!,
      episode.manga.value!.source!,
      episode.manga.value!.sourceId,
    );
    final proxyServer = ref.read(androidProxyServerStateProvider);

    final isMihonTorrent =
        source?.sourceCodeLanguage == SourceCodeLanguage.mihon &&
        source!.name!.contains("(Torrent");
    if ((source?.isTorrent ?? false) ||
        episode.manga.value!.source == "torrent" ||
        isMihonTorrent) {
      List<Video> list = [];

      List<Video> torrentList = [];
      if (episode.archivePath?.isNotEmpty ?? false) {
        final (videos, infohash) = await MTorrentServer().getTorrentPlaylist(
          episode.url,
          episode.archivePath,
        );
        keepAlive.close();
        return (videos, false, [infohash ?? ""], mpvDirectory);
      }

      try {
        list = await getIsolateService.get<List<Video>>(
          url: episode.url!,
          source: source,
          serviceType: 'getVideoList',
          proxyServer: proxyServer,
        );
      } catch (e) {
        list = [Video(episode.url!, episode.name!, episode.url!)];
      }

      for (var v in list) {
        final (videos, infohash) = await MTorrentServer().getTorrentPlaylist(
          v.url,
          episode.archivePath,
        );
        for (var video in _filterTorrentVideos(videos, episodePayload)) {
          torrentList.add(
            video..quality = video.quality.substringBeforeLast("."),
          );
          if (infohash != null) {
            infoHashes.add(infohash);
          }
        }
      }
      keepAlive.close();
      return (torrentList, false, infoHashes, mpvDirectory);
    }

    List<Video> list = await getIsolateService.get<List<Video>>(
      url: episode.url!,
      source: source,
      serviceType: 'getVideoList',
      proxyServer: proxyServer,
    );
    List<Video> videos = [];

    for (var video in list) {
      if (!videos.any((element) => element.quality == video.quality)) {
        videos.add(video);
      }
    }

    result = (videos, false, infoHashes, mpvDirectory);

    keepAlive.close();
    return result;
  } catch (e) {
    keepAlive.close();
    rethrow;
  }
}

Map<String, dynamic> _decodeEpisodePayload(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const {};
  try {
    final json = jsonDecode(raw);
    if (json is Map) return Map<String, dynamic>.from(json);
  } catch (_) {}
  return const {};
}

Map<String, String>? _decodeHeaders(dynamic raw) {
  if (raw is! Map) return null;
  final headers = raw.map((key, value) => MapEntry('$key', '$value'));
  return headers.isEmpty ? null : headers;
}

List<Track> _decodeTracks(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map(
        (e) =>
            Track(file: e["file"]?.toString(), label: e["label"]?.toString()),
      )
      .where((e) => e.file?.isNotEmpty ?? false)
      .toList();
}

List<Video> _filterTorrentVideos(
  List<Video> videos,
  Map<String, dynamic> payload,
) {
  final filename = payload["filename"]?.toString().trim();
  if (filename != null && filename.isNotEmpty) {
    final match = videos.where((e) => e.quality == filename).toList();
    if (match.isNotEmpty) return match;
  }

  final fileIdx = payload["fileIdx"];
  final index = fileIdx is int
      ? fileIdx
      : int.tryParse(fileIdx?.toString() ?? "");
  if (index != null && index >= 0 && index < videos.length) {
    return [videos[index]];
  }

  return videos;
}
