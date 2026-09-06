import 'package:flutter/material.dart';

/// Color and stroke tokens for painting one biome.
class SagaBiomeTheme {
  final Color backgroundColor;
  final Gradient? backgroundGradient;

  /// Colours for the path already covered, and for the whole path when no
  /// progress is supplied.
  final Color pathFillColor;
  final Color pathBorderColor;

  /// Colours for the stretch still ahead of the player.
  ///
  /// `null` paints the whole path in the walked colours, which is how a map
  /// that tracks no progress behaves. Setting them dimmer gives the familiar
  /// "road lights up as you go" look.
  final Color? upcomingPathFillColor;
  final Color? upcomingPathBorderColor;
  final Color shadowColor;
  final double pathBorderWidth;
  final double pathInnerStrokeWidth;
  final double shadowOffsetDy;
  final double shadowBlurSigma;

  /// Optional art keys for this biome, resolved by the host.
  ///
  /// The package never loads these; it hands them back to the node and path
  /// builders so one biome can look different from another beyond its colours.
  /// Reach them from a builder through the resolver you already pass the view:
  ///
  /// ```dart
  /// final theme = resolver.resolve(chunk.dominantBiomeId);
  /// final sprite = theme.assets['nodeSprite'];
  /// ```
  ///
  /// Deliberately an opaque `Map<String, String>` rather than named fields
  /// like `nodeSprite` or `pathStoneAsset`. Named fields would freeze an asset
  /// taxonomy the package has no business defining, and a format the package
  /// does not load — the same trap `flutter_svg` was (ADR-0008). Your keys,
  /// your formats, your loader.
  ///
  /// Empty by default.
  final Map<String, String> assets;

  /// A wash painted over the whole chunk, for biome mood beyond the palette.
  ///
  /// Applied by the chunk painter after the background and the path, so it
  /// tints both. It sits *under* the node widgets, which are separate widgets
  /// the host builds — a tint is atmosphere, not a filter over your UI.
  ///
  /// Use a translucent colour; an opaque one hides the chunk. `null`, the
  /// default, paints nothing.
  final Color? ambientTint;

  const SagaBiomeTheme({
    required this.backgroundColor,
    this.backgroundGradient,
    required this.pathFillColor,
    required this.pathBorderColor,
    this.upcomingPathFillColor,
    this.upcomingPathBorderColor,
    required this.shadowColor,
    this.pathBorderWidth = 3.0,
    this.pathInnerStrokeWidth = 2.0,
    this.shadowOffsetDy = 4.0,
    this.shadowBlurSigma = 8.0,
    this.assets = const <String, String>{},
    this.ambientTint,
  });
}
