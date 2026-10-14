import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Screen-size helpers so the UI fits everything from a small 640x360 phone
/// to a tablet. The game is landscape, so the short side (height) drives scale.
class Responsive {
  Responsive._(this.size, this.padding);

  factory Responsive.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Responsive._(mq.size, mq.padding);
  }

  final Size size;

  /// Notch / rounded-corner insets.
  final EdgeInsets padding;

  double get shortest => math.min(size.width, size.height);

  /// 1.0 on a typical 390 dp-high landscape phone; smaller on tiny phones,
  /// larger on tablets.
  double get scale => (shortest / 390).clamp(0.78, 1.5);

  /// Short landscape phones (e.g. 640x360 or less).
  bool get compact => size.height < 380;

  /// Tablets and large foldables.
  bool get large => shortest >= 600;

  double s(double v) => v * scale;

  /// Safe insets with a minimum margin, for HUD elements near the edges.
  EdgeInsets get safe => EdgeInsets.fromLTRB(
    math.max(padding.left, 8),
    math.max(padding.top, 6),
    math.max(padding.right, 8),
    math.max(padding.bottom, 6),
  );
}

/// Clamps the system text size so a large accessibility setting cannot break
/// game layouts, and asks to rotate when shown in portrait (web / tablets;
/// Android is locked to landscape in the manifest).
class ResponsiveShell extends StatelessWidget {
  const ResponsiveShell({super.key, required this.child, required this.rotateMessage});

  final Widget child;
  final String rotateMessage;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final clamped = mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15));
    final portrait = mq.size.height > mq.size.width;
    return MediaQuery(
      data: clamped,
      child: Stack(
        children: [
          if (portrait)
            // Keep the app alive, laid out at a landscape size, under the message.
            ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: mq.size.height,
                maxWidth: mq.size.height,
                minHeight: mq.size.width,
                maxHeight: mq.size.width,
                child: MediaQuery(
                  data: clamped.copyWith(size: Size(mq.size.height, mq.size.width)),
                  child: child,
                ),
              ),
            )
          else
            child,
          if (portrait)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0xF20D1B2A),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.screen_rotation, size: 64, color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          rotateMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 18, decoration: TextDecoration.none),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Vertically centres its child, scrolling instead of overflowing on short screens.
class CenteredScroll extends StatelessWidget {
  const CenteredScroll({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}
