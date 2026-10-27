import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:haze_royale/app/app.dart';
import 'package:haze_royale/app/router.dart';
import 'package:haze_royale/game/systems/match_manager.dart';
import 'package:haze_royale/services/hms/hms_services.dart';
import 'package:haze_royale/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'simulation_test.dart' show loadConfig;

/// Landscape sizes (logical px) from a small budget phone up to tablets.
const sizes = <String, Size>{
  'small phone 640x360': Size(640, 360),
  'phone 740x360': Size(740, 360),
  'notch phone 812x375': Size(812, 375),
  'large phone 915x412': Size(915, 412),
  'tablet 1024x768': Size(1024, 768),
  'tablet 1280x800': Size(1280, 800),
};

Future<ProviderContainer> pumpApp(WidgetTester tester, Size size, String route, {String lang = 'en'}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  // Simulate a notch on the left like many Android phones in landscape.
  tester.view.padding = const FakeViewPadding(left: 32);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({'language': lang, 'tutorial_done': true, 'story_seen': true});
  final prefs = await SharedPreferences.getInstance();
  final config = loadConfig();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      hmsServicesProvider.overrideWithValue(HmsServices.create(hmsAvailable: false, prefs: prefs)),
      gameConfigProvider.overrideWith((ref) async => config),
    ],
  );
  addTearDown(container.dispose);

  if (route == '/results') {
    final sim = MatchSimulation(config, seed: 1, autopilotPlayer: true)..start(1500, 1500);
    while (sim.playerResult == null) {
      sim.update(1 / 30);
    }
    final summary = await container.read(profileProvider.notifier).recordMatch(sim.playerResult!, config);
    container.read(lastMatchProvider.notifier).set(summary);
  }

  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const HazeRoyaleApp()));
  appRouter.go(route);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

void main() {
  for (final route in ['/', '/lobby', '/results', '/leaderboard', '/settings', '/story', '/guide', '/game', '/craft']) {
    for (final e in sizes.entries) {
      for (final lang in ['en', 'ms']) {
        testWidgets('$route fits on ${e.key} ($lang)', (tester) async {
          await pumpApp(tester, e.value, route, lang: lang);
          if (route == '/game' || route == '/craft') {
            // Land, then let the HUD, sticks and action buttons lay out mid-match.
            await tester.tap(find.byIcon(Icons.paragliding));
            for (var i = 0; i < 20; i++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
            expect(find.byIcon(Icons.park), findsWidgets, reason: 'plant button visible');
          }
          // Any RenderFlex overflow is reported by the framework and fails the test.
          // Unmount, then let pending timers (lobby / drop countdowns) run out.
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 2));
        });
      }
    }
  }

  testWidgets('portrait shows the rotate-your-phone message', (tester) async {
    await pumpApp(tester, const Size(390, 844), '/');
    expect(find.byIcon(Icons.screen_rotation), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  test('router has every screen', () {
    expect(
      appRouter.configuration.routes.whereType<GoRoute>().map((r) => r.path),
      containsAll(['/', '/lobby', '/game', '/craft', '/results', '/leaderboard', '/settings', '/story', '/guide']),
    );
  });
}
