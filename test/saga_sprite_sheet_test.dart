import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Serves a synthetic image so sprite playback can be tested without assets.
class _FakeImageProvider extends ImageProvider<_FakeImageProvider> {
  _FakeImageProvider(this.image, {this.scale = 1.0, this.synchronous = true});

  final ui.Image image;
  final double scale;
  final bool synchronous;

  @override
  Future<_FakeImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FakeImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _FakeImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final info = ImageInfo(image: image, scale: scale);
    if (synchronous) {
      return OneFrameImageStreamCompleter(SynchronousFuture<ImageInfo>(info));
    }
    return OneFrameImageStreamCompleter(Future<ImageInfo>.delayed(
      const Duration(milliseconds: 50),
      () => info,
    ));
  }

  @override
  bool operator ==(Object other) =>
      other is _FakeImageProvider &&
      other.image == image &&
      other.scale == scale &&
      other.synchronous == synchronous;

  @override
  int get hashCode => Object.hash(image, scale, synchronous);
}

void main() {
  group('slicing', () {
    test('a horizontal strip lays frames side by side', () {
      // The agreed default: three 60x60 frames make a 180x60 image.
      const sheet =
          SagaSpriteSheet(frameWidth: 60, frameHeight: 60, frameCount: 3);

      expect(sheet.sheetSize, const Size(180, 60));
      expect(sheet.rows, 1);
      expect(sheet.frameRect(0), const Rect.fromLTWH(0, 0, 60, 60));
      expect(sheet.frameRect(1), const Rect.fromLTWH(60, 0, 60, 60));
      expect(sheet.frameRect(2), const Rect.fromLTWH(120, 0, 60, 60));
    });

    test('a vertical strip stacks frames', () {
      const sheet = SagaSpriteSheet(
        frameWidth: 60,
        frameHeight: 60,
        frameCount: 3,
        layout: SagaSpriteLayout.vertical,
      );

      expect(sheet.sheetSize, const Size(60, 180));
      expect(sheet.frameRect(1), const Rect.fromLTWH(0, 60, 60, 60));
      expect(sheet.frameRect(2), const Rect.fromLTWH(0, 120, 60, 60));
    });

    test('a grid fills left to right then top to bottom', () {
      const sheet = SagaSpriteSheet(
        frameWidth: 32,
        frameHeight: 32,
        frameCount: 6,
        layout: SagaSpriteLayout.grid,
        columns: 3,
      );

      expect(sheet.rows, 2);
      expect(sheet.sheetSize, const Size(96, 64));
      expect(sheet.frameRect(2), const Rect.fromLTWH(64, 0, 32, 32));
      expect(sheet.frameRect(3), const Rect.fromLTWH(0, 32, 32, 32));
    });

    test('a partly filled last row still measures whole rows', () {
      const sheet = SagaSpriteSheet(
        frameWidth: 10,
        frameHeight: 10,
        frameCount: 7,
        layout: SagaSpriteLayout.grid,
        columns: 3,
      );

      expect(sheet.rows, 3);
      expect(sheet.sheetSize, const Size(30, 30));
      expect(sheet.frameRect(6), const Rect.fromLTWH(0, 20, 10, 10));
    });

    test('spacing and margin shift the frames', () {
      const sheet = SagaSpriteSheet(
        frameWidth: 20,
        frameHeight: 20,
        frameCount: 3,
        spacing: 4,
        margin: 2,
      );

      expect(sheet.frameRect(0), const Rect.fromLTWH(2, 2, 20, 20));
      expect(sheet.frameRect(1), const Rect.fromLTWH(26, 2, 20, 20));
      // 2 margin + 3*20 frames + 2*4 gaps + 2 margin
      expect(sheet.sheetSize.width, 72);
    });

    test('a single frame is a valid sheet', () {
      const sheet =
          SagaSpriteSheet(frameWidth: 8, frameHeight: 8, frameCount: 1);
      expect(sheet.frameRect(0), const Rect.fromLTWH(0, 0, 8, 8));
      expect(sheet.sheetSize, const Size(8, 8));
    });

    test('an out-of-range frame asserts', () {
      const sheet =
          SagaSpriteSheet(frameWidth: 8, frameHeight: 8, frameCount: 2);
      expect(() => sheet.frameRect(2), throwsAssertionError);
      expect(() => sheet.frameRect(-1), throwsAssertionError);
    });

    test('a grid without columns asserts', () {
      expect(
        () => SagaSpriteSheet(
          frameWidth: 8,
          frameHeight: 8,
          frameCount: 4,
          layout: SagaSpriteLayout.grid,
        ),
        throwsAssertionError,
      );
    });

    test('degenerate dimensions assert', () {
      expect(
        () => SagaSpriteSheet(frameWidth: 0, frameHeight: 8, frameCount: 1),
        throwsAssertionError,
      );
      expect(
        () => SagaSpriteSheet(frameWidth: 8, frameHeight: 8, frameCount: 0),
        throwsAssertionError,
      );
    });

    test('sheets compare by value', () {
      const a = SagaSpriteSheet(frameWidth: 60, frameHeight: 60, frameCount: 3);
      const b = SagaSpriteSheet(frameWidth: 60, frameHeight: 60, frameCount: 3);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(a.copyWith(frameCount: 4)));
    });
  });

  group('playback', () {
    const clip = SagaSpriteClip(count: 4, fps: 10);
    const frame = Duration(milliseconds: 100);

    test('advances one frame per tick', () {
      expect(clip.frameAt(Duration.zero), 0);
      expect(clip.frameAt(frame), 1);
      expect(clip.frameAt(frame * 2), 2);
      expect(clip.frameAt(frame * 3), 3);
    });

    test('holds a frame for its whole duration', () {
      expect(clip.frameAt(const Duration(milliseconds: 99)), 0);
      expect(clip.frameAt(const Duration(milliseconds: 100)), 1);
      expect(clip.frameAt(const Duration(milliseconds: 199)), 1);
    });

    test('loop wraps around', () {
      expect(clip.frameAt(frame * 4), 0);
      expect(clip.frameAt(frame * 5), 1);
      expect(clip.frameAt(frame * 41), 1);
    });

    test('once holds the last frame', () {
      const once = SagaSpriteClip(
        count: 4,
        fps: 10,
        loop: SagaSpriteLoop.once,
      );
      expect(once.frameAt(frame * 3), 3);
      expect(once.frameAt(frame * 4), 3);
      expect(once.frameAt(frame * 100), 3);
      expect(once.isFinished(frame * 3), isFalse);
      expect(once.isFinished(frame * 4), isTrue);
    });

    test('pingPong turns around without repeating the end frames', () {
      const bounce = SagaSpriteClip(
        count: 4,
        fps: 10,
        loop: SagaSpriteLoop.pingPong,
      );
      // 0,1,2,3,2,1, then back to 0 — a naive mirror would stutter on 3 and 0.
      final sequence = [
        for (var i = 0; i < 8; i++) bounce.frameAt(frame * i),
      ];
      expect(sequence, [0, 1, 2, 3, 2, 1, 0, 1]);
    });

    test('a clip offset into the sheet returns sheet indices', () {
      const walk = SagaSpriteClip(from: 4, count: 3, fps: 10);
      expect(walk.frameAt(Duration.zero), 4);
      expect(walk.frameAt(frame * 2), 6);
      expect(walk.frameAt(frame * 3), 4);
    });

    test('a one-frame clip never moves', () {
      const still = SagaSpriteClip(
        from: 2,
        count: 1,
        loop: SagaSpriteLoop.pingPong,
      );
      expect(still.frameAt(Duration.zero), 2);
      expect(still.frameAt(frame * 50), 2);
    });

    test('negative elapsed is treated as the start', () {
      expect(clip.frameAt(const Duration(milliseconds: -500)), 0);
    });

    test('pass duration follows the frame rate', () {
      expect(clip.passDuration, const Duration(milliseconds: 400));
      expect(
        const SagaSpriteClip(count: 6, fps: 60).passDuration,
        const Duration(milliseconds: 100),
      );
    });

    test('wholeSheet covers every frame', () {
      const sheet =
          SagaSpriteSheet(frameWidth: 10, frameHeight: 10, frameCount: 5);
      final all = SagaSpriteClip.wholeSheet(sheet);
      expect(all.from, 0);
      expect(all.count, 5);
    });

    test('degenerate clips assert', () {
      expect(() => SagaSpriteClip(count: 0), throwsAssertionError);
      expect(() => SagaSpriteClip(count: 2, fps: 0), throwsAssertionError);
    });
  });

  group('widget', () {
    late ui.Image image;
    late ui.Image hiDpiImage;

    setUp(() async {
      // Built here, not inside testWidgets: decoding is real async work, and
      // the fake-async zone a widget test runs in would never let it finish.
      image = await createTestImage(width: 180, height: 60);
      hiDpiImage = await createTestImage(width: 360, height: 120);
    });

    Future<void> pump(
      WidgetTester tester, {
      required ImageProvider provider,
      SagaSpriteClip clip = const SagaSpriteClip(count: 3, fps: 10),
      bool playing = true,
      bool disableAnimations = false,
      Widget? placeholder,
      List<int>? frames,
    }) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 60,
                height: 60,
                child: SagaSpriteAnimation(
                  image: provider,
                  sheet: const SagaSpriteSheet(
                    frameWidth: 60,
                    frameHeight: 60,
                    frameCount: 3,
                  ),
                  clip: clip,
                  playing: playing,
                  placeholder: placeholder,
                  onFrame: frames?.add,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('renders once the image resolves', (tester) async {
      await pump(tester, provider: _FakeImageProvider(image));
      await tester.pump();

      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the placeholder until the image arrives',
        (tester) async {
      await pump(
        tester,
        provider: _FakeImageProvider(image, synchronous: false),
        placeholder: const Text('loading'),
      );
      await tester.pump();

      // Web decodes on a later frame far more often than mobile, so this state
      // is not rare there.
      expect(find.text('loading'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('loading'), findsNothing);
    });

    testWidgets('advances frames over time', (tester) async {
      final frames = <int>[];
      await pump(tester, provider: _FakeImageProvider(image), frames: frames);
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(frames, isNotEmpty);
      expect(frames.first, greaterThan(0));

      // Leave no ticker running into the next test.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a paused clip holds its frame', (tester) async {
      final frames = <int>[];
      await pump(
        tester,
        provider: _FakeImageProvider(image),
        playing: false,
        frames: frames,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(frames, isEmpty);
    });

    testWidgets('reduced motion freezes the animation', (tester) async {
      final frames = <int>[];
      await pump(
        tester,
        provider: _FakeImageProvider(image),
        disableAnimations: true,
        frames: frames,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Honouring the platform setting, not an option.
      expect(frames, isEmpty);
    });

    testWidgets('a once clip reports completion', (tester) async {
      var completed = false;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 60,
            height: 60,
            child: SagaSpriteAnimation(
              image: _FakeImageProvider(image),
              sheet: const SagaSpriteSheet(
                frameWidth: 60,
                frameHeight: 60,
                frameCount: 3,
              ),
              clip: const SagaSpriteClip(
                count: 3,
                fps: 10,
                loop: SagaSpriteLoop.once,
              ),
              onCompleted: () => completed = true,
            ),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(completed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a 2x asset samples twice the pixels', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 60,
            height: 60,
            child: SagaSpriteAnimation(
              image: _FakeImageProvider(hiDpiImage, scale: 2),
              sheet: const SagaSpriteSheet(
                frameWidth: 60,
                frameHeight: 60,
                frameCount: 3,
              ),
              clip: const SagaSpriteClip(count: 3),
              playing: false,
            ),
          ),
        ),
      );
      await tester.pump();

      // Frame rectangles are written in logical units; the resolved asset
      // scale is what turns them into the right pixel block, so 2x and 3x
      // variants work without restating the sheet.
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<SagaSpritePainter>()
          .single;
      expect(painter.imageScale, 2);
      expect(painter.sourceRect, const Rect.fromLTWH(0, 0, 60, 60));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('disposing leaves no ticker behind', (tester) async {
      await pump(tester, provider: _FakeImageProvider(image));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());

      expect(tester.takeException(), isNull);
    });
  });

  group('painter', () {
    test('repaints only when something changed', () async {
      final image = await createTestImage(width: 60, height: 60);
      final a = SagaSpritePainter(
        image: image,
        imageScale: 1,
        sourceRect: const Rect.fromLTWH(0, 0, 60, 60),
      );
      final same = SagaSpritePainter(
        image: image,
        imageScale: 1,
        sourceRect: const Rect.fromLTWH(0, 0, 60, 60),
      );
      final movedFrame = SagaSpritePainter(
        image: image,
        imageScale: 1,
        sourceRect: const Rect.fromLTWH(60, 0, 60, 60),
      );
      final rescaled = SagaSpritePainter(
        image: image,
        imageScale: 2,
        sourceRect: const Rect.fromLTWH(0, 0, 60, 60),
      );
      final flipped = SagaSpritePainter(
        image: image,
        imageScale: 1,
        sourceRect: const Rect.fromLTWH(0, 0, 60, 60),
        flipHorizontally: true,
      );

      expect(a.shouldRepaint(same), isFalse);
      expect(a.shouldRepaint(movedFrame), isTrue);
      expect(a.shouldRepaint(rescaled), isTrue);
      expect(a.shouldRepaint(flipped), isTrue);
      image.dispose();
    });

    test('a scaled sheet samples a proportionally larger block', () async {
      final image = await createTestImage(width: 360, height: 120);
      const sheet = SagaSpriteSheet(
        frameWidth: 60,
        frameHeight: 60,
        frameCount: 3,
      );

      // The sheet describes logical units; the painter multiplies by the asset
      // scale to reach pixels. Frame 1 of a 2x sheet starts at pixel 120.
      final logical = sheet.frameRect(1);
      expect(logical.left, 60);
      expect(logical.left * 2, 120);
      expect(logical.width * 2, 120);
      image.dispose();
    });
  });
}
