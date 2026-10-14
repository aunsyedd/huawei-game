import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asks the Android side whether HMS Core is installed (see MainActivity.kt).
/// Anything else (web, iOS, missing channel) counts as "no HMS".
class HmsDetector {
  static const _channel = MethodChannel('haze_royale/hms');

  Future<bool> isHmsAvailable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('isHmsAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
