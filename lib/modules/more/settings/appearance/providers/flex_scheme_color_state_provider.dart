import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:windyomi/main.dart';
import 'package:windyomi/models/settings.dart';
import 'package:windyomi/modules/more/settings/appearance/providers/theme_mode_state_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'flex_scheme_color_state_provider.g.dart';

@riverpod
class FlexSchemeColorState extends _$FlexSchemeColorState {
  @override
  FlexSchemeColor build() {
    final flexSchemeColorIndex = isar.settings
        .getSync(227)!
        .flexSchemeColorIndex!;
    return ref.read(themeModeStateProvider)
        ? ThemeAA.schemes[flexSchemeColorIndex].dark
        : ThemeAA.schemes[flexSchemeColorIndex].light;
  }

  void setTheme(FlexSchemeColor color, int index) {
    final settings = isar.settings.getSync(227);
    state = color;
    isar.writeTxnSync(
      () => isar.settings.putSync(
        settings!
          ..flexSchemeColorIndex = index
          ..updatedAt = DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class ThemeAA {
  static const List<FlexSchemeData> schemes = <FlexSchemeData>[
    FlexSchemeData(
      name: 'Windyomi',
      description: 'Dark purple Windyomi brand theme.',
      light: FlexSchemeColor(
        primary: Color(0xFF725FC6),
        primaryContainer: Color(0xFFE8DDFF),
        secondary: Color(0xFF5C4F84),
        secondaryContainer: Color(0xFFE7DEFF),
        tertiary: Color(0xFF006A7C),
        tertiaryContainer: Color(0xFFB3EBFF),
        appBarColor: Color(0xFF725FC6),
      ),
      dark: FlexSchemeColor(
        primary: Color(0xFFA99BFF),
        primaryContainer: Color(0xFF382A65),
        primaryLightRef: Color(0xFF725FC6),
        secondary: Color(0xFFCBC2FF),
        secondaryContainer: Color(0xFF312945),
        secondaryLightRef: Color(0xFF5C4F84),
        tertiary: Color(0xFF76D7F2),
        tertiaryContainer: Color(0xFF12313A),
        appBarColor: Color(0xFF0A0D16),
      ),
    ),
    ...FlexColor.schemesList,
  ];
}
