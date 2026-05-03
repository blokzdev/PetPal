import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/design.dart';
import 'pet_button.dart';
import 'pet_empty_state.dart';
import 'pet_skeleton.dart';

/// Shared layout chassis for every screen in `lib/app/screens/`.
///
/// Replaces the `Scaffold(appBar: AppBar(title: Text(...)), body:
/// SafeArea(...))` boilerplate that 9 screens repeated before task 5.5.
/// Three constructors:
///
/// - [AppScaffold] — the basic case. `AppScaffold(title: 'Settings',
///   body: ...)` is the common path.
/// - [AppScaffold.hero] — exposes a hero builder that renders a tall
///   surface immediately below the app bar, before the body. Used by
///   `home_screen` for the per-pet greeting (anticipating 5.10's hero
///   moment); Phase 6 will populate the hero with a per-pet photo +
///   warm gradient.
/// - [AppScaffold.async] — Riverpod-aware. Takes an [AsyncValue<T>] and
///   a `data` builder; default `loading` is a vertical stack of
///   [PetSkeleton.line] rows; default `error` is a [PetEmptyState] with
///   a retry button. Tasks 5.7 (empty states) and 5.8 (loading
///   feedback) consume this — most screens just swap their existing
///   `Scaffold(... asyncValue.when(...))` for `AppScaffold.async(...)`.
///
/// All variants accept an optional [petAccent] color. When supplied,
/// the AppBar background is blended 8% toward the accent — a subtle
/// tint that lets Phase 6's photo-driven per-pet palette pull through
/// without further screen edits. Phase 5 leaves [petAccent] null
/// everywhere; the threading exists so Phase 6 has somewhere to plug
/// the photo-derived accent into. Subtler than re-skinning the whole
/// app bar, intentionally.
///
/// SnackBars dispatch through [appSnackBar] (top-level helper at the
/// bottom of this file). The dispatch helper uses
/// [ScaffoldMessenger.of] and lets the design-system [SnackBarThemeData]
/// (DECISIONS row 38: floating, pill-shape, `Motion.medium` enter/exit)
/// do all the styling.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.petAccent,
    this.titleWidget,
  })  : _heroBuilder = null,
        _heroHeight = null;

  /// Hero variant — renders a tall surface immediately below the app
  /// bar, before the body. Used by home_screen for the per-pet greeting
  /// (5.10). The hero is a fixed-height region (default 120 dp); use
  /// [heroHeight] to override.
  const AppScaffold.hero({
    super.key,
    required this.title,
    required Widget Function(BuildContext) heroBuilder,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.petAccent,
    this.titleWidget,
    double heroHeight = 120,
  })  : _heroBuilder = heroBuilder,
        _heroHeight = heroHeight;

  /// Riverpod-aware variant. Renders the body through
  /// [AsyncValue.when], with [PetSkeleton]-backed loading and
  /// [PetEmptyState]-backed error rendering as defaults.
  ///
  /// `data` is required. `loading`, `error`, and `onRetry` are optional
  /// — the defaults are usually correct.
  static Widget async<T>({
    Key? key,
    required String title,
    required AsyncValue<T> value,
    required Widget Function(BuildContext, T) data,
    Widget Function(BuildContext)? loading,
    Widget Function(BuildContext, Object error, StackTrace? stack)? error,
    VoidCallback? onRetry,
    List<Widget>? actions,
    Widget? floatingActionButton,
    Color? petAccent,
    Widget? titleWidget,
  }) {
    return _AsyncAppScaffold<T>(
      key: key,
      title: title,
      value: value,
      dataBuilder: data,
      loadingBuilder: loading,
      errorBuilder: error,
      onRetry: onRetry,
      actions: actions,
      floatingActionButton: floatingActionButton,
      petAccent: petAccent,
      titleWidget: titleWidget,
    );
  }

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  /// Optional accent threaded from a pet (Phase 6: derived from the
  /// pet's photo). Phase 5 leaves this null on every callsite; the
  /// threading is a Phase 6 hook that doesn't require further screen
  /// edits when populated. When non-null, the app bar background is
  /// blended 8% toward [petAccent].
  final Color? petAccent;

  /// Override the default `Text(title)` with a custom widget — used by
  /// screens that want a serif title via [JournalText.title] or a
  /// multiline app-bar title.
  final Widget? titleWidget;

  final Widget Function(BuildContext)? _heroBuilder;
  final double? _heroHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appBarBackground = petAccent == null
        ? null
        : Color.lerp(scheme.surface, petAccent, 0.08);

    final hero = _heroBuilder;
    final body = hero == null
        ? this.body
        : Column(
            children: [
              SizedBox(
                height: _heroHeight,
                width: double.infinity,
                child: hero(context),
              ),
              Expanded(child: this.body),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: titleWidget ?? Text(title),
        actions: actions,
        backgroundColor: appBarBackground,
      ),
      body: SafeArea(child: body),
      floatingActionButton: floatingActionButton,
    );
  }
}

