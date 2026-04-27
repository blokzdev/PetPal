/// Elevation tokens — semantic names mapped to Material 3 dp values.
/// Use the names, not the numbers, in component code so the visual
/// elevation pyramid stays editable in one place.
abstract final class Elevation {
  /// Surfaces flush with the background. Default for screens.
  static const double flat = 0;

  /// Default card elevation. Subtle separation from the background.
  static const double low = 1;

  /// Raised cards, dialogs at rest. Clearly above the surface.
  static const double medium = 3;

  /// Floating action buttons, tooltips, popovers. Strong separation.
  static const double high = 6;
}
