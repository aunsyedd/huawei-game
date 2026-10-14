import 'dart:math' as math;
import 'dart:ui';

/// Soft shapes rendered once at startup into small textures, so per-frame
/// drawing is a cheap image blit instead of gradients or blurs.
/// White sprites are tinted at draw time with [Sprites.tint].
class Sprites {
  Sprites._();

  static Sprites? _instance;
  static Sprites get instance => _instance ??= Sprites._().._build();

  late final Image softShadow; // black radial falloff
  late final Image glow; // white radial falloff (tint + additive blend)
  late final Image puff; // soft cloud (tinted smoke / dust)
  late final Image sphere; // highlight + rim shading laid over a coloured disc
  late final List<Image> splats; // white paint splat shapes

  static const int _size = 64;

  final Map<int, ColorFilter> _tints = {};

  /// Colour filter that turns a white sprite into [c] (alpha preserved).
  ColorFilter tint(Color c) => _tints[c.toARGB32()] ??= ColorFilter.mode(c, BlendMode.modulate);

  void _build() {
    softShadow = _radial([const Color(0x99000000), const Color(0x00000000)], [0.0, 1.0]);
    glow = _radial([const Color(0xFFFFFFFF), const Color(0x66FFFFFF), const Color(0x00FFFFFF)], [0.0, 0.35, 1.0]);
    puff = _render((c, s) {
      final rng = math.Random(3);
      for (var i = 0; i < 7; i++) {
        final cx = s * (0.3 + rng.nextDouble() * 0.4), cy = s * (0.3 + rng.nextDouble() * 0.4);
        final r = s * (0.18 + rng.nextDouble() * 0.16);
        c.drawCircle(
          Offset(cx, cy),
          r,
          Paint()..shader = Gradient.radial(Offset(cx, cy), r, [const Color(0x55FFFFFF), const Color(0x00FFFFFF)]),
        );
      }
    });
    sphere = _render((c, s) {
      final o = Offset(s / 2, s / 2);
      final r = s / 2;
      // Dark rim towards the bottom-right, bright spot top-left.
      c.drawCircle(
        o,
        r,
        Paint()
          ..shader = Gradient.radial(
            o.translate(-r * 0.25, -r * 0.3),
            r * 1.25,
            [const Color(0x00000000), const Color(0x00000000), const Color(0x55000000)],
            [0.0, 0.55, 1.0],
          ),
      );
      c.drawCircle(
        o.translate(-r * 0.32, -r * 0.36),
        r * 0.42,
        Paint()
          ..shader = Gradient.radial(o.translate(-r * 0.32, -r * 0.36), r * 0.42, [
            const Color(0x88FFFFFF),
            const Color(0x00FFFFFF),
          ]),
      );
    });
    splats = [for (var v = 0; v < 4; v++) _splat(v)];
  }

  Image _radial(List<Color> colors, List<double> stops) => _render((c, s) {
    final o = Offset(s / 2, s / 2);
    c.drawCircle(o, s / 2, Paint()..shader = Gradient.radial(o, s / 2, colors, stops));
  });

  Image _splat(int seed) => _render((c, s) {
    final rng = math.Random(seed * 31 + 7);
    final p = Paint()..color = const Color(0xFFFFFFFF);
    final o = Offset(s / 2, s / 2);
    c.drawCircle(o, s * 0.22, p);
    final blobs = 6 + rng.nextInt(4);
    for (var i = 0; i < blobs; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final d = s * (0.12 + rng.nextDouble() * 0.2);
      c.drawCircle(o.translate(math.cos(a) * d, math.sin(a) * d), s * (0.07 + rng.nextDouble() * 0.09), p);
      // A few flung droplets further out.
      if (rng.nextBool()) {
        final d2 = s * (0.34 + rng.nextDouble() * 0.12);
        c.drawCircle(o.translate(math.cos(a) * d2, math.sin(a) * d2), s * (0.02 + rng.nextDouble() * 0.03), p);
      }
    }
  });

  Image _render(void Function(Canvas c, double size) paint) {
    final rec = PictureRecorder();
    final c = Canvas(rec);
    paint(c, _size.toDouble());
    return rec.endRecording().toImageSync(_size, _size);
  }

  static final Rect src = Rect.fromLTWH(0, 0, _size.toDouble(), _size.toDouble());
}
