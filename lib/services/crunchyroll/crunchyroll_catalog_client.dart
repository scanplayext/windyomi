import 'dart:convert';

import 'package:http/http.dart' as http;

class CrunchyrollCatalogClient {
  static final _endpoint = Uri.parse('https://graphql.anilist.co');

  Future<CrunchyrollCatalogPage> popular({int page = 1}) {
    return _fetch(sort: const ['POPULARITY_DESC'], page: page);
  }

  Future<CrunchyrollCatalogPage> latest({int page = 1}) {
    return _fetch(sort: const ['START_DATE_DESC'], page: page);
  }

  Future<CrunchyrollCatalogPage> search(String query, {int page = 1}) {
    return _fetch(
      sort: const ['SEARCH_MATCH', 'POPULARITY_DESC'],
      search: query,
      page: page,
    );
  }

  Future<CrunchyrollCatalogPage> _fetch({
    required List<String> sort,
    String? search,
    int page = 1,
  }) async {
    final items = <CrunchyrollSeries>[];
    var currentPage = page;
    var hasNextPage = true;

    while (items.length < 24 && hasNextPage && currentPage < page + 4) {
      final result = await _requestPage(
        page: currentPage,
        perPage: 30,
        sort: sort,
        search: search,
      );

      items.addAll(
        result.items.where((series) => series.crunchyrollUrl.isNotEmpty),
      );
      hasNextPage = result.hasNextPage;
      currentPage++;
    }

    return CrunchyrollCatalogPage(
      items: items,
      hasNextPage: hasNextPage,
      nextPage: currentPage,
    );
  }

  Future<CrunchyrollCatalogPage> _requestPage({
    required int page,
    required int perPage,
    required List<String> sort,
    String? search,
  }) async {
    final response = await http.post(
      _endpoint,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'query': _catalogQuery,
        'variables': {
          'page': page,
          'perPage': perPage,
          'sort': sort,
          'search': search?.trim().isEmpty ?? true ? null : search!.trim(),
        },
      }),
    );

    if (response.statusCode == 429) {
      throw StateError(
        'AniList esta limitando las peticiones. Prueba otra vez en unos segundos.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'No se pudo cargar el catalogo (${response.statusCode}).',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final pageData = json['data']?['Page'] as Map<String, dynamic>?;
    if (pageData == null) {
      throw const FormatException('La respuesta del catalogo no es valida.');
    }

    final pageInfo = pageData['pageInfo'] as Map<String, dynamic>? ?? const {};
    final media = pageData['media'] as List? ?? const [];

    return CrunchyrollCatalogPage(
      items: media
          .whereType<Map>()
          .map((item) => CrunchyrollSeries.fromJson(item))
          .toList(),
      hasNextPage: pageInfo['hasNextPage'] == true,
      nextPage: page + 1,
    );
  }
}

class CrunchyrollCatalogPage {
  final List<CrunchyrollSeries> items;
  final bool hasNextPage;
  final int nextPage;

  const CrunchyrollCatalogPage({
    required this.items,
    required this.hasNextPage,
    required this.nextPage,
  });
}

class CrunchyrollSeries {
  final int id;
  final String title;
  final String nativeTitle;
  final String description;
  final String coverImage;
  final String bannerImage;
  final String color;
  final List<String> genres;
  final int? episodes;
  final int? duration;
  final int? score;
  final int? year;
  final String status;
  final String crunchyrollUrl;
  final int? nextAiringEpisode;

  const CrunchyrollSeries({
    required this.id,
    required this.title,
    required this.nativeTitle,
    required this.description,
    required this.coverImage,
    required this.bannerImage,
    required this.color,
    required this.genres,
    required this.episodes,
    required this.duration,
    required this.score,
    required this.year,
    required this.status,
    required this.crunchyrollUrl,
    required this.nextAiringEpisode,
  });

  factory CrunchyrollSeries.fromJson(Map<dynamic, dynamic> json) {
    final title = json['title'] as Map? ?? const {};
    final cover = json['coverImage'] as Map? ?? const {};
    final startDate = json['startDate'] as Map? ?? const {};
    final nextAiring = json['nextAiringEpisode'] as Map?;
    final links = json['externalLinks'] as List? ?? const [];
    final crunchyrollUrl = links
        .whereType<Map>()
        .map((link) => link['url']?.toString() ?? '')
        .firstWhere(
          (url) => url.toLowerCase().contains('crunchyroll.com'),
          orElse: () => '',
        );

    return CrunchyrollSeries(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: title['english']?.toString().trim().isNotEmpty == true
          ? title['english'].toString()
          : title['romaji']?.toString() ?? 'Sin titulo',
      nativeTitle: title['native']?.toString() ?? '',
      description: _stripMarkup(json['description']?.toString() ?? ''),
      coverImage:
          cover['extraLarge']?.toString() ?? cover['large']?.toString() ?? '',
      bannerImage: json['bannerImage']?.toString() ?? '',
      color: cover['color']?.toString() ?? '',
      genres: (json['genres'] as List? ?? const [])
          .map((genre) => genre.toString())
          .toList(),
      episodes: (json['episodes'] as num?)?.toInt(),
      duration: (json['duration'] as num?)?.toInt(),
      score: (json['averageScore'] as num?)?.toInt(),
      year: (startDate['year'] as num?)?.toInt(),
      status: json['status']?.toString() ?? '',
      crunchyrollUrl: crunchyrollUrl.replaceFirst('http://', 'https://'),
      nextAiringEpisode: (nextAiring?['episode'] as num?)?.toInt(),
    );
  }

  String get displayStatus {
    return switch (status) {
      'RELEASING' => 'En emision',
      'FINISHED' => 'Finalizado',
      'NOT_YET_RELEASED' => 'Proximamente',
      'CANCELLED' => 'Cancelado',
      'HIATUS' => 'En pausa',
      _ => 'Desconocido',
    };
  }

  String get watchUrl {
    if (crunchyrollUrl.isNotEmpty) return crunchyrollUrl;
    return Uri.https('www.crunchyroll.com', '/search', {'q': title}).toString();
  }
}

String _stripMarkup(String value) {
  return value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&amp;', '&')
      .trim();
}

const _catalogQuery = r'''
query ($page: Int, $perPage: Int, $sort: [MediaSort], $search: String) {
  Page(page: $page, perPage: $perPage) {
    pageInfo {
      hasNextPage
    }
    media(type: ANIME, isAdult: false, sort: $sort, search: $search) {
      id
      title {
        romaji
        english
        native
      }
      description(asHtml: false)
      coverImage {
        extraLarge
        large
        color
      }
      bannerImage
      genres
      episodes
      duration
      averageScore
      status
      startDate {
        year
      }
      nextAiringEpisode {
        episode
      }
      externalLinks {
        site
        url
      }
    }
  }
}
''';
