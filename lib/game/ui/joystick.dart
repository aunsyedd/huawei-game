import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Touch joystick. With [floating] the base appears where the finger lands
/// anywhere inside the widget; otherwise it sits fixed at the centre.
/// [onChanged] receives a vector with length 0..1 (0 when released).
class Joystick extends StatefulWidget {
  const Joystick({
    super.key,
    required this.onChanged,
    this.floating = false,
    this.radius = 60,
    this.color = Colors.white,
    this.fireThreshold,
  });

  final void Function(Offset value) onChanged;
  final bool floating;
  final double radius;
  final Color color;

  /// When set, the ring turns red past this deflection (fire zone hint).
  final double? fireThreshold;

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  int? _pointer;
  Offset? _base;
  Offset _knob = Offset.zero;

  void _update(Offset local) {
    final base = _base!;
    var d = local - base;
    if (d.distance > widget.radius) d = d / d.distance * widget.radius;
    setState(() => _knob = d);
    widget.onChanged(d / widget.radius);
  }

  void _release() {
    setState(() {
      _pointer = null;
      _knob = Offset.zero;
      if (widget.floating) _base = null;
    });
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final center = Offset(c.maxWidth / 2, c.maxHeight / 2);
        final base = _base ?? (widget.floating ? null : center);
        final firing = widget.fireThreshold != null && _knob.distance / widget.radius > widget.fireThreshold!;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            // Mouse is handled by the game screen (aim with cursor, click to fire).
            if (_pointer != null || e.kind == PointerDeviceKind.mouse) return;
            _pointer = e.pointer;
            _base = widget.floating ? e.localPosition : center;
            _update(e.localPosition);
          },
          onPointerMove: (e) {
            if (e.pointer == _pointer) _update(e.localPosition);
          },
          onPointerUp: (e) {
            if (e.pointer == _pointer) _release();
          },
          onPointerCancel: (e) {
            if (e.pointer == _pointer) _release();
          },
          child: CustomPaint(
            size: Size(c.maxWidth, c.maxHeight),
            painter: _StickPainter(base, _knob, widget.radius, widget.color, firing, _pointer != null),
          ),
        );
      },
    );
  }
}

class _StickPainter extends CustomPainter {
  _StickPainter(this.base, this.knob, this.radius, this.color, this.firing, this.active);
  final Offset? base;
  final Offset knob;
  final double radius;
  final Color color;
  final bool firing, active;

  @override
  void paint(Canvas canvas, Size size) {
    final b = base;
    if (b == null) return;
    final ring = firing ? const Color(0xFFFF7043) : color;
    canvas.drawCircle(b, radius, Paint()..color = ring.withValues(alpha: active ? 0.18 : 0.10));
    canvas.drawCircle(
      b,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = ring.withValues(alpha: active ? 0.6 : 0.35),
    );
    canvas.drawCircle(b + knob, radius * 0.42, Paint()..color = ring.withValues(alpha: active ? 0.75 : 0.4));
  }

  @override
  bool shouldRepaint(_StickPainter old) =>
      old.base != base || old.knob != knob || old.firing != firing || old.active != active;
}
