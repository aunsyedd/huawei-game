import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Everything that is drawn many times per frame is pre-rendered once into a
/// single texture atlas. Per-frame drawing is then one image blit per object,
/// and whole groups (splats, smoke, droplets, glows) go out in one
/// `drawRawAtlas` call. This is what keeps the frame rate high on phones.
class Sprites {
  Sprites._(this.skinColors);

  static Sprites? _instance;

  /// Builds the atlas once; [skins] are the unlockable player colours.
  static Sprites build({List<Color> skins = const []}) => _instance ??= Sprites._(skins).._build();
  static Sprites get instance => build();

  final List<Color> skinColors;

  late final Image atlas;

  // White sprites (tinted per draw).
  static const shadow = Rect.fromLTWH(0, 0, 64, 64);
  static const shadowOval = Rect.fromLTWH(64, 0, 64, 44);
  static const glow = Rect.fromLTWH(128, 0, 64, 64);
  static const sphere = Rect.fromLTWH(192, 0, 64, 64);
  static List<Rect> splats = [for (var i = 0; i < 4; i++) Rect.fromLTWH(256 + 64.0 * i, 0, 64, 64)];
  static const dot = Rect.fromLTWH(512, 0, 16, 16);
  static const leaf = Rect.fromLTWH(528, 0, 32, 16);
  static const puff = Rect.fromLTWH(576, 0, 128, 80);
  static const cube = Rect.fromLTWH(832, 0, 48, 48);

  // Coloured sprites.
  static const rock = Rect.fromLTWH(704, 0, 64, 48);
  static const palmCrown = Rect.fromLTWH(0, 96, 128, 128);
  static const canopy = Rect.fromLTWH(128, 96, 128, 128);
  static const sapling = Rect.fromLTWH(768, 0, 64, 64);

  /// One shaded body per actor colour (index from [bodyColors]).
  static Rect body(int i) => Rect.fromLTWH(256 + 64.0 * i, 96, 64, 64);

  /// Loot badge icons, see [lootIcon].
  static Rect loot(int i) => Rect.fromLTWH(48.0 * i, 240, 48, 48);

  /// Player skin bodies (index into the skins in progression.json).
  static Rect skin(int i) => Rect.fromLTWH(64.0 * i, 300, 64, 64);

  static const bodyColors = [
    Color(0xFF29B6F6), // player
    Color(0xFFEF5350), Color(0xFFAB47BC), Color(0xFF5C6BC0), Color(0xFF26A69A),
    Color(0xFFFFA726), Color(0xFF8D6E63), Color(0xFFEC407A), Color(0xFF78909C),
  ];

  static const lootColors = [
    Color(0xFF4FC3F7), // 0 splash pistol
    Color(0xFF7E57C2), // 1 soaker rifle
    Color(0xFFFF7043), // 2 bubble launcher
    Color(0xFF64B5F6), // 3 light vest
    Color(0xFF1565C0), // 4 heavy vest
    Color(0xFF29B6F6), // 5 water
    Color(0xFFB0BEC5), // 6 mask
    Color(0xFF43A047), // 7 seed
  ];

  void _build() {
    final rec = PictureRecorder();
    final c = Canvas(rec);
    _soft(c, shadow, const Color(0x99000000));
    _softOval(c, shadowOval, const Color(0x99000000));
    _radial(c, glow, [const Color(0xFFFFFFFF), const Color(0x66FFFFFF), const Color(0x00FFFFFF)], [0, 0.35, 1]);
    _sphere(c, sphere);
    for (var i = 0; i < 4; i++) {
      _splat(c, splats[i], i);
    }
    c.drawCircle(dot.center, 7, Paint()..color = const Color(0xFFFFFFFF));
    c.drawOval(leaf.deflate(1), Paint()..color = const Color(0xFFFFFFFF));
    _puff(c, puff);
    _cube(c, cube);
    _rock(c, rock);
    _palm(c, palmCrown);
    _canopy(c, canopy, const Color(0xFF1B5E20), const Color(0xFF2E7D32), const Color(0xFF66BB6A));
    _canopy(c, sapling, const Color(0xFF2E7D32), const Color(0xFF43A047), const Color(0xFF9CCC65));
    for (var i = 0; i < bodyColors.length; i++) {
      _body(c, body(i), bodyColors[i], player: i == 0);
    }
    for (var i = 0; i < skinColors.length && i < 16; i++) {
      _body(c, skin(i), skinColors[i], player: true);
    }
    for (var i = 0; i < lootColors.length; i++) {
      _loot(c, loot(i), i);
    }
    atlas = rec.endRecording().toImageSync(1024, 384);
  }

