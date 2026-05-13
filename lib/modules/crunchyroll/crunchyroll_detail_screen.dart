import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:windyomi/services/crunchyroll/crunchyroll_catalog_client.dart';
import 'package:windyomi/utils/cached_network.dart';
import 'package:windyomi/utils/extensions/build_context_extensions.dart';

class CrunchyrollDetailScreen extends StatelessWidget {
  final CrunchyrollSeries series;

  const CrunchyrollDetailScreen({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Reproducir',
            onPressed: () => _openPlayer(context),
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(context)),
          SliverToBoxAdapter(child: _buildInfo(context)),
          SliverToBoxAdapter(child: _buildActions(context)),
          SliverToBoxAdapter(child: _buildDescription(context)),
          SliverToBoxAdapter(child: _buildEpisodeHeader(context)),
          SliverList.builder(
            itemCount: _episodeTileCount,
            itemBuilder: (context, index) {
              if (_isMoreTile(index)) {
                return _OpenFullListTile(onTap: () => _openPlayer(context));
              }
              return _CrunchyrollEpisodeTile(
                index: index + 1,
                series: series,
                onTap: () => _openPlayer(context, episodeNumber: index + 1),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 30)),
        ],
      ),
    );
  }

  int get _episodeCount => series.episodes ?? 1;

  int get _episodeTileCount {
    if (_episodeCount > 80) return 81;
    return _episodeCount.clamp(1, 80).toInt();
  }

  bool _isMoreTile(int index) => _episodeCount > 80 && index == 80;

  Widget _buildHeader(BuildContext context) {
    final banner = series.bannerImage.isNotEmpty
        ? series.bannerImage
        : series.coverImage;

    return SizedBox(
      height: 430,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (banner.isNotEmpty)
            cachedNetworkImage(
              imageUrl: banner,
              width: context.width(1),
              height: 430,
              fit: BoxFit.cover,
            ),
          Container(color: Colors.black.withValues(alpha: 0.55)),
          Positioned(
            left: 18,
            right: 18,
            bottom: 28,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Material(
                  borderRadius: BorderRadius.circular(5),
                  clipBehavior: Clip.antiAlias,
                  child: series.coverImage.isEmpty
                      ? Container(
                          width: 115,
                          height: 170,
                          color: context.primaryColor.withValues(alpha: 0.25),
                          child: const Icon(Icons.movie_outlined, size: 44),
                        )
                      : cachedNetworkImage(
                          imageUrl: series.coverImage,
                          width: 115,
                          height: 170,
                          fit: BoxFit.cover,
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          series.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (series.nativeTitle.isNotEmpty)
                          Text(
                            series.nativeTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo(BuildContext context) {
    final values = <String>[
      if (series.year != null) series.year.toString(),
      series.displayStatus,
      if (series.episodes != null) '${series.episodes} eps',
      if (series.duration != null) '${series.duration} min',
      if (series.score != null) '${series.score}%',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: values
            .map(
              (value) => Chip(
                visualDensity: VisualDensity.compact,
                label: Text(value),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _openPlayer(context),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Reproducir'),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            tooltip: 'Abrir en Crunchyroll',
            onPressed: () => _openPlayer(context),
            icon: const Icon(Icons.open_in_full),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (series.genres.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                series.genres.join(' - '),
                style: TextStyle(color: context.secondaryColor, fontSize: 12),
              ),
            ),
          Text(
            series.description.isEmpty
                ? 'Descripcion no disponible.'
                : series.description,
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          const Text(
            'Episodios',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            'Crunchyroll',
            style: TextStyle(color: context.secondaryColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _openPlayer(BuildContext context, {int? episodeNumber}) {
    context.push(
      '/crunchyrollPlayer',
      extra: {
        'url': series.watchUrl,
        'title': series.title,
        'episodeTitle': episodeNumber == null
            ? 'Crunchyroll'
            : 'Episodio $episodeNumber',
        'episodeNumber': episodeNumber,
        'episodeCount': _episodeCount,
      },
    );
  }
}

class _CrunchyrollEpisodeTile extends StatelessWidget {
  final int index;
  final CrunchyrollSeries series;
  final VoidCallback onTap;

  const _CrunchyrollEpisodeTile({
    required this.index,
    required this.series,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 15),
      minLeadingWidth: 0,
      horizontalTitleGap: 13,
      leading: Container(
        width: 2,
        height: 40,
        decoration: BoxDecoration(
          color: context.primaryColor,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      title: Row(
        children: [
          if (series.bannerImage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Material(
                borderRadius: BorderRadius.circular(5),
                clipBehavior: Clip.antiAlias,
                child: cachedNetworkImage(
                  imageUrl: series.bannerImage,
                  width: 72,
                  height: 42,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          Expanded(
            child: Text(
              'Episodio $index',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Text(
        [
          if (series.duration != null) '${series.duration} min',
          'reproductor oficial',
        ].join(' - '),
        style: const TextStyle(fontSize: 11),
      ),
      trailing: IconButton(
        tooltip: 'Reproducir',
        onPressed: onTap,
        icon: const Icon(Icons.play_arrow_rounded),
      ),
      onTap: onTap,
    );
  }
}

class _OpenFullListTile extends StatelessWidget {
  final VoidCallback onTap;

  const _OpenFullListTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 15),
      leading: Icon(Icons.format_list_bulleted, color: context.primaryColor),
      title: const Text('Ver lista completa en Crunchyroll'),
      subtitle: const Text(
        'La seleccion exacta del episodio se hace dentro del reproductor oficial.',
        style: TextStyle(fontSize: 11),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }
}
