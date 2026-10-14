import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'services/audio_service.dart';
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
  final audio = GameAudioService(
    sfxVolume: prefs.getDouble('sound') ?? 0.8,
    musicVolume: prefs.getDouble('music') ?? 0.5,
  );
  unawaited(audio.init());

  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        hmsServicesProvider.overrideWithValue(services),
        audioServiceProvider.overrideWithValue(audio),
      ],
      child: const HazeRoyaleApp(),
    ),
  );
}
