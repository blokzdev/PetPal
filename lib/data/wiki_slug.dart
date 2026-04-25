/// Convert an entry title to a filesystem-safe slug.
///
/// Lowercases, keeps unicode letters and digits, collapses whitespace runs to
/// single hyphens, strips everything else, trims leading/trailing hyphens, and
/// caps length. Returns `untitled` for inputs that reduce to empty.
String slugify(String input, {int maxLength = 64}) {
  var s = input.toLowerCase().trim();
  s = s.replaceAll(RegExp(r'[^\p{L}\p{N}\s-]+', unicode: true), '');
  s = s.replaceAll(RegExp(r'\s+'), '-');
  s = s.replaceAll(RegExp(r'-+'), '-');
  s = s.replaceAll(RegExp(r'^-+|-+$'), '');
  if (s.length > maxLength) s = s.substring(0, maxLength);
  s = s.replaceAll(RegExp(r'-+$'), '');
  if (s.isEmpty) return 'untitled';
  return s;
}