  // ------------------------------------------------------------------ painters

  void _soft(Canvas c, Rect r, Color color) => _radial(c, r, [color, color.withValues(alpha: 0)], [0, 1]);

  void _radial(Canvas c, Rect r, List<Color> colors, List<double> stops) {
    c.drawOval(r, Paint()..shader = Gradient.radial(r.center, r.shortestSide / 2, colors, stops));
  }

  void _softOval(Canvas c, Rect r, Color color) {
    c.save();
    c.translate(r.center.dx, r.center.dy);
    c.scale(1, r.height / r.width);
    final rr = r.width / 2;
    c.drawCircle(
      Offset.zero,
      rr,
      Paint()..shader = Gradient.radial(Offset.zero, rr, [color, color.withValues(alpha: 0)]),
    );
    c.restore();
  }

  void _sphere(Canvas c, Rect r) {
    final o = r.center, rad = r.width / 2;
    c.drawCircle(
      o,
      rad,
      Paint()
        ..shader = Gradient.radial(
          o.translate(-rad * 0.25, -rad * 0.3),
          rad * 1.25,
          [const Color(0x00000000), const Color(0x00000000), const Color(0x55000000)],
          [0, 0.55, 1],
        ),
    );
    final h = o.translate(-rad * 0.32, -rad * 0.36);
    c.drawCircle(
      h,
      rad * 0.42,
      Paint()..shader = Gradient.radial(h, rad * 0.42, [const Color(0x88FFFFFF), const Color(0x00FFFFFF)]),
    );
  }

  void _splat(Canvas c, Rect r, int seed) {
    final rng = math.Random(seed * 31 + 7);
    final p = Paint()..color = const Color(0xFFFFFFFF);
    final o = r.center, s = r.width;
    c.save();
    c.clipRect(r);
    c.drawCircle(o, s * 0.22, p);
    final blobs = 6 + rng.nextInt(4);
    for (var i = 0; i < blobs; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final d = s * (0.12 + rng.nextDouble() * 0.2);
      c.drawCircle(o.translate(math.cos(a) * d, math.sin(a) * d), s * (0.07 + rng.nextDouble() * 0.09), p);
      if (rng.nextBool()) {
        final d2 = s * (0.34 + rng.nextDouble() * 0.1);
        c.drawCircle(o.translate(math.cos(a) * d2, math.sin(a) * d2), s * (0.02 + rng.nextDouble() * 0.03), p);
      }
    }
    c.restore();
  }

  void _puff(Canvas c, Rect r) {
    final rng = math.Random(3);
    c.save();
    c.clipRect(r);
    for (var i = 0; i < 8; i++) {
      final cx = r.left + r.width * (0.25 + rng.nextDouble() * 0.5);
      final cy = r.top + r.height * (0.3 + rng.nextDouble() * 0.4);
      final rad = r.height * (0.22 + rng.nextDouble() * 0.16);
      c.drawCircle(
        Offset(cx, cy),
        rad,
        Paint()..shader = Gradient.radial(Offset(cx, cy), rad, [const Color(0x55FFFFFF), const Color(0x00FFFFFF)]),
      );
    }
    c.restore();
  }

