import 'package:flutter/material.dart';

import '../../core/domain/biome_ids.dart';
import 'saga_biome_theme.dart';

/// Resolves [SagaBiomeTheme] from biome id.
abstract interface class SagaBiomeThemeResolver {
  SagaBiomeTheme resolve(String biomeId);
}

/// Built-in biome resolver with light/dark palettes.
class DefaultSagaBiomeThemeResolver implements SagaBiomeThemeResolver {
  final Brightness brightness;

  const DefaultSagaBiomeThemeResolver({this.brightness = Brightness.light});

  @override
  SagaBiomeTheme resolve(String biomeId) {
    final isLight = brightness == Brightness.light;
    switch (biomeId) {
      case kBiomeIdDesert:
        return isLight ? _desertLight : _desertDark;
      case kBiomeIdGlacier:
        return isLight ? _glacierLight : _glacierDark;
      case kBiomeIdForest:
      default:
        return isLight ? _forestLight : _forestDark;
    }
  }
}

const SagaBiomeTheme _forestLight = SagaBiomeTheme(
  backgroundColor: Color(0xFF2D5A27),
  pathFillColor: Color(0xFF1E3D1A),
  pathBorderColor: Color(0xFF0F2610),
  shadowColor: Color(0x40000000),
);
const SagaBiomeTheme _forestDark = SagaBiomeTheme(
  backgroundColor: Color(0xFF1E4020),
  pathFillColor: Color(0xFF2A5530),
  pathBorderColor: Color(0xFF0D1F0F),
  shadowColor: Color(0x50000000),
);
const SagaBiomeTheme _desertLight = SagaBiomeTheme(
  backgroundColor: Color(0xFFC4A35A),
  pathFillColor: Color(0xFF8B6914),
  pathBorderColor: Color(0xFF5C4510),
  shadowColor: Color(0x40000000),
);
const SagaBiomeTheme _desertDark = SagaBiomeTheme(
  backgroundColor: Color(0xFF7A5C2A),
  pathFillColor: Color(0xFFA67C32),
  pathBorderColor: Color(0xFF3D2E14),
  shadowColor: Color(0x50000000),
);
const SagaBiomeTheme _glacierLight = SagaBiomeTheme(
  backgroundColor: Color(0xFFB0D4E8),
  pathFillColor: Color(0xFFE8F4FA),
  pathBorderColor: Color(0xFF1E3A5F),
  shadowColor: Color(0x40000000),
);
const SagaBiomeTheme _glacierDark = SagaBiomeTheme(
  backgroundColor: Color(0xFF2A4A5C),
  pathFillColor: Color(0xFF4A7A94),
  pathBorderColor: Color(0xFF0F1F2F),
  shadowColor: Color(0x50000000),
);
