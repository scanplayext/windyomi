import 'package:windyomi/utils/platform_utils.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:windyomi/models/manga.dart';
import 'package:windyomi/models/settings.dart';
import 'package:windyomi/models/source.dart';
import 'package:windyomi/models/track.dart';
import 'package:windyomi/models/track_preference.dart';
import 'package:windyomi/models/track_search.dart';
import 'package:windyomi/modules/anime/anime_player_view.dart';
import 'package:windyomi/modules/browse/extension/edit_code.dart';
import 'package:windyomi/modules/browse/extension/extension_detail.dart';
import 'package:windyomi/modules/browse/extension/widgets/create_extension.dart';
import 'package:windyomi/modules/browse/sources/sources_filter_screen.dart';
import 'package:windyomi/modules/calendar/calendar_screen.dart';
import 'package:windyomi/modules/crunchyroll/crunchyroll_detail_screen.dart';
import 'package:windyomi/modules/crunchyroll/crunchyroll_home_screen.dart';
import 'package:windyomi/modules/crunchyroll/crunchyroll_player_screen.dart';
import 'package:windyomi/modules/manga/detail/widgets/migrate_screen.dart';
import 'package:windyomi/modules/mass_migration/mass_migration_source_selection_screen.dart';
import 'package:windyomi/modules/manga/detail/widgets/recommendation_screen.dart';
import 'package:windyomi/modules/manga/detail/widgets/watch_order_screen.dart';
import 'package:windyomi/modules/more/data_and_storage/create_backup.dart';
import 'package:windyomi/modules/more/data_and_storage/data_and_storage.dart';
import 'package:windyomi/modules/more/settings/appearance/custom_navigation_settings.dart';
import 'package:windyomi/modules/more/settings/browse/source_repositories.dart';
import 'package:windyomi/modules/more/settings/player/custom_button_screen.dart';
import 'package:windyomi/modules/more/settings/player/player_advanced_screen.dart';
import 'package:windyomi/modules/more/settings/player/player_audio_screen.dart';
import 'package:windyomi/modules/more/settings/player/player_decoder_screen.dart';
import 'package:windyomi/modules/more/settings/player/player_overview_screen.dart';
import 'package:windyomi/modules/more/settings/reader/providers/reader_state_provider.dart';
import 'package:windyomi/modules/more/statistics/statistics_screen.dart';
import 'package:windyomi/modules/novel/novel_reader_view.dart';
import 'package:windyomi/modules/tracker_library/tracker_library_screen.dart';
import 'package:windyomi/modules/updates/updates_screen.dart';
import 'package:windyomi/modules/more/categories/categories_screen.dart';
import 'package:windyomi/modules/more/settings/downloads/downloads_screen.dart';
import 'package:windyomi/modules/more/settings/player/player_screen.dart';
import 'package:windyomi/modules/more/settings/sync/sync.dart';
import 'package:windyomi/modules/more/settings/track/track.dart';
import 'package:windyomi/modules/more/settings/track/manage_trackers/manage_trackers.dart';
import 'package:windyomi/modules/more/settings/track/manage_trackers/tracking_detail.dart';
import 'package:windyomi/modules/webview/webview.dart';
import 'package:windyomi/modules/browse/browse_screen.dart';
import 'package:windyomi/modules/browse/extension/extension_lang.dart';
import 'package:windyomi/modules/browse/global_search/global_search_screen.dart';
import 'package:windyomi/modules/main_view/main_screen.dart';
import 'package:windyomi/modules/history/history_screen.dart';
import 'package:windyomi/modules/library/library_screen.dart';
import 'package:windyomi/modules/manga/detail/manga_detail_main.dart';
import 'package:windyomi/modules/manga/home/manga_home_screen.dart';
import 'package:windyomi/modules/manga/reader/reader_view.dart';
import 'package:windyomi/modules/more/about/about_screen.dart';
import 'package:windyomi/modules/more/download_queue/download_queue_screen.dart';
import 'package:windyomi/modules/more/more_screen.dart';
import 'package:windyomi/modules/more/settings/appearance/appearance_screen.dart';
import 'package:windyomi/modules/more/settings/browse/browse_screen.dart';
import 'package:windyomi/modules/more/settings/browse/extension_server_screen.dart';
import 'package:windyomi/modules/more/settings/general/general_screen.dart';
import 'package:windyomi/modules/more/settings/reader/reader_screen.dart';
import 'package:windyomi/modules/more/settings/settings_screen.dart';
import 'package:windyomi/modules/more/settings/security/security_screen.dart';
import 'package:windyomi/modules/stremio/stremio_addons_screen.dart';
import 'package:windyomi/modules/torrent/torrent_stream_screen.dart';
import 'package:windyomi/services/crunchyroll/crunchyroll_catalog_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter/cupertino.dart';
part 'router.g.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
@riverpod
GoRouter router(Ref ref) {
  final navigationOrder = ref.watch(navigationOrderStateProvider);
  final router = RouterNotifier(navigationOrder);
  final hiddenItems = ref.watch(hideItemsStateProvider);
  final initLocation = navigationOrder
      .where((e) => !hiddenItems.contains(e))
      .first;

  return GoRouter(
    observers: [BotToastNavigatorObserver()],
    initialLocation: initLocation,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: router,
    routes: router._routes,
    navigatorKey: navigatorKey,
    onException: (context, state, router) => router.go(initLocation),
  );
}

