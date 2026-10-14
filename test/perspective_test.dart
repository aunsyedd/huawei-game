import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haze_royale/game/haze_royale_game.dart';
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
}
