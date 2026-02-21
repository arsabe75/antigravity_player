import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Architecture Tests', () {
    test('Domain layer should not depend on other layers', () {
      final domainDir = Directory('lib/domain');
      if (!domainDir.existsSync()) {
        fail('Domain directory not found');
      }

      final dartFiles = domainDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        final lines = content.split('\n');

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('import ') || line.startsWith('export ')) {
            // Check for forbidden imports
            if (line.contains('package:video_player_app/infrastructure/') ||
                line.contains('package:video_player_app/application/') ||
                line.contains('package:video_player_app/presentation/') ||
                line.contains('../infrastructure/') ||
                line.contains('../application/') ||
                line.contains('../presentation/') ||
                line.contains('package:flutter/')) {
              fail(
                'Domain layer violates boundaries in file ${file.path}:${i + 1}\n'
                'Import found: $line',
              );
            }
          }
        }
      }
    });

    test('Application layer should not depend on presentation layer', () {
      final applicationDir = Directory('lib/application');
      if (!applicationDir.existsSync()) {
        fail('Application directory not found');
      }

      final dartFiles = applicationDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        final lines = content.split('\n');

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('import ') || line.startsWith('export ')) {
            // Check for forbidden imports
            if (line.contains('package:video_player_app/presentation/') ||
                line.contains('../presentation/') ||
                line.contains('../../presentation/')) {
              fail(
                'Application layer violates boundaries in file ${file.path}:${i + 1}\n'
                'Import found: $line',
              );
            }
          }
        }
      }
    });
  });
}
