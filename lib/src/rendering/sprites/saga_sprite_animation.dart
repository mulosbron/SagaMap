import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'saga_sprite_sheet.dart';

/// Plays a clip from a sprite sheet.
///
/// Depends on nothing but Flutter, so it runs identically on Android, iOS and
/// the web. The other character formats — Lottie, Rive, GIF, WebP — already
/// have packages that do this; sprite sheets do not, which is why this one is
/// written out.
class SagaSpriteAnimation extends StatefulWidget {
  final ImageProvider image;
  final SagaSpriteSheet sheet;
  final SagaSpriteClip clip;

  /// Mirrors the frame across its vertical centre.
  ///
  /// Lets one set of frames face both ways, instead of authoring a mirrored
  /// copy of every walk cycle.
  final bool flipHorizontally;

  /// Whether the clip advances. Freezing holds the current frame rather than
  /// resetting, so pausing and resuming does not restart the animation.
  final bool playing;

  /// Defaults to [FilterQuality.none], which is what pixel art needs: any
  /// smoothing turns crisp pixels into mush when the sprite is scaled up.
  final FilterQuality filterQuality;

  /// How the frame is fitted into the widget's box.
  final BoxFit fit;

  /// Shown until the image has decoded. Web decodes on a later frame far more
  /// often than mobile does, so this is not a rare state there.
  final Widget? placeholder;

  /// Reports the sheet frame index whenever it changes.
  final ValueChanged<int>? onFrame;

  /// Called when a [SagaSpriteLoop.once] clip reaches its last frame.
  final VoidCallback? onCompleted;

  const SagaSpriteAnimation({
    super.key,
    required this.image,
    required this.sheet,
    required this.clip,
    this.flipHorizontally = false,
    this.playing = true,
    this.filterQuality = FilterQuality.none,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.onFrame,
    this.onCompleted,
  });

  @override
  State<SagaSpriteAnimation> createState() => _SagaSpriteAnimationState();
}

class _SagaSpriteAnimationState extends State<SagaSpriteAnimation>
    with SingleTickerProviderStateMixin {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _image;
  double _imageScale = 1;

  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;
  Duration _lastTick = Duration.zero;
  int _frame = 0;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _frame = widget.clip.from;
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant SagaSpriteAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _resolveImage();
    }
    if (oldWidget.clip != widget.clip) {
      // A different clip is a different animation; restarting is the only
      // sensible reading of "now play this instead".
      _elapsed = Duration.zero;
      _completed = false;
      _frame = widget.clip.from;
    }
    _syncTicker();
  }

  /// Animations are suppressed when the platform asks for reduced motion; the
  /// clip then holds its first frame.
  bool get _animationsAllowed {
    final query = MediaQuery.maybeOf(context);
    return query == null || !query.disableAnimations;
  }

  void _syncTicker() {
    final shouldRun = widget.playing && _animationsAllowed && !_completed;
    if (shouldRun && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration total) {
    // Accumulate deltas rather than using the raw ticker time, so pausing does
    // not fast-forward the clip by however long it was stopped.
    final delta =
        _lastTick == Duration.zero ? Duration.zero : total - _lastTick;
    _lastTick = total;
    _elapsed += delta;

    final next = widget.clip.frameAt(_elapsed);
    if (next != _frame) {
      setState(() => _frame = next);
      widget.onFrame?.call(next);
    }

    if (widget.clip.isFinished(_elapsed) && !_completed) {
      _completed = true;
      _ticker.stop();
      widget.onCompleted?.call();
    }
  }

  void _resolveImage() {
    final configuration = createLocalImageConfiguration(context);
    final stream = widget.image.resolve(configuration);
    if (stream.key == _stream?.key) return;

    _detachStream();
    _listener = ImageStreamListener(_onImage, onError: _onImageError);
    _stream = stream..addListener(_listener!);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    setState(() {
      _image?.dispose();
      _image = info.image;
      // A 2.0x asset holds twice as many pixels per logical unit, so the sheet's
      // logical frame rectangles have to be scaled to reach the right pixels.
      _imageScale = info.scale;
    });
  }

  void _onImageError(Object error, StackTrace? stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'saga_map',
        context: ErrorDescription('resolving a sprite sheet image'),
      ),
    );
  }

  void _detachStream() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _detachStream();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return widget.placeholder ?? const SizedBox.shrink();
    }

    return CustomPaint(
      painter: SagaSpritePainter(
        image: image,
        imageScale: _imageScale,
        sourceRect: widget.sheet.frameRect(_frame),
        flipHorizontally: widget.flipHorizontally,
        filterQuality: widget.filterQuality,
        fit: widget.fit,
      ),
    );
  }
}

/// Draws one sprite frame into the box it is given.
class SagaSpritePainter extends CustomPainter {
  final ui.Image image;

  /// Image pixels per logical pixel, from the resolved asset.
  final double imageScale;

  /// Frame rectangle in logical units; scaled by [imageScale] before sampling.
  final Rect sourceRect;

  final bool flipHorizontally;
  final FilterQuality filterQuality;
  final BoxFit fit;

  const SagaSpritePainter({
    required this.image,
    required this.imageScale,
    required this.sourceRect,
    this.flipHorizontally = false,
    this.filterQuality = FilterQuality.none,
    this.fit = BoxFit.contain,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final source = Rect.fromLTWH(
      sourceRect.left * imageScale,
      sourceRect.top * imageScale,
      sourceRect.width * imageScale,
      sourceRect.height * imageScale,
    );

    final fitted = applyBoxFit(fit, sourceRect.size, size);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );

    canvas.save();
    if (flipHorizontally) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawImageRect(
      image,
      source,
      destination,
      Paint()..filterQuality = filterQuality,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SagaSpritePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.imageScale != imageScale ||
        oldDelegate.sourceRect != sourceRect ||
        oldDelegate.flipHorizontally != flipHorizontally ||
        oldDelegate.filterQuality != filterQuality ||
        oldDelegate.fit != fit;
  }
}
