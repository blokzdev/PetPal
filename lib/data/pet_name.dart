/// Defensive empty-name handling for pet-name interpolation sites.
///
/// Phase 5.5 on-device verification surfaced taglines reading
/// `PetPal remembers 's life so you don't have to.` and chat CTAs
/// reading `Chat with ` (orphaned apostrophe and trailing space)
/// when a pet's SOUL.md ended up with an empty `# {name}` header.
/// The structural fix for empty-name reaching the SOUL was Bug 1
/// (commit 718daa9). This helper is the belt-and-suspenders layer:
/// even if a future migration / corruption / edge case produces an
/// empty pet name, no surface should render with orphan punctuation.
///
/// Use [displayPetName] in user-facing UI surfaces (Title-Case
/// register). Use [displayPetNameLower] in inline harness prompts
/// (lowercase, matches the existing reminder_service fallback).
library;

/// User-facing fallback for an empty / null pet name. Title-cased
/// because the app surfaces (hero greeting, chat CTA, journal
/// title) all run in Title-Case register.
const String petNamePlaceholder = 'Your pet';

/// Lowercase fallback for harness / prompt-string sites that read
/// inline ("a memory-first companion for your pet"). Matches the
/// existing reminder_service.dart fallback so the harness layer
/// stays consistent with itself.
const String petNamePlaceholderLower = 'your pet';

/// Returns [raw] trimmed; falls back to [petNamePlaceholder]
/// (`Your pet`) when [raw] is null, empty, or whitespace-only.
/// Use in UI surfaces.
String displayPetName(String? raw) {
  if (raw == null) return petNamePlaceholder;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? petNamePlaceholder : trimmed;
}

/// Lowercase variant for inline harness prompts. Returns [raw]
/// trimmed; falls back to [petNamePlaceholderLower] (`your pet`).
String displayPetNameLower(String? raw) {
  if (raw == null) return petNamePlaceholderLower;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? petNamePlaceholderLower : trimmed;
}
