import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n/strings.dart';
import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../state/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final st = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final r = Responsive.of(context);

    return Scaffold(
      body: HazeBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: r.compact ? 6 : 16),
              children: [
                Row(
                  children: [
                    IconButton(onPressed: () => context.go('/'), icon: const Icon(Icons.arrow_back)),
                    Flexible(
                      child: Text(
                        s('settings'),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.translate),
                        title: Text(s('language')),
                        trailing: SegmentedButton<String>(
                          segments: [
                            ButtonSegment(value: 'en', label: Text(r.compact ? 'EN' : 'English')),
                            ButtonSegment(value: 'ms', label: Text(r.compact ? 'BM' : 'Bahasa Melayu')),
                          ],
                          selected: {st.language},
                          onSelectionChanged: (v) => n.setLanguage(v.first),
                          showSelectedIcon: false,
                        ),
                      ),
                      _slider(Icons.volume_up, s('sound'), st.soundVolume, 0, 1, n.setSound),
                      _slider(Icons.music_note, s('music'), st.musicVolume, 0, 1, n.setMusic),
                      _slider(Icons.gamepad, s('sensitivity'), st.sensitivity, 0.5, 1.5, n.setSensitivity),
                      SwitchListTile(
                        secondary: const Icon(Icons.vibration),
                        title: Text(s('haptics')),
                        value: st.haptics,
                        onChanged: n.setHaptics,
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.speed),
                        title: Text(s('show_fps')),
                        value: st.showFps,
                        onChanged: n.setShowFps,
                      ),
                      ListTile(
                        leading: const Icon(Icons.school),
                        title: Text(s('reset_tutorial')),
                        onTap: () {
                          n.setTutorialDone(false);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('tutorial_reset_done'))));
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _slider(IconData icon, String label, double value, double min, double max, void Function(double) onChanged) =>
      ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
      );
}
