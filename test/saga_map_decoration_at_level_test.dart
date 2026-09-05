import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';
import 'package:flutter/widgets.dart';

void main() {
  test('SagaMapDecoration.atLevel creates proper instance', () {
    final dec = SagaMapDecoration.atLevel(
      levelId: 10,
      height: 100,
      builder: (context) => const SizedBox(),
    );
    expect(dec.levelId, 10);
    expect(dec.height, 100);
    expect(dec.chunkFraction, isNull);
    expect(dec.pathPosition, isNull);
  });
}
