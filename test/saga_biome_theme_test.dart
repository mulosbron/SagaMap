import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Host-defined biomes need two things the 1.x theme did not have: somewhere
/// to hang art keys, and a defined answer for an id the resolver has never
/// heard of.

/// A resolver for a host's own realms, which is what ADR-0007 expects a host
/// with ten of them to write instead of living with the fallback.
class _RealmThemeResolver implements SagaBiomeThemeResolver {
  const _RealmThemeResolver();

  @override
  SagaBiomeTheme resolve(String biomeId) => SagaBiomeTheme(
        backgroundColor: const Color(0xFF101010),
        pathFillColor: const Color(0xFF202020),
        pathBorderColor: const Color(0xFF303030),
        shadowColor: const Color(0x40000000),
        assets: {'nodeSprite': 'assets/$biomeId/node.webp'},
        ambientTint: const Color(0x22FF0000),
      );
}

void main() {
  group('SagaBiomeTheme art hooks', () {
    test('assets and ambientTint default to empty and null', () {
      const theme = SagaBiomeTheme(
        backgroundColor: Color(0xFF000000),
        pathFillColor: Color(0xFF000000),
        pathBorderColor: Color(0xFF000000),
        shadowColor: Color(0xFF000000),
      );

      expect(theme.assets, isEmpty);
      expect(theme.ambientTint, isNull);
    });

    test('a host resolver can hang its own art keys off a biome id', () {
      const resolver = _RealmThemeResolver();

      // The package does not load these; it carries them.
      expect(
        resolver.resolve('sunspire').assets['nodeSprite'],
        'assets/sunspire/node.webp',
      );
      expect(
        resolver.resolve('drownlands').assets['nodeSprite'],
        'assets/drownlands/node.webp',
      );
    });

    test('the built-in themes carry no assets', () {
      const resolver = DefaultSagaBiomeThemeResolver();
      for (final id in kSagaBiomeIds) {
        expect(resolver.resolve(id).assets, isEmpty);
        expect(resolver.resolve(id).ambientTint, isNull);
      }
    });
  });

  group('DefaultSagaBiomeThemeResolver fallback', () {
    setUp(debugResetUnknownBiomeWarnings);

    test('the three built-in ids resolve to three distinct themes', () {
      const resolver = DefaultSagaBiomeThemeResolver();
      final backgrounds = kSagaBiomeIds
          .map((id) => resolver.resolve(id).backgroundColor)
          .toSet();
      expect(backgrounds.length, kSagaBiomeIds.length);
    });

    test('an unknown id falls back to forest rather than throwing', () {
      // A map that is the wrong green still works; one that crashes does not.
      const resolver = DefaultSagaBiomeThemeResolver();
      expect(
        resolver.resolve('sunspire').backgroundColor,
        resolver.resolve(kBiomeIdForest).backgroundColor,
      );
    });

    test('the fallback follows the configured brightness', () {
      const light = DefaultSagaBiomeThemeResolver();
      const dark = DefaultSagaBiomeThemeResolver(brightness: Brightness.dark);

      expect(light.resolve('sunspire').backgroundColor,
          light.resolve(kBiomeIdForest).backgroundColor);
      expect(dark.resolve('sunspire').backgroundColor,
          dark.resolve(kBiomeIdForest).backgroundColor);
      expect(light.resolve('sunspire').backgroundColor,
          isNot(dark.resolve('sunspire').backgroundColor));
    });

    test('an unknown id is reported once, not once per resolve', () {
      const resolver = DefaultSagaBiomeThemeResolver();
      final printed = <String>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) printed.add(message);
      };
      addTearDown(() => debugPrint = previous);

      for (var i = 0; i < 50; i++) {
        resolver.resolve('sunspire');
      }
      resolver.resolve('drownlands');
      // Known ids stay silent.
      for (final id in kSagaBiomeIds) {
        resolver.resolve(id);
      }

      expect(printed.where((m) => m.contains('sunspire')), hasLength(1));
      expect(printed.where((m) => m.contains('drownlands')), hasLength(1));
      expect(printed, hasLength(2));
      expect(printed.first, contains('SagaBiomeThemeResolver'));
    });
  });
}