@riverpod
class RouterCurrentLocationState extends _$RouterCurrentLocationState {
  bool _didSubscribe = false;
  @override
  String? build() {
    ref.keepAlive();
    // Delay listener‐registration until after the first frame.
    if (!_didSubscribe) {
      _didSubscribe = true;
      // Schedule the registration to run after the first build/frame:
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _listener();
      });
    }
    return null;
  }

  void _listener() {
    final router = ref.read(routerProvider);
    router.routerDelegate.addListener(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final RouteMatchList matches =
            router.routerDelegate.currentConfiguration;
        final RouteMatch lastMatch = matches.last;
        final RouteMatchList matchList = lastMatch is ImperativeRouteMatch
            ? lastMatch.matches
            : matches;
        state = matchList.uri.toString();
      });
    });
  }

  void refresh() {
    _listener();
  }
}

class RouterNotifier extends ChangeNotifier {
  RouterNotifier(this.navigationOrder);

  final List<String> navigationOrder;

  List<RouteBase> get _routes => [
    ShellRoute(
      builder: (context, state, child) => MainScreen(child: child),
      routes: [
        _genericRoute<String?>(
          name: "MangaLibrary",
          builder: (id) =>
              LibraryScreen(itemType: ItemType.manga, presetInput: id),
          directionalTransition: true,
        ),
        _genericRoute<String?>(
          name: "AnimeLibrary",
          builder: (id) =>
              LibraryScreen(itemType: ItemType.anime, presetInput: id),
          directionalTransition: true,
        ),
        _genericRoute<String?>(
          name: "NovelLibrary",
          builder: (id) =>
              LibraryScreen(itemType: ItemType.novel, presetInput: id),
          directionalTransition: true,
        ),
        _genericRoute<String?>(
          name: "trackerLibrary",
          builder: (id) => TrackerLibraryScreen(presetInput: id),
          directionalTransition: true,
        ),
        _genericRoute(
          name: "history",
          child: const HistoryScreen(),
          directionalTransition: true,
        ),
        _genericRoute(
          name: "updates",
          child: const UpdatesScreen(),
          directionalTransition: true,
        ),
        _genericRoute(
          name: "browse",
          child: const BrowseScreen(),
          directionalTransition: true,
        ),
        _genericRoute(
          name: "crunchyroll",
          child: const CrunchyrollHomeScreen(),
          directionalTransition: true,
        ),
        _genericRoute(
          name: "more",
          child: const MoreScreen(),
          directionalTransition: true,
        ),
      ],
    ),
    _genericRoute<(Source?, bool)>(
      name: "mangaHome",
      builder: (id) => MangaHomeScreen(source: id.$1!, isLatest: id.$2),
    ),
    _genericRoute<int>(
      path: "/manga-reader/detail",
      builder: (id) => MangaReaderDetail(mangaId: id),
    ),
    _genericRoute<int>(
      name: "mangaReaderView",
      builder: (id) => MangaReaderView(chapterId: id),
    ),
    _genericRoute<int>(
      name: "animePlayerView",
      builder: (id) => AnimePlayerView(episodeId: id),
    ),
    _genericRoute<int>(
      name: "novelReaderView",
      builder: (id) => NovelReaderView(chapterId: id),
    ),
    _genericRoute<ItemType>(
      name: "ExtensionLang",
      builder: (itemType) => ExtensionsLang(itemType: itemType),
    ),
    _genericRoute(name: "settings", child: const SettingsScreen()),
    _genericRoute(name: "appearance", child: const AppearanceScreen()),
    _genericRoute<Source>(
      name: "extension_detail",
      builder: (source) => ExtensionDetail(source: source),
    ),
    _genericRoute<(String?, ItemType)>(
      name: "globalSearch",
      builder: (data) => GlobalSearchScreen(search: data.$1, itemType: data.$2),
    ),
    _genericRoute(name: "about", child: const AboutScreen()),
    _genericRoute(name: "track", child: const TrackScreen()),
    _genericRoute(name: "sync", child: const SyncScreen()),
    _genericRoute<ItemType>(
      name: "sourceFilter",
      builder: (itemType) => SourcesFilterScreen(itemType: itemType),
    ),
    _genericRoute(name: "downloadQueue", child: const DownloadQueueScreen()),
    _genericRoute<Map<String, dynamic>>(
      name: "mangawebview",
      builder: (data) => MangaWebView(url: data["url"]!, title: data['title']!),
    ),
    _genericRoute<(bool, int)>(
      name: "categories",
      builder: (data) => CategoriesScreen(data: data),
    ),
    _genericRoute(name: "statistics", child: const StatisticsScreen()),
    _genericRoute(name: "general", child: const GeneralScreen()),
    _genericRoute(name: "readerMode", child: const ReaderScreen()),
    _genericRoute(name: "browseS", child: const BrowseSScreen()),
    _genericRoute(
      name: "extensionServer",
      child: const ExtensionServerScreen(),
    ),
    _genericRoute<ItemType>(
      name: "SourceRepositories",
      builder: (itemType) => SourceRepositories(itemType: itemType),
    ),
    _genericRoute(name: "downloads", child: const DownloadsScreen()),
    _genericRoute(name: "dataAndStorage", child: const DataAndStorage()),
    _genericRoute<CrunchyrollSeries>(
      name: "crunchyrollDetail",
      builder: (series) => CrunchyrollDetailScreen(series: series),
    ),
    _genericRoute<Map<String, dynamic>>(
      name: "crunchyrollPlayer",
      builder: (data) => CrunchyrollPlayerScreen(
        initialUrl: data["url"]?.toString(),
        title: data["title"]?.toString(),
        episodeTitle: data["episodeTitle"]?.toString(),
        episodeNumber: data["episodeNumber"] as int?,
        episodeCount: data["episodeCount"] as int?,
      ),
    ),
    _genericRoute(name: "stremioAddons", child: const StremioAddonsScreen()),
    _genericRoute(name: "torrentStream", child: const TorrentStreamScreen()),
    _genericRoute(name: "security", child: const SecurityScreen()),
    _genericRoute(name: "manageTrackers", child: const ManageTrackersScreen()),
    _genericRoute<TrackPreference>(
      name: "trackingDetail",
      builder: (trackerPref) => TrackingDetail(trackerPref: trackerPref),
    ),
    _genericRoute(name: "playerOverview", child: const PlayerOverviewScreen()),
    _genericRoute(name: "playerMode", child: const PlayerScreen()),
    _genericRoute<int>(
      name: "codeEditor",
      builder: (sourceId) => CodeEditorPage(sourceId: sourceId),
    ),
    _genericRoute(name: "createExtension", child: const CreateExtension()),
    _genericRoute(name: "createBackup", child: const CreateBackup()),
    _genericRoute(
      name: "customNavigationSettings",
      child: const CustomNavigationSettings(),
    ),
    _genericRoute(
      name: "customButtonScreen",
      child: const CustomButtonScreen(),
    ),
    _genericRoute(
      name: "playerDecoderScreen",
      child: const PlayerDecoderScreen(),
    ),
    _genericRoute(name: "playerAudioScreen", child: const PlayerAudioScreen()),
    _genericRoute(
      name: "playerAdvancedScreen",
      child: const PlayerAdvancedScreen(),
    ),
    _genericRoute<ItemType?>(
      name: "calendarScreen",
      builder: (itemType) => CalendarScreen(itemType: itemType),
    ),
    _genericRoute<Manga>(
      name: "migrate",
      builder: (manga) => MigrationScreen(manga: manga),
    ),
    _genericRoute<Manga>(
      name: "massMigration",
      builder: (manga) =>
          MassMigrationSourceSelectionScreen(initialManga: manga),
    ),
    _genericRoute<(Manga, TrackSearch)>(
      name: "migrate/tracker",
      builder: (data) => MigrationScreen(manga: data.$1, trackSearch: data.$2),
    ),
    _genericRoute<(String, ItemType, AlgorithmWeights)>(
      name: "recommendations",
      builder: (data) => RecommendationScreen(
        name: data.$1,
        itemType: data.$2,
        algorithmWeights: data.$3,
      ),
    ),
    _genericRoute<(String, Track?)>(
      name: "watchOrder",
      builder: (data) => WatchOrderScreen(name: data.$1, track: data.$2),
    ),
  ];

