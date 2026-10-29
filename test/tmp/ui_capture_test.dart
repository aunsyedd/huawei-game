import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haze_royale/app/app.dart';
import 'package:haze_royale/app/router.dart';
import 'package:haze_royale/game/systems/match_manager.dart';
import 'package:haze_royale/services/hms/hms_services.dart';
import 'package:haze_royale/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../simulation_test.dart' show loadConfig;

/// Dev only: screenshots of the real screens with real fonts, for the user
/// guide and the pitch deck. Run with SHOT_DIR set.
const logical = Size(915, 412);
const dpr = 2.0;

Future<void> _loadFonts() async {
  // flutter_tester lives in <sdk>/bin/cache/artifacts/engine/<platform>/.
  final dir = '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts';
  // Styles with no family fall back to the test font, so Roboto stands in for that too.
  for (final family in ['Roboto', 'FlutterTest', 'Ahem']) {
    final roboto = FontLoader(family);
    for (final f in ['roboto-regular', 'roboto-medium', 'roboto-bold', 'roboto-black', 'roboto-italic']) {
      roboto.addFont(Future.value(ByteData.sublistView(File('$dir/$f.ttf').readAsBytesSync())));
    }
    await roboto.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('$dir/materialicons-regular.otf').readAsBytesSync())));
  await icons.load();
}

final _shotKey = GlobalKey();

Future<void> _shot(WidgetTester tester, String path) async {
  await tester.runAsync(() async {
    final boundary = _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: dpr);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _frames(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 33));
  }
}

void main() {
  final out = Platform.environment['SHOT_DIR'];

  for (final lang in ['en', 'ms']) {
    for (final route in ['/', '/lobby', '/guide', '/story', '/settings', '/leaderboard', '/results', '/game', '/craft']) {
      testWidgets('capture $route $lang', (tester) async {
        if (out == null) return;
        await tester.runAsync(_loadFonts);
        tester.view.physicalSize = logical * dpr;
        tester.view.devicePixelRatio = dpr;
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
          final sim = MatchSimulation(config, seed: 3, autopilotPlayer: true)..start(1500, 1500);
          while (sim.playerResult == null) {
            sim.update(1 / 30);
          }
          final summary = await container.read(profileProvider.notifier).recordMatch(sim.playerResult!, config);
          container.read(lastMatchProvider.notifier).set(summary);
        }

        await tester.pumpWidget(
          RepaintBoundary(
            key: _shotKey,
            child: UncontrolledProviderScope(container: container, child: const HazeRoyaleApp()),
          ),
        );
        appRouter.go(route);
        await _frames(tester, 20);
        final name = route == '/' ? 'menu' : route.substring(1);
        if (route == '/game' || route == '/craft') {
          await _shot(tester, '$out/${name}_drop_$lang.png');
          await tester.tap(find.byIcon(Icons.paragliding));
          await _frames(tester, 150);
        }
        await _shot(tester, '$out/${name}_$lang.png');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }
}
