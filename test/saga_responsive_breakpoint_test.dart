import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// T-15: the built-in bounds are inclusive integers while the resolver takes a
/// `double`, so every gap between them — `(450, 451)`, `(900, 901)`,
/// `(1920, 1921)` — used to fall through to a hard-coded `desktop`.

void main() {
  const resolver = SagaResponsiveResolver();

  group('breakpoints cover the whole number line', () {
    test('a fractional width lands in the band it belongs to', () {
      expect(resolver.resolveBreakpoint(450.5), SagaMapBreakpointName.mobile);
      expect(resolver.resolveBreakpoint(900.5), SagaMapBreakpointName.tablet);
      expect(resolver.resolveBreakpoint(1920.5), SagaMapBreakpointName.desktop);

      // A width a real device actually reports, from a 2880px screen at 7x.
      expect(
        resolver.resolveBreakpoint(411.42857142857144),
        SagaMapBreakpointName.mobile,
      );
    });

    test('the seams do not resize the map', () {
      // The regression that mattered: a phone-width viewport getting desktop
      // sizing means touch targets a quarter smaller than the design.
      final justInside = resolver.resolveForWidth(450);
      final justPast = resolver.resolveForWidth(450.5);

      expect(justPast.breakpoint, justInside.breakpoint);
      expect(justPast.nodeSize, justInside.nodeSize);
      expect(justPast.interactionRadius, justInside.interactionRadius);
      expect(justPast.maxLateralExtent, justInside.maxLateralExtent);
    });

    test('every width from 0 to 2000 resolves as the integer below it', () {
      // Sweeping halves is the cheap way to prove there is no seam left at
      // all, rather than testing the three we happen to know about.
      for (var w = 0; w <= 2000; w++) {
        expect(
          resolver.resolveBreakpoint(w + 0.5),
          resolver.resolveBreakpoint(w.toDouble()),
          reason: 'width ${w + 0.5}',
        );
      }
    });

    test('the ends of the line behave', () {
      expect(resolver.resolveBreakpoint(0), SagaMapBreakpointName.mobile);
      expect(resolver.resolveBreakpoint(-1), SagaMapBreakpointName.mobile);
      expect(
        resolver.resolveBreakpoint(double.infinity),
        SagaMapBreakpointName.ultra4k,
      );
      // Every comparison against NaN is false, so it matches no interval and
      // has started none. The narrowest band is the safer wrong answer: bigger
      // nodes and bigger touch targets.
      expect(
          resolver.resolveBreakpoint(double.nan), SagaMapBreakpointName.mobile);
    });

    test('a host config with its own gaps is covered too', () {
      const sparse = SagaResponsiveResolver(
        config: SagaMapResponsiveConfig(
          breakpoints: [
            SagaMapBreakpoint(
                start: 0, end: 100, name: SagaMapBreakpointName.mobile),
            SagaMapBreakpoint(
                start: 500, end: 600, name: SagaMapBreakpointName.desktop),
          ],
          nodeSizePolicy:
              SagaMapValuePolicy(mobile: 1, tablet: 1, desktop: 1, ultra4k: 1),
          nodeSpacingPolicy:
              SagaMapValuePolicy(mobile: 1, tablet: 1, desktop: 1, ultra4k: 1),
          zoomPolicy:
              SagaMapValuePolicy(mobile: 1, tablet: 1, desktop: 1, ultra4k: 1),
          interactionRadiusPolicy:
              SagaMapValuePolicy(mobile: 1, tablet: 1, desktop: 1, ultra4k: 1),
          cameraPaddingPolicy:
              SagaMapValuePolicy(mobile: 1, tablet: 1, desktop: 1, ultra4k: 1),
          maxLateralExtentPolicy: null,
          scrollSensitivityPolicy:
              SagaMapValuePolicy(mobile: 1, tablet: 1, desktop: 1, ultra4k: 1),
          pathAxis: SagaMapPathAxis.vertical,
        ),
      );

      // 300 is in neither interval; it belongs to the widest band it is past.
      expect(sparse.resolveBreakpoint(300), SagaMapBreakpointName.mobile);
      expect(sparse.resolveBreakpoint(700), SagaMapBreakpointName.desktop);
    });
  });
}
