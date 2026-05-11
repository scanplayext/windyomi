import 'package:windyomi/eval/lib.dart';
import 'package:windyomi/eval/model/source_preference.dart';
import 'package:windyomi/models/source.dart';

List<SourcePreference> getSourcePreference({required Source source}) {
  final service = getExtensionService(source, "");
  try {
    return service.getSourcePreferences();
  } finally {
    service.dispose();
  }
}