  /// A small isometric cube, tinted per draw (mined-block debris).
  void _cube(Canvas c, Rect r) {
    final o = r.center, s = r.width * 0.3;
    final p = Paint()..color = const Color(0xFFFFFFFF);
    Path face(List<Offset> pts) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (final q in pts.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      return path..close();
    }

    final top = [
      o.translate(0, -s),
      o.translate(s, -s * 0.5),
      o.translate(0, 0),
      o.translate(-s, -s * 0.5),
    ];
    final left = [o.translate(-s, -s * 0.5), o.translate(0, 0), o.translate(0, s), o.translate(-s, s * 0.5)];
    final right = [o.translate(s, -s * 0.5), o.translate(0, 0), o.translate(0, s), o.translate(s, s * 0.5)];
    c.drawPath(face(top), p);
    c.drawPath(face(left), Paint()..color = const Color(0xFFB4B4B4));
    c.drawPath(face(right), Paint()..color = const Color(0xFF8C8C8C));
  }

  void _rock(Canvas c, Rect r) {
    final o = r.center;
    c.drawOval(
      Rect.fromCenter(center: o, width: r.width * 0.95, height: r.height * 0.85),
      Paint()..color = const Color(0xFF767E83),
    );
    c.drawOval(
      Rect.fromCenter(center: o.translate(-5, -5), width: r.width * 0.65, height: r.height * 0.5),
      Paint()..color = const Color(0xFF969EA3),
    );
    c.drawOval(
      Rect.fromCenter(center: o.translate(9, 9), width: r.width * 0.35, height: r.height * 0.18),
      Paint()..color = const Color(0x806E8C50),
    );
  }

  /// Top-down palm crown, pre-squashed for the camera tilt.
  void _palm(Canvas c, Rect r) {
    final o = r.center;
    c.save();
    c.translate(o.dx, o.dy);
    c.scale(1, 0.78);
    final len = r.width * 0.48;
    final path = Path();
    for (var k = 0; k < 7; k++) {
      final a = k * math.pi * 2 / 7;
      final tip = Offset(math.cos(a) * len, math.sin(a) * len);
      final n = Offset(-math.sin(a), math.cos(a)) * (len * 0.16);
      final mid = tip * 0.45;
      path
        ..reset()
        ..moveTo(0, 0)
        ..quadraticBezierTo(mid.dx + n.dx, mid.dy + n.dy, tip.dx, tip.dy)
        ..quadraticBezierTo(mid.dx - n.dx, mid.dy - n.dy, 0, 0);
      c.drawPath(path, Paint()..color = k.isEven ? const Color(0xFF2E7D32) : const Color(0xFF43A047));
      c.drawLine(
        Offset.zero,
        tip * 0.95,
        Paint()
          ..color = const Color(0x40000000)
          ..strokeWidth = 1.2,
      );
    }
    c.drawCircle(Offset.zero, len * 0.12, Paint()..color = const Color(0xFF6D4C41));
    c.drawCircle(const Offset(4, 3), len * 0.08, Paint()..color = const Color(0xFF8D6E63));
    c.restore();
  }

  void _canopy(Canvas c, Rect r, Color dark, Color mid, Color light) {
    final o = r.center, rad = r.width * 0.36;
    c.drawCircle(o.translate(rad * 0.25, rad * 0.2), rad * 0.9, Paint()..color = dark);
    c.drawCircle(o.translate(-rad * 0.35, rad * 0.1), rad * 0.75, Paint()..color = dark);
    c.drawCircle(o, rad * 0.95, Paint()..color = mid);
    c.drawCircle(o.translate(-rad * 0.3, -rad * 0.25), rad * 0.55, Paint()..color = light);
    _sphere(c, Rect.fromCircle(center: o, radius: rad * 1.05));
  }

  void _body(Canvas c, Rect r, Color color, {required bool player}) {
    final o = r.center, rad = r.width * 0.42;
    c.drawCircle(o, rad, Paint()..color = color);
    c.drawCircle(
      o.translate(0, -rad * 0.25),
      rad * 0.62,
      Paint()..color = Color.lerp(color, const Color(0xFF000000), 0.35)!,
    );
    _sphere(c, Rect.fromCircle(center: o, radius: rad));
    c.drawCircle(
      o,
      rad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = player ? 5 : 3
        ..color = player ? const Color(0xFFFFFFFF) : const Color(0x99000000),
    );
  }

