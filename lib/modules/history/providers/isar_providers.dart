import 'package:isar_community/isar.dart';
import 'package:windyomi/main.dart';
import 'package:windyomi/models/chapter.dart';
import 'package:windyomi/models/update.dart';
import 'package:windyomi/models/history.dart';
import 'package:windyomi/models/manga.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'isar_providers.g.dart';

@riverpod
Stream<List<History>> getAllHistoryStream(
  Ref ref, {
  required ItemType itemType,
  String search = "",
}) async* {
  yield* isar.historys
      .filter()
      .idIsNotNull()
      .and()
      .chapter((q) => q.manga((q) => q.itemTypeEqualTo(itemType)))
      .and()
      .chapter(
        (q) => q.manga((q) => q.nameContains(search, caseSensitive: false)),
      )
      .watch(fireImmediately: true);
}

@riverpod
Stream<List<Update>> getAllUpdateStream(
  Ref ref, {
  required ItemType itemType,
  String search = "",
}) async* {
  yield* isar.updates
      .filter()
      .idIsNotNull()
      .and()
      .chapter((q) => q.manga((q) => q.itemTypeEqualTo(itemType)))
      .and()
      .chapter(
        (q) => q.manga((q) => q.nameContains(search, caseSensitive: false)),
      )
      .watch(fireImmediately: true);
}
