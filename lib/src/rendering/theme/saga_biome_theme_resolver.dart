import 'package:flutter/material.dart';

import '../../core/domain/biome_ids.dart';
import 'saga_biome_theme.dart';

/// Resolves [SagaBiomeTheme] from biome id.
///
/// Since `SagaMapConfig.biomeIds` is host-supplied, an implementation will be
/// handed ids it has never seen. It must return *some* theme for every id —
/// a resolver that throws takes the whole map down over a typo — and it should
/// make that fallback visible in debug, not silent.
abstract interface class SagaBiomeThemeResolver {
  SagaBiomeTheme resolve(String biomeId);
}

/// Built-in biome resolver with light/dark palettes.
///
/// Knows the three ids in [kSagaBiomeIds]. **Any other id falls back to the
/// forest theme** rather than throwing: a map that is the wrong green still
/// works, a map that crashes does not. In debug builds the first fallback for
/// each unknown id prints a warning, once, so a mistyped id in a host's own
/// `biomeIds` does not silently paint the whole world one colour.
///
/// A host with its own realms implements [SagaBiomeThemeResolver] rather than
/// living with this fallback.
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
        return isLight ? _forestLight : _forestDark;
      default:
        _warnUnknownBiomeOnce(biomeId);
        return isLight ? _forestLight : _forestDark;
    }
  }
}

/// Ids already reported, so a resolve called once per chunk per frame does not
/// turn one typo into a log flood.
final Set<String> _reportedUnknownBiomeIds = <String>{};

/// Prints one debug-mode warning per unknown biome id.
///
/// Silence here is the failure mode ADR-0007 calls out: the host believes its
/// realms are themed and sees a uniformly forest-coloured map instead.
void _warnUnknownBiomeOnce(String biomeId) {
  assert(() {
    if (_reportedUnknownBiomeIds.add(biomeId)) {
      debugPrint(
        'saga_map: DefaultSagaBiomeThemeResolver does not know the biome id '
        '"$biomeId" and is falling back to the forest theme. Implement '
        'SagaBiomeThemeResolver to theme your own SagaMapConfig.biomeIds.',
      );
    }
    return true;
  }());
}

/// Clears the "already warned" set. Test-only.
@visibleForTesting
void debugResetUnknownBiomeWarnings() => _reportedUnknownBiomeIds.clear();

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
