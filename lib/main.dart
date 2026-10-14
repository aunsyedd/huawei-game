import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'services/hms/hms_detector.dart';
import 'services/hms/hms_services.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final prefs = await SharedPreferences.getInstance();
  final hms = await HmsDetector().isHmsAvailable();
  final services = HmsServices.create(hmsAvailable: hms, prefs: prefs);
  services.push.init();

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs), hmsServicesProvider.overrideWithValue(services)],
      child: const HazeRoyaleApp(),
    ),
  );
}
