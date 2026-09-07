import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// T-17: a cropping BoxFit must crop, not squash, and a sheet swap must not
/// leave the frame index pointing outside the new sheet.

/// A two-frame strip whose first frame is three horizontal bands: red across
/// the top quarter, green across the middle half, blue across the bottom
/// quarter. A cropping fit shows only the green band; squashing the whole frame
/// into the same box shows all three. Even quadrants would not separate the
/// two — both put the seam in the middle of the box.
Future<ui.Image> _bandedStrip() {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  void box(double l, double t, double w, double h, Color c) =>
      canvas.drawRect(Rect.fromLTWH(l, t, w, h), Paint()..color = c);

  box(0, 0, 40, 10, const Color(0xFFFF0000));
  box(0, 10, 40, 20, const Color(0xFF00FF00));
  box(0, 30, 40, 10, const Color(0xFF0000FF));
  // Frame 1: flat black, so sampling into it is obvious.
  box(40, 0, 40, 40, const Color(0xFF000000));

  return recorder.endRecording().toImage(80, 40);
}

class _RawProvider extends ImageProvider<_RawProvider> {
  _RawProvider(this.image);
  final ui.Image image;

  @override
  Future<_RawProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_RawProvider>(this);

  @override
  ImageStreamCompleter loadImage(
      _RawProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image, scale: 1)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _RawProvider && other.image == image;

  @override
  int get hashCode => image.hashCode;
}

void main() {
  // Real async image work, so it happens outside the fake-async zone a widget
  // test runs in — that zone would never let `toImage` finish.
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image strip;
  setUp(() async => strip = await _bandedStrip());
  tearDown(() => strip.dispose());

  test('BoxFit.cover crops the frame instead of squashing it', () async {
    // A 40x40 frame into a 40x20 box. Covering it means sampling the frame's
    // middle band — all green — at full width. Squashing the whole frame in
    // would show red at the top and blue at the bottom instead.
    final painter = SagaSpritePainter(
      image: strip,
      imageScale: 1,
      sourceRect: const Rect.fromLTWH(0, 0, 40, 40),
      fit: BoxFit.cover,
    );

    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(40, 20));
    final rendered = await recorder.endRecording().toImage(40, 20);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    Color at(int x, int y) {
      final i = (y * 40 + x) * 4;
      return Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
    }

    expect(at(20, 1), const Color(0xFF00FF00), reason: 'top of the box');
    expect(at(20, 10), const Color(0xFF00FF00), reason: 'middle of the box');
    expect(at(20, 18), const Color(0xFF00FF00), reason: 'bottom of the box');

    rendered.dispose();
  });

  test('a non-cropping fit is unaffected', () async {
    // contain samples the whole frame, so all three bands stay visible — the
    // fix must not change what the fits that were already right do.
    final painter = SagaSpritePainter(
      image: strip,
      imageScale: 1,
      sourceRect: const Rect.fromLTWH(0, 0, 40, 40),
      fit: BoxFit.contain,
    );

    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(20, 20));
    final rendered = await recorder.endRecording().toImage(20, 20);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    Color at(int x, int y) {
      final i = (y * 20 + x) * 4;
      return Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
    }

    expect(at(10, 1), const Color(0xFFFF0000));
    expect(at(10, 10), const Color(0xFF00FF00));
    expect(at(10, 18), const Color(0xFF0000FF));

    rendered.dispose();
  });

  testWidgets('a clip that overruns its sheet is refused', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 40,
          height: 40,
          child: SagaSpriteAnimation(
            image: _RawProvider(strip),
            sheet: const SagaSpriteSheet(
              frameWidth: 40,
              frameHeight: 40,
              frameCount: 2,
            ),
            // Six frames out of a two-frame sheet.
            clip: const SagaSpriteClip(count: 6),
          ),
        ),
      ),
    );

    // Thrown, not asserted: an assert is stripped from release builds, which is
    // exactly where sampling outside the sheet shows as corrupt art.
    expect(tester.takeException(), isA<ArgumentError>());
  });

  testWidgets('swapping to a smaller sheet resets the frame', (tester) async {
    Widget build(SagaSpriteSheet sheet, SagaSpriteClip clip) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 40,
          height: 40,
          child: SagaSpriteAnimation(
            image: _RawProvider(strip),
            sheet: sheet,
            clip: clip,
          ),
        ),
      );
    }

    const big = SagaSpriteSheet(frameWidth: 20, frameHeight: 40, frameCount: 4);
    const small =
        SagaSpriteSheet(frameWidth: 40, frameHeight: 40, frameCount: 2);

    await tester
        .pumpWidget(build(big, const SagaSpriteClip(from: 3, count: 1)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    // The clip is unchanged and still names frame 3, which the small sheet does
    // not have. didUpdateWidget used to branch on image and clip but not sheet,
    // so `_frame` stayed at 3 and frameRect sampled outside the sheet with only
    // a debug assert in the way.
    await tester.pumpWidget(
      build(small, const SagaSpriteClip(from: 3, count: 1)),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // Reported, not thrown: a swap should not take the app down, and the frame
    // it keeps drawing is one the new sheet actually has.
    expect(tester.takeException(), isA<ArgumentError>());

    // A clip that fits the new sheet swaps cleanly.
    await tester.pumpWidget(
      build(small, const SagaSpriteClip(from: 1, count: 1)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });
}
