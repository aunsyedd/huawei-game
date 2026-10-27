import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haze_royale/game/haze_royale_game.dart';
import 'package:haze_royale/game/systems/match_manager.dart';
import 'package:haze_royale/services/feedback_service.dart';

import '../simulation_test.dart' show loadConfig;

const w = 1024, h = 480;

Future<void> shot(HazeRoyaleGame g, String path) async {
  final rec = PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, w * 1.0, h * 1.0), Paint()..color = g.backgroundColor());
  g.render(c);
  final img = await rec.endRecording().toImage(w, h);
  final png = await img.toByteData(format: ImageByteFormat.png);
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
}

void settle(HazeRoyaleGame g, int frames) {
  for (var i = 0; i < frames; i++) {
    g.update(1 / 60);
    if (i % 8 == 0) {
      final p = PictureRecorder();
      g.render(Canvas(p));
      p.endRecording().dispose();
    }
  }
}

void main() {
  testWidgets('capture frames', (tester) async {
    await tester.runAsync(() async {
      final out = Platform.environment['SHOT_DIR'];
      if (out == null) return; // dev-only: run with SHOT_DIR set to capture
      final cfg = loadConfig();

      // ---------------- Royale ----------------
      final g = HazeRoyaleGame(
        config: cfg,
        lang: 'en',
        feedback: FeedbackService(hapticsEnabled: false),
        seed: 5,
      )..onGameResize(Vector2(w * 1.0, h * 1.0));
      settle(g, 60);
      g.startMatch(2150, 1700);
      settle(g, 300);
      g.aimInput.setValues(1, 0.2);
      g.moveInput.setValues(0.3, 0.2);
      g.fireHeld = true;
      settle(g, 40);
      await shot(g, '$out/01_town.png');

      g.fireHeld = false;
      g.moveInput.setValues(-1, -0.6);
      settle(g, 140);
      g.moveInput.setValues(0, 0);
      await shot(g, '$out/02_plantation.png');

      // Turned camera.
      g.orbitCamera(160, 0);
      settle(g, 90);
      await shot(g, '$out/03_turned.png');

      // Low tilt: the horizon and sky should appear.
      for (var i = 0; i < 60; i++) {
        g.orbitCamera(0, 6);
        g.update(1 / 60);
      }
      settle(g, 60);
      await shot(g, '$out/04_horizon.png');

      settle(g, 60 * 120);
      await shot(g, '$out/05_late_haze.png');

      // ---------------- Blok Craft ----------------
      final c = HazeRoyaleGame(
        config: cfg,
        lang: 'en',
        feedback: FeedbackService(hapticsEnabled: false),
        mode: GameMode.craft,
        seed: 9,
      )..onGameResize(Vector2(w * 1.0, h * 1.0));
      settle(c, 60);
      c.startMatch(1500, 2200);
      settle(c, 60);
      final p = c.sim.player;
      // Build a little hut out of the starting planks and glass.
      final blocks = c.sim.blocks;
      final bx0 = blocks.gx(p.pos.x) + 2, by0 = blocks.gy(p.pos.y) - 1;
      final plank = cfg.blocks.indexOf['plank']!;
      final glass = cfg.blocks.indexOf['glass']!;
      final lamp = cfg.blocks.indexOf['lamp']!;
      final stone = cfg.blocks.indexOf['stone']!;
      for (var i = 0; i < 6; i++) {
        for (var j = 0; j < 5; j++) {
          final edge = i == 0 || j == 0 || i == 5 || j == 4;
          if (!edge) continue;
          final type = (i == 3 && j == 0) ? glass : plank;
          for (var z = 0; z < 3; z++) {
            blocks.set(bx0 + i, by0 + j, z, z == 2 ? stone : type);
          }
        }
      }
      blocks.set(bx0 + 2, by0 + 2, 0, lamp);
      // A staircase outside.
      for (var i = 0; i < 5; i++) {
        for (var z = 0; z <= i; z++) {
          blocks.set(bx0 - 2 - i, by0 + 2, z, stone);
        }
      }
      settle(c, 90);
      await shot(c, '$out/06_craft_build.png');

      // Mining the block in front of the player.
      p.aimAngle = 0;
      c.mineHeld = true;
      settle(c, 40);
      await shot(c, '$out/07_craft_mining.png');
      c.mineHeld = false;

      // Night, with the lantern lit.
      c.timeOfDay = 0.92;
      settle(c, 40);
      c.timeOfDay = 0.92;
      await shot(c, '$out/08_craft_night.png');

      // ---------------- perf ----------------
      for (final q in [3, 2, 0]) {
        final pg = HazeRoyaleGame(
          config: cfg,
          lang: 'en',
          feedback: FeedbackService(hapticsEnabled: false),
          graphics: q,
          seed: 5,
        )..onGameResize(Vector2(w * 1.0, h * 1.0));
        settle(pg, 60);
        pg.startMatch(2150, 1700);
        // Scatter a few hundred blocks around the player for a worst case.
        final b = pg.sim.blocks;
        final rng = math.Random(3);
        final cx = b.gx(pg.sim.player.pos.x), cy = b.gy(pg.sim.player.pos.y);
        for (var i = 0; i < 400; i++) {
          b.set(cx + rng.nextInt(24) - 12, cy + rng.nextInt(24) - 12, rng.nextInt(3), rng.nextInt(13));
        }
        settle(pg, 120);
        final sw = Stopwatch()..start();
        for (var i = 0; i < 200; i++) {
          pg.update(1 / 60);
          final pic = PictureRecorder();
          pg.render(Canvas(pic));
          pic.endRecording().dispose();
        }
        // ignore: avoid_print
        print('quality $q: ${(sw.elapsedMicroseconds / 200 / 1000).toStringAsFixed(2)} ms/frame CPU');
      }
    });
  });
}
