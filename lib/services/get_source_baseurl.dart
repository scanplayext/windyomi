import 'package:windyomi/eval/lib.dart';
import 'package:windyomi/models/source.dart';
import 'package:windyomi/modules/more/settings/browse/providers/browse_state_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'get_source_baseurl.g.dart';

@riverpod
String sourceBaseUrl(Ref ref, {required Source source}) {
  final service = getExtensionService(
    source,
    ref.read(androidProxyServerStateProvider),
  );
  try {
    return service.sourceBaseUrl;
  } finally {
    service.dispose();
  }
}
