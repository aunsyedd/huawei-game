import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class AirAlert {
  const AirAlert({required this.api, required this.en, required this.ms});
  final int api;
  final String en, ms;
  String text(String lang) => lang == 'ms' ? ms : en;
}

/// Source of haze / air-quality alerts.
abstract class AirQualityService {
  Future<AirAlert?> currentAlert();
}

/// Reads alerts from assets/data/air_quality_alerts.json. Swap for a live
/// source once a usable public Malaysian API feed is confirmed.
class ConfigAirQualityService implements AirQualityService {
  @override
  Future<AirAlert?> currentAlert() async {
    try {
      final j = jsonDecode(await rootBundle.loadString('assets/data/air_quality_alerts.json')) as Map<String, dynamic>;
      final alerts = j['alerts'] as List;
      if (alerts.isEmpty) return null;
      final a = alerts.first as Map<String, dynamic>;
      return AirAlert(api: a['api'] as int, en: a['en'] as String, ms: a['ms'] as String);
    } catch (_) {
      return null;
    }
  }
}
