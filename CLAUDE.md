# Haze Royale — project spec

Flutter + Flame mobile game for the UMPSA x HUAWEI GameCenter competition.
Targets Android (Huawei + any Android), **landscape only**. Web build is used for quick desktop testing.

## Game
2D top-down battle royale (surviv.io / Zombs Royale style) on a Malaysian island. **Non-violent**: paint/water
blasters, players are "tagged out", no blood or real guns. Never use PUBG names or assets.

- Match: player + 24 AI bots drop onto the map, loot, fight, last one standing wins. 3–5 minute matches.
- Zone: toxic **haze** from forest fires shrinks the safe area in phases (warning countdown, then shrink).
  Standing in haze drains health (armour does not help; an Air Mask reduces it).
- Twist: loot **seed packs** and plant trees (hold to plant, 2 s, interruptible). A tree creates a clean-air
  bubble inside the haze that grows over 3 stages. Bots plant too. Trees can be destroyed by blasters.
  After the last zone phase, bubbles slowly wither so matches always end.
- Loot: Splash Pistol (fast/short), Soaker Rifle (medium), Bubble Launcher (area splash), vests (2 tiers),
  Water Bottle (heal), Air Mask (small heal + haze shield), Seed Pack.
- Map areas: forest (NW), palm oil plantation (NE), kampung (W), small town (E), beach (S).
- Results: placement, tag-outs, trees planted, time survived, score (rewards fighting AND planting),
  plus one "Did you know?" haze fact (BM + EN).
- Languages: English + Bahasa Malaysia.

## Stack
Flutter stable, Flame (`Game` base class with a custom canvas renderer), Riverpod 3 (Notifier API only),
go_router, flutter_localizations, shared_preferences.
The map is generated deterministically from `assets/data/map.json` (seeded) instead of a Tiled `.tmx`;
flame_tiled can be added later if hand-made maps are wanted.

## Architecture
```
lib/app          routing, theme, l10n (lib/app/l10n/strings.dart holds every EN/BM string)
lib/features     menu, lobby, game (screen host), results, leaderboard, settings
lib/game         haze_royale_game.dart (Flame Game: camera, input bridge, cached ground chunks)
  render/        perspective_renderer.dart: tilted 3D camera (2.5D). Ground drawn through a
                 perspective matrix; walls, pitched roofs, trees, players and shots are projected
                 and depth-sorted by y. Gameplay stays 2D (x, y) in the simulation.
  components/    actor, player (input), bot (brain), projectile (pool), tree, loot, building
  systems/       match_manager (MatchSimulation, pure Dart, headless-testable), zone, combat,
                 loot_spawner, bot_ai, spatial_grid
  world/         map_layout (procedural map from JSON)
  ui/            joystick, hud, minimap, drop_overlay
lib/state        Riverpod providers (settings, profile stats, last match result, services)
lib/data         game_config.dart: typed models loaded from assets/data/*.json
lib/services/hms account, game_service, push, air_quality — each an abstract interface + fake;
                 hms_detector.dart asks Android (MethodChannel) whether HMS Core is installed.
```

## Rules
- Weapon, loot, zone, tree, bot, score and map numbers live in `assets/data/*.json`. Balance there, not in code.
- Every Huawei service sits behind an interface with a fake so the game runs without HMS (emulator, web).
- 60 fps on a mid-range phone with 25 bots: static spatial grid for walls/obstacles, per-frame spatial hash
  for actors/trees, pooled projectiles/effects, bots far from the camera think at a lower rate,
  static map cached as per-chunk `Picture`s, only visible things are drawn.
- `MatchSimulation` must stay free of Flutter widgets/rendering so `test/` can run full headless matches.
- Release APK under 50 MB (hard limit 100 MB): `flutter build apk --release --split-per-abi`.
  Graphics are drawn in code (no image files). Audio is synthesised by `tool/gen_audio.py` into
  assets/audio/*.wav (22 kHz mono, ~2.3 MB total); re-run it after changing a sound.
- Rendering perf: the ground is baked per 500x500 chunk into textures (all 36, prebaked during the landing
  countdown) — put static ground detail in `_recordChunk`, never per frame. Repeated objects (palms, trees,
  rocks, bodies, loot icons, splats, smoke, glows) come from one sprite atlas (`render/sprites.dart`) and are
  drawn as single blits or `AtlasBatch` groups (one `drawRawAtlas` per group). No `saveLayer` in the game
  view (the haze is one `Path.combine` shape). `HazeRoyaleGame.quality` (2→0) drops extras automatically
  when fps stays under 48. Visual-only effects live in `render/fx.dart` (pooled, not in the simulation).
  Grid lookups use `StaticGrid.gather` with a reused buffer (no allocation per query).
- Sound: `AudioService` → `GameAudioService` over `services/audio/` backends: Web Audio API on web
  (decoded buffers: ~10 ms latency, gapless loops, cross-faded music), audioplayers low-latency SoundPool on
  Android with a serialised music player. Browsers start audio after the first tap (`unlock()` from a root
  Listener). Music is generated on an exact sample grid in `tool/gen_audio.py`.
  `test/audio_assets_test.dart` checks every referenced sound exists and is preloaded.
- Native-code plugins that compile C/C++ during the build (e.g. flutter_soloud) break `flutter test` on
  machines without Visual Studio — avoid them.

## Deploy (web demo)
Vercel project `haze-royale` builds from source with `tool/vercel_build.sh` (clones Flutter 3.47.5, runs
`flutter build web`), configured in `vercel.json`. `vercel deploy --prod` from the repo root, or push to the
linked GitHub repo. Live: https://haze-royale.vercel.app

## Status / open items
- HMS kits (Account, Game Service, Push) are wired as interfaces + fakes only; real implementations come
  after the 16–18 Oct HMS workshop (see HMS_SETUP.md).
