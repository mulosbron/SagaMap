import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Driver for `integration_test/screenshot_test.dart`.
///
/// The screenshot itself is taken inside the app process; only the host can
/// write files, so the bytes come back here to be saved. Run from `example/`:
///
/// ```bash
/// flutter drive \
///   --driver=test_driver/integration_test.dart \
///   --target=integration_test/screenshot_test.dart \
///   -d <device>
/// ```
///
/// Paths are relative to `example/`, which is where `flutter drive` runs, so
/// the images land in the package's own `doc/screenshots/`.
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('../doc/screenshots/$name.png');
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
      stdout.writeln('wrote ${file.path} (${bytes.length} bytes)');
      return true;
    },
  );
}
