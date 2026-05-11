import 'dart:math';
import 'package:isar_community/isar.dart';
import 'package:windyomi/eval/model/m_manga.dart';
import 'package:windyomi/eval/model/m_pages.dart';
import 'package:windyomi/main.dart';
import 'package:windyomi/models/manga.dart';
import 'package:windyomi/models/source.dart';
import 'package:windyomi/modules/more/settings/browse/providers/browse_state_provider.dart';
import 'package:windyomi/services/isolate_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'search.g.dart';

@riverpod
Future<MPages?> search(
  Ref ref, {
  required Source source,
  required String query,
  required int page,
  required List<dynamic> filterList,
}) async {
  if (source.name == "local" && source.lang == "") {
    final result =
        (await isar.mangas
                .filter()
                .itemTypeEqualTo(source.itemType)
                .group(
                  (q) => q
                      .sourceEqualTo("local")
                      .or()
                      .linkContains("Windyomi/local")
                      .or()
                      .linkContains("Windyomi\\local"),
                )
                .nameContains(query, caseSensitive: false)
                .offset(max(0, page - 1) * 50)
                .limit(50)
                .findAll())
            .map((e) => MManga(name: e.name))
            .toList();
    return MPages(list: result, hasNextPage: true);
  }
  return getIsolateService.get<MPages?>(
    query: query,
    filterList: filterList,
    source: source,
    page: page,
    serviceType: 'search',
    proxyServer: ref.read(androidProxyServerStateProvider),
  );
}
