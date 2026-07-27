import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Background source kind used by map chunk rendering.
enum SagaMapBackgroundKind {
  none,
  color,
  imageAsset,
  svgAsset,
}

/// Strategy used when chunk count exceeds provided backgrounds.
enum SagaMapBackgroundOverflowBehavior {
  loop,
  clampLast,
  empty,
}

/// Immutable configuration object for map backgrounds.
class SagaMapBackgroundConfig {
  final SagaMapBackgroundKind kind;
  final String? assetPath;
  final List<String>? assetPaths;
  final Color color;
  final BoxFit fit;
  final Alignment alignment;
  final SagaMapBackgroundOverflowBehavior overflowBehavior;

  const SagaMapBackgroundConfig.none()
      : kind = SagaMapBackgroundKind.none,
        assetPath = null,
        assetPaths = null,
        color = Colors.transparent,
        fit = BoxFit.cover,
        alignment = Alignment.center,
        overflowBehavior = SagaMapBackgroundOverflowBehavior.loop;

  const SagaMapBackgroundConfig.color({
    required this.color,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  })  : kind = SagaMapBackgroundKind.color,
        assetPath = null,
        assetPaths = null,
        overflowBehavior = SagaMapBackgroundOverflowBehavior.loop;

  const SagaMapBackgroundConfig.imageAsset({
    required this.assetPath,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.color = Colors.transparent,
  })  : kind = SagaMapBackgroundKind.imageAsset,
        assetPaths = null,
        overflowBehavior = SagaMapBackgroundOverflowBehavior.loop;

  const SagaMapBackgroundConfig.imageAssets({
    required this.assetPaths,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.color = Colors.transparent,
    this.overflowBehavior = SagaMapBackgroundOverflowBehavior.loop,
  })  : kind = SagaMapBackgroundKind.imageAsset,
        assetPath = null;

  const SagaMapBackgroundConfig.svgAsset({
    required this.assetPath,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.color = Colors.transparent,
  })  : kind = SagaMapBackgroundKind.svgAsset,
        assetPaths = null,
        overflowBehavior = SagaMapBackgroundOverflowBehavior.loop;

  const SagaMapBackgroundConfig.svgAssets({
    required this.assetPaths,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.color = Colors.transparent,
    this.overflowBehavior = SagaMapBackgroundOverflowBehavior.loop,
  })  : kind = SagaMapBackgroundKind.svgAsset,
        assetPath = null;

  /// Builds the background widget for an optional [chunkIndex].
  Widget buildBackgroundWidget({int? chunkIndex}) {
    switch (kind) {
      case SagaMapBackgroundKind.none:
        return const SizedBox.shrink();
      case SagaMapBackgroundKind.color:
        return ColoredBox(color: color);
      case SagaMapBackgroundKind.imageAsset:
        final resolvedPath = _resolvePath(chunkIndex);
        if (resolvedPath == null || resolvedPath.isEmpty) {
          return const SizedBox.shrink();
        }
        return Image.asset(
          resolvedPath,
          fit: fit,
          alignment: alignment,
        );
      case SagaMapBackgroundKind.svgAsset:
        final resolvedPath = _resolvePath(chunkIndex);
        if (resolvedPath == null || resolvedPath.isEmpty) {
          return const SizedBox.shrink();
        }
        return SvgPicture.asset(
          resolvedPath,
          fit: fit,
          alignment: alignment,
        );
    }
  }

  String? _resolvePath(int? chunkIndex) {
    final candidates = assetPaths;
    if (candidates != null && candidates.isNotEmpty) {
      if (chunkIndex == null) {
        return candidates.first;
      }
      final length = candidates.length;
      if (chunkIndex >= 0 && chunkIndex < length) {
        return candidates[chunkIndex];
      }
      switch (overflowBehavior) {
        case SagaMapBackgroundOverflowBehavior.loop:
          final safeIndex = ((chunkIndex % length) + length) % length;
          return candidates[safeIndex];
        case SagaMapBackgroundOverflowBehavior.clampLast:
          return candidates.last;
        case SagaMapBackgroundOverflowBehavior.empty:
          return null;
      }
    }
    return assetPath;
  }
}
