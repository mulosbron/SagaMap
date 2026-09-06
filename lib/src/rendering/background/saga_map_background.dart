import 'package:flutter/material.dart';

/// Builds a background layer for one chunk.
///
/// [chunkIndex] is the chunk being painted, or `null` when the background is
/// built outside a chunk. Vary the artwork by it to reproduce what the removed
/// multi-asset constructors did.
typedef SagaMapBackgroundBuilder = Widget Function(
  BuildContext context,
  int? chunkIndex,
);

/// Background source kind used by map chunk rendering.
enum SagaMapBackgroundKind {
  none,
  color,
  imageAsset,

  /// The host supplies the widget. Anything Flutter can draw goes here.
  builder,
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

  /// Builds the background yourself.
  ///
  /// The package positions and scrolls whatever this returns; it loads nothing
  /// itself. That is the whole point: the package has no opinion about your
  /// artwork's format, and therefore no dependency on a decoder for it.
  ///
  /// For an SVG, add `flutter_svg` to your own app and return
  /// `SvgPicture.asset`. Lottie, Rive, a `CustomPaint`, a video, a gradient —
  /// same shape.
  ///
  /// Only consulted for [SagaMapBackgroundKind.builder]. `null` there renders
  /// nothing, the same as [SagaMapBackgroundConfig.none].
  final SagaMapBackgroundBuilder? backgroundBuilder;

  const SagaMapBackgroundConfig.none()
      : kind = SagaMapBackgroundKind.none,
        assetPath = null,
        assetPaths = null,
        color = Colors.transparent,
        fit = BoxFit.cover,
        alignment = Alignment.center,
        overflowBehavior = SagaMapBackgroundOverflowBehavior.loop,
        backgroundBuilder = null;

  const SagaMapBackgroundConfig.color({
    required this.color,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  })  : kind = SagaMapBackgroundKind.color,
        assetPath = null,
        assetPaths = null,
        overflowBehavior = SagaMapBackgroundOverflowBehavior.loop,
        backgroundBuilder = null;

  const SagaMapBackgroundConfig.imageAsset({
    required this.assetPath,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.color = Colors.transparent,
  })  : kind = SagaMapBackgroundKind.imageAsset,
        assetPaths = null,
        overflowBehavior = SagaMapBackgroundOverflowBehavior.loop,
        backgroundBuilder = null;

  const SagaMapBackgroundConfig.imageAssets({
    required this.assetPaths,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.color = Colors.transparent,
    this.overflowBehavior = SagaMapBackgroundOverflowBehavior.loop,
  })  : kind = SagaMapBackgroundKind.imageAsset,
        assetPath = null,
        backgroundBuilder = null;

  /// A background the host draws.
  ///
  /// [fit], [alignment] and [overflowBehavior] do not apply — they describe how
  /// the package would place an asset it loaded, and here it loads nothing.
  /// The returned widget fills the chunk; size and align it yourself.
  const SagaMapBackgroundConfig.builder(this.backgroundBuilder)
      : kind = SagaMapBackgroundKind.builder,
        assetPath = null,
        assetPaths = null,
        color = Colors.transparent,
        fit = BoxFit.cover,
        alignment = Alignment.center,
        overflowBehavior = SagaMapBackgroundOverflowBehavior.loop;

  /// Builds the background widget for an optional [chunkIndex].
  Widget buildBackgroundWidget(BuildContext context, {int? chunkIndex}) {
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
      case SagaMapBackgroundKind.builder:
        return backgroundBuilder?.call(context, chunkIndex) ??
            const SizedBox.shrink();
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
