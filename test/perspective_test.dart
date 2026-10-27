import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haze_royale/game/haze_royale_game.dart';
import 'package:haze_royale/game/render/camera3d.dart';
import 'package:haze_royale/services/feedback_service.dart';

import 'simulation_test.dart' show loadConfig;

void main() {
  test('3D camera: unproject inverts project on the ground plane', () {
    final game = HazeRoyaleGame(config: loadConfig(), lang: 'en', feedback: FeedbackService(hapticsEnabled: false))
      ..onGameResize(Vector2(812, 375));
    final r = game.renderer..setCamera(1500, 1500);

    expect(r.project(1500, 1500, 0), isTrue);
    expect(r.projected.dx, closeTo(406, 0.01));
    expect(r.projected.dy, closeTo(375 * 0.6, 0.01));

    for (final (x, y) in [(1300.0, 1350.0), (1800.0, 1650.0), (1500.0, 1200.0)]) {
      expect(r.project(x, y, 0), isTrue);
      final (wx, wy) = r.unproject(r.projected.dx, r.projected.dy);
      expect(wx, closeTo(x, 0.5));
      expect(wy, closeTo(y, 0.5));
    }

    // Taller things appear higher on screen.
    r.project(1500, 1500, 0);
    final ground = r.projected.dy;
    r.project(1500, 1500, 80);
    expect(r.projected.dy, lessThan(ground));
  });

  test('the camera can be turned and tilted and still inverts correctly', () {
    final game = HazeRoyaleGame(config: loadConfig(), lang: 'en', feedback: FeedbackService(hapticsEnabled: false))
      ..onGameResize(Vector2(812, 375));
    final r = game.renderer;

    for (final yaw in [0.0, 0.9, -2.3, 3.0]) {
      for (final tilt in [Camera3D.minTilt, Camera3D.defaultTilt, Camera3D.maxTilt]) {
        game
          ..camYaw = yaw
          ..camTilt = tilt;
        r.setCamera(1500, 1500);

        // The look-at point always lands on the same spot on screen.
        expect(r.project(1500, 1500, 0), isTrue);
        expect(r.projected.dx, closeTo(406, 0.01));
        expect(r.projected.dy, closeTo(375 * 0.6, 0.01));

        for (final (x, y) in [(1300.0, 1350.0), (1800.0, 1650.0), (1500.0, 1200.0)]) {
          expect(r.project(x, y, 0), isTrue);
          final (wx, wy) = r.unproject(r.projected.dx, r.projected.dy);
          expect(wx, closeTo(x, 0.5), reason: 'yaw $yaw tilt $tilt');
          expect(wy, closeTo(y, 0.5), reason: 'yaw $yaw tilt $tilt');
        }

        // Walking "north" is always up the screen, whichever way we face.
        final ahead = (1500 + math.sin(yaw) * 300, 1500 - math.cos(yaw) * 300);
        r.project(1500, 1500, 0);
        final here = r.projected.dy;
        expect(r.project(ahead.$1, ahead.$2, 0), isTrue);
        expect(r.projected.dy, lessThan(here), reason: 'yaw $yaw tilt $tilt');
      }
    }
  });

  test('the horizon only comes into view at a low camera angle', () {
    final game = HazeRoyaleGame(config: loadConfig(), lang: 'en', feedback: FeedbackService(hapticsEnabled: false))
      ..onGameResize(Vector2(812, 375));
    game.camTilt = Camera3D.defaultTilt;
    game.renderer.setCamera(1500, 1500);
    expect(game.renderer.cam.horizonY, lessThan(0), reason: 'looking down: no horizon on screen');

    game.camTilt = Camera3D.maxTilt;
    game.renderer.setCamera(1500, 1500);
    final low = game.renderer.cam.horizonY;
    expect(low, greaterThan(game.renderer.cam.h0 - 375));
    expect(low, lessThan(375 * 0.6));
  });
}
