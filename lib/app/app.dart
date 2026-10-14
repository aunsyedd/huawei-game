import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'l10n/strings.dart';
import 'responsive.dart';
import 'router.dart';
import 'theme.dart';

class HazeRoyaleApp extends ConsumerWidget {
  const HazeRoyaleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    return MaterialApp.router(
      title: 'Haze Royale',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ms')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: appRouter,
      builder: (context, child) => Listener(
        // Browsers only allow sound after a user gesture.
        onPointerDown: (_) => ref.read(audioServiceProvider).unlock(),
        child: ResponsiveShell(
          rotateMessage: S(locale.languageCode)('rotate_device'),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
