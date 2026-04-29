import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/pet_name.dart';

/// Bug-2 fixture for the displayPetName / displayPetNameLower
/// helpers. These guard every UI and harness pet-name interpolation
/// site against orphan punctuation when a pet's name is empty,
/// whitespace-only, or null.
void main() {
  group('displayPetName (Title-Case UI fallback)', () {
    test('null -> "Your pet"', () {
      expect(displayPetName(null), 'Your pet');
    });
    test('empty string -> "Your pet"', () {
      expect(displayPetName(''), 'Your pet');
    });
    test('whitespace-only -> "Your pet"', () {
      expect(displayPetName('   '), 'Your pet');
      expect(displayPetName('\t'), 'Your pet');
      expect(displayPetName('\n'), 'Your pet');
    });
    test('non-empty name passes through trimmed', () {
      expect(displayPetName('Loki'), 'Loki');
      expect(displayPetName('  Loki  '), 'Loki');
    });
    test('placeholder constant matches the Title-Case fallback', () {
      expect(petNamePlaceholder, 'Your pet');
    });
  });

  group('displayPetNameLower (harness/prompt fallback)', () {
    test('null -> "your pet"', () {
      expect(displayPetNameLower(null), 'your pet');
    });
    test('empty / whitespace -> "your pet"', () {
      expect(displayPetNameLower(''), 'your pet');
      expect(displayPetNameLower('  '), 'your pet');
    });
    test('non-empty name passes through trimmed', () {
      expect(displayPetNameLower('Loki'), 'Loki');
      expect(displayPetNameLower('  Loki  '), 'Loki');
    });
    test('placeholder constant matches the lowercase fallback', () {
      expect(petNamePlaceholderLower, 'your pet');
    });
  });

  group('possessive interpolation regression cases', () {
    // The user-reported Bug 2 surfaces are interpolations that read
    // either possessively ("$name's life", "$name's journal") or
    // adjacently ("Chat with $name", "memory-first companion for
    // $name"). With the helper installed, neither shape can produce
    // orphan punctuation or trailing spaces.
    test('possessive: empty name yields "Your pet\'s life"', () {
      final n = displayPetName('');
      expect("PetPal remembers $n's life so you don't have to.",
          "PetPal remembers Your pet's life so you don't have to.");
    });
    test('adjacent: empty name yields "Chat with Your pet"', () {
      final n = displayPetName('');
      expect('Chat with $n', 'Chat with Your pet');
    });
    test('harness inline: empty name yields lowercase phrasing', () {
      final n = displayPetNameLower('');
      expect('a memory-first companion for $n.',
          'a memory-first companion for your pet.');
    });
  });
}