  void _loot(Canvas c, Rect r, int kind) {
    final o = r.center, s = r.width / 48;
    final color = lootColors[kind];
    c.drawCircle(o, 20 * s, Paint()..color = const Color(0xF2FFFFFF));
    c.drawCircle(
      o,
      20 * s,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 * s
        ..color = color,
    );
    RRect box(double w, double h, double rad) =>
        RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: w * s, height: h * s), Radius.circular(rad * s));
    final p = Paint()..color = color;
    switch (kind) {
      case 0 || 1 || 2:
        c.drawRRect(box(26, 10, 4), p);
        c.drawCircle(
          o.translate(-5 * s, -6 * s),
          5 * s,
          Paint()..color = Color.lerp(color, const Color(0xFFFFFFFF), 0.5)!,
        );
      case 3 || 4:
        c.drawRRect(box(18, 21, 6), p);
        c.drawLine(
          o.translate(0, -8 * s),
          o.translate(0, 8 * s),
          Paint()
            ..color = const Color(0x66FFFFFF)
            ..strokeWidth = 2.5 * s,
        );
      case 5:
        c.drawRRect(box(11, 21, 4), p);
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: o.translate(0, -12 * s), width: 6 * s, height: 4 * s),
            Radius.circular(1.5 * s),
          ),
          Paint()..color = const Color(0xFF1565C0),
        );
      case 6:
        c.drawRRect(box(21, 13, 5), p);
      default:
        c.drawCircle(o.translate(0, 4 * s), 6.5 * s, Paint()..color = const Color(0xFF795548));
        c.drawOval(Rect.fromCenter(center: o.translate(4 * s, -5 * s), width: 13 * s, height: 8 * s), p);
        c.drawOval(
          Rect.fromCenter(center: o.translate(-4 * s, -4 * s), width: 9 * s, height: 5 * s),
          Paint()..color = const Color(0xFF81C784),
        );
    }
  }

  /// Atlas index for a loot item's icon.
  static int lootIcon(String refId) => switch (refId) {
    'splash_pistol' => 0,
    'soaker_rifle' => 1,
    'bubble_launcher' => 2,
    'vest_1' => 3,
    'vest_2' => 4,
    'water_bottle' => 5,
    'air_mask' => 6,
    _ => 7,
  };
}

/// Collects sprites from the atlas and draws them all in one call.
class AtlasBatch {
  AtlasBatch(this.capacity)
    : _xf = Float32List(capacity * 4),
      _rc = Float32List(capacity * 4),
      _cl = Int32List(capacity);

  final int capacity;
  final Float32List _xf, _rc;
  final Int32List _cl;
  int _n = 0;

  bool get isFull => _n >= capacity;

  /// Adds [src] centred at (cx, cy), scaled uniformly to [width], rotated by
  /// [rot] radians and tinted with [color] (white = untinted).
  void add(Rect src, double cx, double cy, double width, int color, [double rot = 0]) {
    if (_n >= capacity) return;
    final scale = width / src.width;
    final scos = rot == 0 ? scale : math.cos(rot) * scale;
    final ssin = rot == 0 ? 0.0 : math.sin(rot) * scale;
    final w = src.width / 2, h = src.height / 2;
    final i = _n * 4;
    _xf[i] = scos;
    _xf[i + 1] = ssin;
    _xf[i + 2] = cx - scos * w + ssin * h;
    _xf[i + 3] = cy - ssin * w - scos * h;
    _rc[i] = src.left;
    _rc[i + 1] = src.top;
    _rc[i + 2] = src.right;
    _rc[i + 3] = src.bottom;
    _cl[_n] = color;
    _n++;
  }

  void draw(Canvas canvas, Image atlas, Paint paint) {
    if (_n == 0) return;
    canvas.drawRawAtlas(
      atlas,
      Float32List.sublistView(_xf, 0, _n * 4),
      Float32List.sublistView(_rc, 0, _n * 4),
      Int32List.sublistView(_cl, 0, _n),
      BlendMode.modulate,
      null,
      paint,
    );
    _n = 0;
  }
}
