import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haze_royale/game/haze_royale_game.dart';
import 'package:haze_royale/services/feedback_service.dart';

import '../simulation_test.dart' show loadConfig;

void main() {
  testWidgets('frame cost breakdown', (tester) async {
    await tester.runAsync(() async {
      final cfg = loadConfig();
      for (final blocks in [0, 400]) {
        for (final q in [3, 2, 0]) {
          final g = HazeRoyaleGame(
            config: cfg,
            lang: 'en',
            feedback: FeedbackService(hapticsEnabled: false),
            graphics: q,
            seed: 5,
          )..onGameResize(Vector2(1024, 480));
          for (var i = 0; i < 60; i++) {
            g.update(1 / 60);
          }
          g.startMatch(2150, 1700);
          final b = g.sim.blocks;
          final rng = math.Random(3);
          final cx = b.gx(g.sim.player.pos.x), cy = b.gy(g.sim.player.pos.y);
          for (var i = 0; i < blocks; i++) {
            b.set(cx + rng.nextInt(24) - 12, cy + rng.nextInt(24) - 12, rng.nextInt(3), rng.nextInt(13));
          }
          for (var i = 0; i < 120; i++) {
            g.update(1 / 60);
            final p = PictureRecorder();
            g.render(Canvas(p));
            p.endRecording().dispose();
          }
          final su = Stopwatch()..start();
          for (var i = 0; i < 200; i++) {
            g.update(1 / 60);
          }
          su.stop();
          final sr = Stopwatch()..start();
          for (var i = 0; i < 200; i++) {
            final p = PictureRecorder();
            g.render(Canvas(p));
            p.endRecording().dispose();
          }
          sr.stop();
          // ignore: avoid_print
          print(
            'blocks $blocks quality $q: update ${(su.elapsedMicroseconds / 200 / 1000).toStringAsFixed(2)} ms, '
            'render ${(sr.elapsedMicroseconds / 200 / 1000).toStringAsFixed(2)} ms, '
            'tris ${g.renderer.lastTriangles}',
          );
        }
      }
    });
  });
}
