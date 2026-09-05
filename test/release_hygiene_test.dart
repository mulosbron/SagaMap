@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the shipped text artifacts against regressions that slipped through a
/// merge once already: leftover conflict markers, double-encoded (mojibake)
/// characters, and a package version that drifts from the changelog.
void main() {
  final docs = <String>[
    'CHANGELOG.md',
    'README.md',
    'pubspec.yaml',
  ];

  // Only match markers at the start of a line so prose like "see >>>" is safe.
  final conflictMarker = RegExp(r'^(<{7}|={7}|>{7})(\s|$)', multiLine: true);

  // The classic "UTF-8 decoded as CP1252" artifacts we cleaned up.
  const mojibake = ['â€”', 'â†’', 'â†”'];

  group('release hygiene', () {
    for (final path in docs) {
      test('$path has no merge conflict markers', () {
        final text = File(path).readAsStringSync();
        expect(
          conflictMarker.hasMatch(text),
          isFalse,
          reason: '$path contains an unresolved conflict marker',
        );
      });

      test('$path has no mojibake', () {
        final text = File(path).readAsStringSync();
        for (final seq in mojibake) {
          expect(
            text.contains(seq),
            isFalse,
            reason: '$path contains double-encoded characters',
          );
        }
      });
    }

    test('CHANGELOG documents exactly one heading per version', () {
      final text = File('CHANGELOG.md').readAsStringSync();
      final headings = RegExp(r'^## (.+)$', multiLine: true)
          .allMatches(text)
          .map((m) => m.group(1)!.trim())
          .toList();
      expect(
        headings.length,
        headings.toSet().length,
        reason: 'duplicate version headings in CHANGELOG: $headings',
      );
    });

    test('pubspec version has a matching CHANGELOG section', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match =
          RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(pubspec);
      expect(match, isNotNull, reason: 'pubspec has no version field');
      final version = match!.group(1)!.trim();
      final changelog = File('CHANGELOG.md').readAsStringSync();
      expect(
        changelog.contains('## $version'),
        isTrue,
        reason: 'CHANGELOG has no "## $version" section',
      );
    });
  });
}