  GoRoute _genericRoute<T>({
    String? name,
    String? path,
    Widget Function(T extra)? builder,
    Widget? child,
    bool directionalTransition = false,
  }) {
    final routePath = path ?? (name != null ? "/$name" : "/");
    return GoRoute(
      path: routePath,
      name: name,
      builder: (context, state) {
        if (builder != null) {
          final id = state.extra as T;
          return builder(id);
        } else {
          return child!;
        }
      },
      pageBuilder: isApple
          ? (context, state) {
              final pageChild = builder != null
                  ? builder(state.extra as T)
                  : child!;
              if (directionalTransition) {
                return directionalTransitionPage(
                  key: state.pageKey,
                  child: pageChild,
                  location: routePath,
                  navigationOrder: navigationOrder,
                );
              }
              return transitionPage(key: state.pageKey, child: pageChild);
            }
          : null,
    );
  }
}

Page transitionPage({required LocalKey key, required child}) {
  return CupertinoPage(key: key, child: child);
}

int? _lastDirectionalTransitionIndex;

Page directionalTransitionPage({
  required LocalKey key,
  required Widget child,
  required String location,
  required List<String> navigationOrder,
}) {
  final currentIndex = navigationOrder.indexOf(location);
  final previousIndex = _lastDirectionalTransitionIndex;
  final beginX = previousIndex == null || currentIndex == previousIndex
      ? 0.0
      : currentIndex > previousIndex
      ? 1.0
      : -1.0;

  if (currentIndex != -1) {
    _lastDirectionalTransitionIndex = currentIndex;
  }

  return CustomTransitionPage(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (beginX == 0) return child;

      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return SlideTransition(
        position: Tween<Offset>(
          begin: Offset(beginX, 0),
          end: Offset.zero,
        ).animate(curvedAnimation),
        child: child,
      );
    },
  );
}

Route createRoute({required Widget page}) {
  return isApple
      ? CupertinoPageRoute(builder: (context) => page)
      : MaterialPageRoute(builder: (context) => page);
}
