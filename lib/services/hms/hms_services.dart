import 'package:shared_preferences/shared_preferences.dart';

import 'account_service.dart';
import 'air_quality_service.dart';
import 'game_service.dart';
import 'push_service.dart';

/// Everything that talks to Huawei Mobile Services.
class HmsServices {
  HmsServices({
    required this.hmsAvailable,
    required this.account,
    required this.game,
    required this.push,
    required this.airQuality,
  });

  /// Picks real HMS implementations when HMS Core is present, fakes otherwise.
  /// Account Kit is live; Game Service and Push still use their fakes (HMS_SETUP.md).
  factory HmsServices.create({required bool hmsAvailable, required SharedPreferences prefs}) {
    final air = ConfigAirQualityService();
    return HmsServices(
      hmsAvailable: hmsAvailable,
      account: hmsAvailable ? HmsAccountService() : FakeAccountService(prefs),
      game: FakeGameService(prefs),
      push: FakePushService(air),
      airQuality: air,
    );
  }

  final bool hmsAvailable;
  final AccountService account;
  final GameService game;
  final PushService push;
  final AirQualityService airQuality;
}
