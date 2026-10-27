import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/strings.dart';
import '../../data/game_config.dart';
import '../../state/progression.dart';
import '../../state/providers.dart';

/// Level, XP bar, streak and today's missions (menu side panel).
class ProgressCard extends ConsumerWidget {
  const ProgressCard({super.key, required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final cfg = ref.watch(gameConfigProvider).value;
    final st = ref.watch(progressProvider);
    if (cfg == null) return const SizedBox.shrink();
    final prog = Progression(cfg.progression);
    final level = prog.levelFor(st.xp);
    final next = prog.xpForLevel(level + 1);
    final today = Progression.dayNumber(DateTime.now());
    final missions = prog.missionsFor(today);
    final fresh = st.missionDay != today;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                s('level', {'n': level}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
            if (st.streak > 0) ...[
              const SizedBox(width: 6),
              const Icon(Icons.local_fire_department, size: 16, color: Color(0xFFFF7043)),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  s('streak', {'n': st.streak}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFFFCC80)),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: prog.levelProgress(st.xp), minHeight: 7),
        ),
        Text(s('xp_progress', {'a': st.xp, 'b': next}), style: const TextStyle(fontSize: 11, color: Colors.white60)),
        SizedBox(height: compact ? 4 : 8),
        Text(s('missions'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        for (var i = 0; i < missions.length; i++)
          _MissionRow(
            mission: missions[i],
            progress: fresh || i >= st.progress.length ? 0 : st.progress[i],
            done: !fresh && i < st.done.length && st.done[i],
            lang: s.lang,
          ),
        SizedBox(height: compact ? 2 : 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => showLocker(context),
            icon: const Icon(Icons.checkroom, size: 18),
            label: Text(s('locker')),
          ),
        ),
      ],
    );
  }
}

class _MissionRow extends StatelessWidget {
  const _MissionRow({required this.mission, required this.progress, required this.done, required this.lang});
  final MissionDef mission;
  final int progress;
  final bool done;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final p = mission.type == 'survive_seconds'
        ? '${progress ~/ 60}:${(progress % 60).toString().padLeft(2, '0')}'
        : '$progress';
    final t = mission.type == 'survive_seconds'
        ? '${mission.target ~/ 60}:${(mission.target % 60).toString().padLeft(2, '0')}'
        : '${mission.target}';
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 15,
            color: done ? const Color(0xFF66BB6A) : Colors.white38,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              mission.text(lang),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: done ? Colors.white54 : Colors.white),
            ),
          ),
          Text(done ? '+${mission.xp}' : '$p/$t', style: const TextStyle(fontSize: 11, color: Color(0xFFFFCC80))),
        ],
      ),
    );
  }
}

/// Skin picker. Locked skins show the level that unlocks them.
Future<void> showLocker(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _LockerDialog());

class _LockerDialog extends ConsumerWidget {
  const _LockerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final cfg = ref.watch(gameConfigProvider).value;
    final st = ref.watch(progressProvider);
    if (cfg == null) return const SizedBox.shrink();
    final level = Progression(cfg.progression).levelFor(st.xp);
    return AlertDialog(
      title: Text(s('locker')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s('locker_hint'), style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < cfg.progression.skins.length; i++)
                  _SkinChip(
                    skin: cfg.progression.skins[i],
                    locked: cfg.progression.skins[i].level > level,
                    selected: st.skin == i,
                    lang: s.lang,
                    label: s('skin_locked', {'n': cfg.progression.skins[i].level}),
                    onTap: () => ref.read(progressProvider.notifier).setSkin(i),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(s('close')))],
    );
  }
}

class _SkinChip extends StatelessWidget {
  const _SkinChip({
    required this.skin,
    required this.locked,
    required this.selected,
    required this.lang,
    required this.label,
    required this.onTap,
  });

  final SkinDef skin;
  final bool locked, selected;
  final String lang, label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: locked ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 84,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 2.5 : 1),
        ),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                CircleAvatar(radius: 20, backgroundColor: locked ? skin.color.withValues(alpha: 0.3) : skin.color),
                if (locked) const Icon(Icons.lock, size: 18, color: Colors.white70),
                if (selected) const Icon(Icons.check, size: 20, color: Colors.white),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              locked ? label : skin.name(lang),
              style: TextStyle(fontSize: 12, color: locked ? Colors.white54 : Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
