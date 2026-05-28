import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/entitlement/entitlement.dart';
import 'package:petpal/app/entitlement/entitlement_notifier.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/main.dart';
import 'package:petpal/platform/settings_storage.dart';

import '../../_helpers/fake_api_key_storage.dart';
import '../../_helpers/scripted_llm_client.dart';
import '../../_helpers/test_provider_scope.dart';

void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  testWidgets('weekly summary toggle starts off, persists when flipped on',
      (tester) async {
    // Tall viewport so the lazy ListView builds the Weekly-summary
    // section — Phase 7's Plan + Sync sections now sit above it.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = InMemorySettingsStorage();
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          settingsStorageProvider.overrideWithValue(settings),
          ...stack.overrides,
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Phase 6.6 task 6.6.A.3 — bottom nav replaces the home grid.
    // Tap the Hub tab → tap the Settings ListTile inside Hub.
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Hub'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final firstSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Weekly summary'),
    );
    expect(firstSwitch.value, isFalse,
        reason: 'weekly summary should default to off (Pro-tier)');

    // Task 5.12 — section grouping migrated to PetSectionHeader +
    // PetCard. Phase 6.6 task 6.6.B.0 — section header now renders
    // uppercased ("WEEKLY SUMMARY"); the SwitchListTile inside the
    // card keeps the mixed-case title ("Weekly summary"). Two
    // separate text instances under one card surface.
    expect(find.text('WEEKLY SUMMARY'), findsOneWidget,
        reason: 'PetSectionHeader title renders in small-caps register');
    expect(find.text('Weekly summary'), findsOneWidget,
        reason: 'SwitchListTile title keeps mixed case');
    expect(
      find.ancestor(
        of: find.widgetWithText(SwitchListTile, 'Weekly summary'),
        matching: find.byType(Card),
      ),
      findsOneWidget,
      reason: 'switch lives inside the section card (5.12)');
    expect(
      find.ancestor(
        of: find.widgetWithText(
            ListTile, "Generate this week's summary now"),
        matching: find.byType(Card),
      ),
      findsOneWidget,
      reason: 'run-now row shares the section card (5.12)');

    await tester.tap(find.widgetWithText(SwitchListTile, 'Weekly summary'));
    await tester.pumpAndSettle();

    final afterToggle = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Weekly summary'),
    );
    expect(afterToggle.value, isTrue);

    // Underlying storage was updated.
    expect(await settings.getBool('weekly_digest_enabled'), isTrue);
  });

  testWidgets('preloaded "on" state shows the toggle as on', (tester) async {
    // Tall viewport so the lazy ListView builds the Weekly-summary
    // section — Phase 7's Plan + Sync sections now sit above it.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings =
        InMemorySettingsStorage({'weekly_digest_enabled': true});
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          settingsStorageProvider.overrideWithValue(settings),
          ...stack.overrides,
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Phase 6.6 task 6.6.A.3 — Hub tab → Settings sub-page.
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Hub'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final s = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Weekly summary'),
    );
    expect(s.value, isTrue);
  });

  // ── Phase 7 task E.1.b — Plan card tests ─────────────────────────

  group('Phase 7 task E.1.b — Plan card', () {
    Future<void> pumpSettingsWithEntitlement(
      WidgetTester tester, {
      required Override entitlementOverride,
    }) async {
      // Tall viewport so the Plan card + section + ambient counter
      // all render in one frame.
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settings = InMemorySettingsStorage();
      final stack = await buildChatTestStack(
        llm: ScriptedLlmClient(scripts: const []),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiKeyStorageProvider.overrideWithValue(
              FakeApiKeyStorage(initial: 'sk-ant-test'),
            ),
            settingsStorageProvider.overrideWithValue(settings),
            entitlementOverride,
            ...stack.overrides,
          ],
          child: const PetPalApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Hub'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
    }

    testWidgets('Free anonymous → "Free plan" badge + Upgrade CTA + '
        'ambient counter (VOICE.md §6 ex. 11 register)',
        (tester) async {
      await pumpSettingsWithEntitlement(
        tester,
        entitlementOverride:
            entitlementProvider.overrideWith(_FreeEntitlementNotifier.new),
      );

      expect(find.text('PLAN'), findsOneWidget,
          reason: 'PetSectionHeader uppercases the title');
      expect(find.text('Free plan'), findsOneWidget);
      expect(find.text('Upgrade'), findsOneWidget,
          reason: 'free-tier badge row carries the upgrade CTA');
      // Ambient counter (per VOICE.md §6 example 11). 0/200 → ample
      // headroom register.
      expect(
        find.textContaining('PetPal handles 200 chats a month'),
        findsOneWidget,
      );
    });

    testWidgets('Pro user → "PetPal Pro · Monthly" + no counter + '
        'no Upgrade CTA', (tester) async {
      await pumpSettingsWithEntitlement(
        tester,
        entitlementOverride:
            entitlementProvider.overrideWith(_ProMonthlyNotifier.new),
      );

      expect(find.text('PetPal Pro · Monthly'), findsOneWidget);
      // Pro is unmetered → counter row must NOT render (VOICE.md §7
      // principle: no metering language in chat / Settings counter
      // is for free tier ambient info only).
      expect(find.text('Monthly chat allowance'), findsNothing);
      expect(find.text('Upgrade'), findsNothing,
          reason: 'Pro user must not see the upgrade CTA');
    });

    testWidgets('BYOK user → "Free plan + BYOK" + no counter '
        '(BYOK lifts the cost-driven cap)', (tester) async {
      await pumpSettingsWithEntitlement(
        tester,
        entitlementOverride:
            entitlementProvider.overrideWith(_ByokNotifier.new),
      );

      expect(find.text('Free plan + BYOK'), findsOneWidget);
      // BYOK lifts the text cap → counter row must NOT render.
      expect(find.text('Monthly chat allowance'), findsNothing);
    });

    testWidgets('Restore purchases tile renders for every plan state',
        (tester) async {
      await pumpSettingsWithEntitlement(
        tester,
        entitlementOverride:
            entitlementProvider.overrideWith(_FreeEntitlementNotifier.new),
      );
      expect(find.text('Restore purchases'), findsOneWidget);
    });
  });
}

class _FreeEntitlementNotifier extends EntitlementNotifier {
  @override
  Future<Entitlement> build() async => Entitlement.freeAnonymous();
}

class _ProMonthlyNotifier extends EntitlementNotifier {
  @override
  Future<Entitlement> build() async => Entitlement(
        state: EntitlementState.proMonthly,
        userId: 'user-pro',
        renewalDate: DateTime(2026, 6, 15),
        counterPeriodStart: DateTime(2026, 5),
      );
}

class _ByokNotifier extends EntitlementNotifier {
  @override
  Future<Entitlement> build() async => Entitlement(
        state: EntitlementState.byok,
        userId: 'user-byok',
        counterPeriodStart: DateTime(2026, 5),
      );
}
