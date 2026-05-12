import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:windyomi/modules/library/widgets/search_text_form_field.dart';
import 'package:windyomi/modules/manga/home/widget/mangas_card_selector.dart';
import 'package:windyomi/modules/widgets/bottom_text_widget.dart';
import 'package:windyomi/modules/widgets/cover_view_widget.dart';
import 'package:windyomi/modules/widgets/gridview_widget.dart';
import 'package:windyomi/modules/widgets/progress_center.dart';
import 'package:windyomi/services/crunchyroll/crunchyroll_catalog_client.dart';
import 'package:windyomi/utils/cached_network.dart';
import 'package:windyomi/utils/extensions/build_context_extensions.dart';

class CrunchyrollHomeScreen extends StatefulWidget {
  const CrunchyrollHomeScreen({super.key});

  @override
  State<CrunchyrollHomeScreen> createState() => _CrunchyrollHomeScreenState();
}

class _CrunchyrollHomeScreenState extends State<CrunchyrollHomeScreen> {
  final _client = CrunchyrollCatalogClient();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _items = <CrunchyrollSeries>[];

  var _selectedIndex = 0;
  var _nextPage = 1;
  var _hasNextPage = true;
  var _isFirstLoading = true;
  var _isLoadingMore = false;
  var _isSearch = false;
  var _query = '';
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFirstPage() async {
    if (!mounted) return;
    setState(() {
      _items.clear();
      _nextPage = 1;
      _hasNextPage = true;
      _isFirstLoading = true;
      _isLoadingMore = false;
      _error = null;
    });

    try {
      final page = await _fetchPage(1);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _nextPage = page.nextPage;
        _hasNextPage = page.hasNextPage;
        _isFirstLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isFirstLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasNextPage) return;
    setState(() {
      _isLoadingMore = true;
    });

    try {
      final page = await _fetchPage(_nextPage);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _nextPage = page.nextPage;
        _hasNextPage = page.hasNextPage;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoadingMore = false;
      });
    }
  }

  Future<CrunchyrollCatalogPage> _fetchPage(int page) {
    if (_isSearch && _query.isNotEmpty) {
      return _client.search(_query, page: page);
    }
    if (_selectedIndex == 1) {
      return _client.latest(page: page);
    }
    return _client.popular(page: page);
  }

  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
      _isSearch = false;
      _query = '';
      _searchController.clear();
    });
    _loadFirstPage();
  }

  void _submitSearch(String value) {
    setState(() {
      _selectedIndex = 2;
      _isSearch = value.trim().isNotEmpty;
      _query = value.trim();
    });
    _loadFirstPage();
  }

  List<_CrunchyrollTypeSelector> get _types => const [
    _CrunchyrollTypeSelector(Icons.favorite, 'Popular'),
    _CrunchyrollTypeSelector(Icons.new_releases_outlined, 'Ultimos'),
    _CrunchyrollTypeSelector(Icons.search, 'Buscar'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _selectedIndex == 2 ? null : const Text('Crunchyroll'),
        leading: _selectedIndex == 2 ? Container() : null,
        actions: [
          if (_selectedIndex == 2)
            SeachFormTextField(
              controller: _searchController,
              onChanged: (_) {},
              onPressed: () {
                _selectTab(0);
              },
              onSuffixPressed: () {
                _searchController.clear();
                setState(() {
                  _isSearch = false;
                  _query = '';
                });
              },
              onFieldSubmitted: _submitSearch,
            )
          else
            IconButton(
              tooltip: 'Buscar',
              onPressed: () {
                setState(() {
                  _selectedIndex = 2;
                  _isSearch = false;
                });
              },
              icon: const Icon(Icons.search),
            ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loadFirstPage,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(AppBar().preferredSize.height * 0.8),
          child: Column(
            children: [
              SizedBox(
                width: context.width(1),
                height: 45,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _types.length,
                  itemBuilder: (context, index) {
                    final item = _types[index];
                    return MangasCardSelector(
                      icon: item.icon,
                      selected: _selectedIndex == index,
                      text: item.title,
                      onPressed: () {
                        if (index == 2) {
                          setState(() {
                            _selectedIndex = 2;
                          });
                        } else {
                          _selectTab(index);
                        }
                      },
                    );
                  },
                ),
              ),
              Container(
                color: context.primaryColor,
                height: 0.3,
                width: context.width(1),
              ),
            ],
          ),
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isFirstLoading) {
      return const ProgressCenter();
    }
    if (_error != null && _items.isEmpty) {
      return _CrunchyrollError(error: _error!, onRetry: _loadFirstPage);
    }
    if (_selectedIndex == 2 && !_isSearch) {
      return const Center(
        child: Text('Busca un anime disponible en Crunchyroll.'),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No hay resultados de Crunchyroll.'));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GridViewWidget(
        controller: _scrollController,
        itemCount: _items.length + 1,
        childAspectRatio: 0.642,
        itemBuilder: (context, index) {
          if (index == _items.length) {
            if (!_hasNextPage) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.all(4),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                onPressed: _isLoadingMore ? null : _loadMore,
                child: _isLoadingMore
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Cargar mas', maxLines: 2),
                          Icon(Icons.arrow_forward_outlined),
                        ],
                      ),
              ),
            );
          }
          return _CrunchyrollSeriesCard(series: _items[index]);
        },
      ),
    );
  }
}

class _CrunchyrollSeriesCard extends StatelessWidget {
  final CrunchyrollSeries series;

  const _CrunchyrollSeriesCard({required this.series});

  @override
  Widget build(BuildContext context) {
    return CoverViewWidget(
      isComfortableGrid: true,
      image: series.coverImage.isEmpty
          ? null
          : coverProvider(series.coverImage),
      bottomTextWidget: BottomTextWidget(
        text: series.title,
        maxLines: 1,
        isComfortableGrid: true,
      ),
      onTap: () => context.push('/crunchyrollDetail', extra: series),
      children: [
        Positioned(
          top: 0,
          left: 0,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Container(
              decoration: BoxDecoration(
                color: context.primaryColor,
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.play_arrow_rounded, size: 16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CrunchyrollError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _CrunchyrollError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh)),
            const Text('Actualizar'),
            const SizedBox(height: 12),
            Text(error.toString(), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _CrunchyrollTypeSelector {
  final IconData icon;
  final String title;

  const _CrunchyrollTypeSelector(this.icon, this.title);
}
