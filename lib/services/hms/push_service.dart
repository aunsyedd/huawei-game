import 'dart:async';

import 'air_quality_service.dart';

/// Huawei Push Kit (haze alerts), behind an interface.
abstract class PushService {
  Future<void> init();
  Stream<AirAlert> get alerts;
}

/// Offline stand-in: emits the configured air-quality alert once at startup
/// as an in-app banner instead of a real push notification.
class FakePushService implements PushService {
  FakePushService(this._air);
  final AirQualityService _air;
  final _controller = StreamController<AirAlert>.broadcast();
  bool _sent = false;

  @override
  Stream<AirAlert> get alerts => _controller.stream;

  @override
  Future<void> init() async {
    if (_sent) return;
    _sent = true;
    final alert = await _air.currentAlert();
    if (alert != null && alert.api > 100) {
      Future.delayed(const Duration(seconds: 2), () => _controller.add(alert));
    }
  }
}