/// Internal implementation behind [AppScaffold.async]. Wraps an
/// [AppScaffold] whose body switches on [AsyncValue.when], with
/// design-system defaults for loading and error.
class _AsyncAppScaffold<T> extends StatelessWidget {
  const _AsyncAppScaffold({
    super.key,
    required this.title,
    required this.value,
    required this.dataBuilder,
    this.loadingBuilder,
    this.errorBuilder,
    this.onRetry,
    this.actions,
    this.floatingActionButton,
    this.petAccent,
    this.titleWidget,
  });

  final String title;
  final AsyncValue<T> value;
  final Widget Function(BuildContext, T) dataBuilder;
  final Widget Function(BuildContext)? loadingBuilder;
  final Widget Function(BuildContext, Object error, StackTrace? stack)?
      errorBuilder;
  final VoidCallback? onRetry;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Color? petAccent;
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: title,
      titleWidget: titleWidget,
      actions: actions,
      floatingActionButton: floatingActionButton,
      petAccent: petAccent,
      body: value.when(
        data: (d) => dataBuilder(context, d),
        loading: () => loadingBuilder?.call(context) ?? _defaultLoading(),
        error: (e, st) =>
            errorBuilder?.call(context, e, st) ?? _defaultError(context, e),
      ),
    );
  }

  /// Default loading: a stack of ListTile-shaped row skeletons —
  /// authentic preview of typical list geometry (icon + title + subtitle).
  /// Reads as "list incoming" without the visual weight of a centered
  /// spinner. List surfaces with non-default row shapes (e.g. reminders'
  /// trailing chip) override `loading:` with a shape-tuned variant.
  Widget _defaultLoading() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s),
      itemCount: 6,
      // Vary title/subtitle widths slightly so the stack reads as a
      // list of distinct items rather than a column of identical rows.
      itemBuilder: (_, i) => PetSkeletonListRow(
        titleWidth: 220 - (i.isEven ? 0 : 50).toDouble(),
        subtitleWidth: 140 - (i.isEven ? 30 : 0).toDouble(),
      ),
    );
  }

  /// Default error: a [PetEmptyState] with the underlying error message
  /// in the body and a retry CTA wired to [onRetry] (or a no-op when the
  /// caller didn't supply one — the empty state still reads as "the
  /// data didn't arrive" without the affordance to retry).
  Widget _defaultError(BuildContext context, Object error) {
    return PetEmptyState(
      icon: PhosphorIconsRegular.warningCircle,
      heading: "Couldn't load this",
      body: '$error',
      action: onRetry == null
          ? null
          : PetButton(label: 'Try again', onPressed: onRetry),
    );
  }
}

/// Top-level snackbar dispatcher. Consistent floating-snackbar
/// treatment across screens — the design-system [SnackBarThemeData]
/// styles the surface; this helper just keeps the dispatch site short.
///
/// Use `appSnackBar(context, 'Saved a memory about Loki')` instead of
/// `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: ...))`.
///
/// Phase 7 task H.2.b — every snackbar dispatched through this helper
/// also fires a `SemanticsService.announce` so TalkBack reads the
/// message aloud. Sighted users see the floating slab; screen-reader
/// users get the same message via the live region channel. Keeps the
/// 12+ existing call sites (chat, hub, settings, paywall, sync setup,
/// account-delete, …) accessible without per-site changes. Set
/// [announce] to false for snackbars whose message is purely visual
/// chrome already conveyed elsewhere in the tree.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> appSnackBar(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
  bool announce = true,
}) {
  if (announce) {
    // `Directionality.maybeOf` + LTR fallback guards against future
    // callers from a context without a Directionality ancestor (e.g.
    // a snackbar dispatched from a bare overlay or a unit-test
    // pumping outside MaterialApp). Every current call site sits
    // inside MaterialApp so the maybeOf path returns the inherited
    // direction; the fallback is purely defensive.
    SemanticsService.announce(
      message,
      Directionality.maybeOf(context) ?? TextDirection.ltr,
    );
  }
  return ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      action: action,
      duration: duration,
    ),
  );
}
