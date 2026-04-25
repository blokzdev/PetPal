import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/wiki_slug.dart';

void main() {
  group('slugify', () {
    test('lowercases and joins words with hyphens', () {
      expect(slugify('Milo Vet Visit'), 'milo-vet-visit');
    });

    test('strips apostrophes and other punctuation', () {
      expect(slugify("Milo's vet visit!"), 'milos-vet-visit');
    });

    test('collapses whitespace runs to a single hyphen', () {
      expect(slugify('  multiple   spaces \t\nhere  '), 'multiple-spaces-here');
    });

    test('preserves unicode letters and digits', () {
      expect(slugify('héllo wörld 2026'), 'héllo-wörld-2026');
    });

    test('trims leading and trailing hyphens after stripping', () {
      expect(slugify('---hello---'), 'hello');
      expect(slugify('!!!boom!!!'), 'boom');
    });

    test('truncates to maxLength and re-trims hanging hyphen', () {
      final s = slugify('a' * 80);
      expect(s.length, 64);
      expect(slugify('a-very-long-title-' * 10, maxLength: 20).endsWith('-'),
          isFalse);
    });

    test('returns "untitled" for inputs that reduce to empty', () {
      expect(slugify(''), 'untitled');
      expect(slugify('   '), 'untitled');
      expect(slugify('!!!'), 'untitled');
    });

    test('strips path-traversal characters defensively', () {
      expect(slugify('../etc/passwd'), 'etcpasswd');
      expect(slugify(r'C:\windows\system32'), 'cwindowssystem32');
    });
  });
}
