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
  });
}
