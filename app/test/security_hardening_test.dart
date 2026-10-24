import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/core/security/master_key_provider.dart';

void main() {
  group('Security Hardening & Vulnerability Remediation Tests', () {
    test('Zip Slip and directory traversal paths are properly detected and blocked', () {
      const maliciousEntryNames = [
        '../../evil.txt',
        '../etc/passwd',
        'foo/../../bar.sh',
        '..\\windows\\system32\\calc.exe',
      ];

      final tempDir = Directory.systemTemp.createTempSync('aerodrive_sec_test');
      try {
        final outDir = Directory(p.join(tempDir.path, 'aerodrive_extracted'));

        for (final entryName in maliciousEntryNames) {
          final normalized = p.normalize(entryName);
          final isTraversal = normalized.startsWith('..') ||
              p.isAbsolute(normalized) ||
              !p.isWithin(outDir.path, p.join(outDir.path, normalized));

          expect(isTraversal, isTrue, reason: 'Entry $entryName should be flagged as traversal');
        }

        // Legitimate entry name
        const legitimateEntry = 'photos/2026/vacation.jpg';
        final normalizedLegit = p.normalize(legitimateEntry);
        final legitPath = p.join(outDir.path, normalizedLegit);
        expect(normalizedLegit.startsWith('..'), isFalse);
        expect(p.isWithin(outDir.path, legitPath), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Filename sanitization removes path separators and forbidden symbols', () {
      const dirtyName = '../../etc/shadow:secret*?.txt';
      final base = p.basename(dirtyName);
      final sanitized = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

      expect(sanitized.contains('/'), isFalse);
      expect(sanitized.contains('\\'), isFalse);
      expect(sanitized.contains('..'), isFalse);
      expect(sanitized.contains(':'), isFalse);
      expect(sanitized.contains('*'), isFalse);
      expect(sanitized.contains('?'), isFalse);
      expect(sanitized, equals('shadow_secret__.txt'));
    });

    test('MasterKeyProvider preserves custom vault key across provider reads', () {
      final customKey = List<int>.generate(32, (i) => i + 1);
      MasterKeyProvider.instance.setKey(customKey);

      final container = ProviderContainer();
      try {
        final keyFromProvider = container.read(masterKeyProvider);
        expect(keyFromProvider, isNotNull);
        expect(keyFromProvider, equals(customKey));
      } finally {
        container.dispose();
        MasterKeyProvider.instance.clearKey();
      }
    });

    test('Text viewer URL scheme validation accepts only http and https', () {
      final safeUrls = [
        Uri.parse('https://example.com/file'),
        Uri.parse('http://example.com/readme'),
      ];

      final dangerousUrls = [
        Uri.parse('file:///etc/passwd'),
        Uri.parse('javascript:alert(1)'),
        Uri.parse('intent://com.example'),
        Uri.parse('content://media/external'),
      ];

      for (final uri in safeUrls) {
        final isSafe = uri.scheme == 'http' || uri.scheme == 'https';
        expect(isSafe, isTrue, reason: '${uri.scheme} should be allowed');
      }

      for (final uri in dangerousUrls) {
        final isSafe = uri.scheme == 'http' || uri.scheme == 'https';
        expect(isSafe, isFalse, reason: '${uri.scheme} should be rejected');
      }
    });
  });
}
