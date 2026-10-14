import 'package:flutter/material.dart';

abstract final class AppColors {
  static const leaf = Color(0xFF43A047);
  static const haze = Color(0xFFBF7A3A);
  static const night = Color(0xFF0D1B2A);
  static const panel = Color(0xFF16283A);
  static const sky = Color(0xFF29B6F6);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.leaf, brightness: Brightness.dark, surface: AppColors.panel);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.night,
    useMaterial3: true,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

/// Shared backdrop for menu screens: dusky sky with a haze band and palms.
class HazeBackground extends StatelessWidget {
  const HazeBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1B2A), Color(0xFF3B3A3F), Color(0xFF8C6A45)],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _PalmsPainter())),
          Positioned.fill(child: SafeArea(child: child)),
        ],
      ),
    );
  }
}

class _PalmsPainter extends CustomPainter {
  const _PalmsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final ground = Paint()..color = const Color(0xFF2E3B22);
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.86)
      ..quadraticBezierTo(size.width * 0.3, size.height * 0.80, size.width * 0.6, size.height * 0.88)
      ..quadraticBezierTo(size.width * 0.85, size.height * 0.93, size.width, size.height * 0.84)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, ground);
    final trunk = Paint()
      ..color = const Color(0xFF2E3B22)
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final (x, h) in [(0.06, 0.32), (0.13, 0.24), (0.9, 0.3), (0.96, 0.22)]) {
      final base = Offset(size.width * x, size.height * 0.87);
      final top = Offset(base.dx + 12, base.dy - size.height * h);
      canvas.drawLine(base, top, trunk);
      for (var i = 0; i < 6; i++) {
        final a = -2.9 + i * 0.55;
        canvas.drawLine(
          top,
          top + Offset(46 * (a < -1.57 ? -1 : 1) * (1 - (a + 1.57).abs() / 2), 18 + (a + 1.57).abs() * 10),
          trunk..strokeWidth = 5,
        );
      }
      trunk.strokeWidth = 7;
    }
    // Haze band.
    final haze = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00BF7A3A), Color(0x55BF7A3A), Color(0x00BF7A3A)],
      ).createShader(Rect.fromLTWH(0, size.height * 0.45, size.width, size.height * 0.4));
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.45, size.width, size.height * 0.4), haze);
  }

  @override
  bool shouldRepaint(_PalmsPainter oldDelegate) => false;
}
