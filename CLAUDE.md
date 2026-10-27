# Haze Royale — project spec

Flutter + Flame mobile game for the UMPSA x HUAWEI GameCenter competition.
Targets Android (Huawei + any Android), **landscape only**. Web build is used for quick desktop testing.

## Game
Full-3D blocky battle royale (surviv.io meets Minecraft) on a Malaysian island. **Non-violent**: paint/water
blasters, players are "tagged out", no blood or real guns. Never use PUBG or Minecraft names or assets.

Two modes, both on the same island:
- **Haze Royale** (`/game`): the battle royale below.
- **Blok Craft** (`/craft`): a sandbox — no bots, no haze, a ~7 minute day/night cycle. Mine, build, craft
  and plant as long as you like. Same simulation with `GameMode.craft`.

- Match: player + 24 AI bots drop onto the map, loot, fight, last one standing wins. 3–5 minute matches.
- Zone: toxic **haze** from forest fires shrinks the safe area in phases (warning countdown, then shrink).
  Standing in haze drains health (armour does not help; an Air Mask reduces it).
- Twist: loot **seed packs** and plant trees (hold to plant, 2 s, interruptible). A tree creates a clean-air
  bubble inside the haze that grows over 3 stages. Bots plant too. Trees can be destroyed by blasters.
  After the last zone phase, bubbles slowly wither so matches always end.
- Loot: Splash Pistol (fast/short), Soaker Rifle (medium), Bubble Launcher (area splash), vests (2 tiers),
  Water Bottle (heal), Air Mask (small heal + haze shield), Seed Pack.
- **Blocks**: a voxel layer sits on the island — patches of log, bamboo, dirt, stone, brick and sand
  (seeded from `blocks.json`). Hold Mine to break the column you face, tap Place to stack one in front.
  Blocks stop movement and shots, so a quick wall is real cover, and blasters chew it away again.
  13 block types; crafting turns them into planks, glass, bricks, lanterns, **air-filter blocks**
  (clean-air bubble like a tree) and even seed packs and water bottles. Bots mine their way out of
  anything you build around them, and drop a block of cover when they are hurt.
- Map areas: forest (NW), palm oil plantation (NE), kampung (W), small town (E), beach (S).
- Results: placement, tag-outs, trees planted, blocks placed, time survived, score (rewards fighting,
  planting AND building),
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
lib/features     menu, lobby, game (screen host), results, leaderboard, settings, guide, story
lib/game         haze_royale_game.dart (Flame Game: camera, input bridge, cached ground chunks)
  render/        camera3d.dart     free orbit camera (yaw + tilt): projection, inverse, and the same
                                   transform as a 4x4 the canvas applies to the ground plane
                 perspective_renderer.dart  frame orchestration: sky, ground, voxels, meshes, haze
                 sky.dart          sky dome, sun, clouds, stars, sea and the `Lighting` day/night model
                 voxels.dart       voxel faces (air-touching only) with per-corner AO, grain and shadows
                 mesh.dart         Mesh/MeshBuilder + TriangleBatch (one depth-sorted drawVertices)
                 models.dart       every model: cube characters, cube oaks (2 LODs), rocks, palms, loot
                 sprites.dart, fx.dart
                 Gameplay stays 2D (x, y) in the simulation; only the view is 3D.
  components/    actor, player (input), bot (brain), projectile (pool), tree, loot, building
  systems/       match_manager (MatchSimulation, pure Dart, headless-testable), zone, combat,
                 loot_spawner, bot_ai, spatial_grid
  world/         map_layout (procedural map from JSON), block_world (the voxel layer)
  ui/            joystick, hud, minimap, drop_overlay, build_bar (hotbar, mine/place, craft, look pad)
lib/state        Riverpod providers (settings, profile stats, last match result, services)
lib/data         game_config.dart: typed models loaded from assets/data/*.json
lib/services/hms account, game_service, push, air_quality — each an abstract interface + fake;
                 hms_detector.dart asks Android (MethodChannel) whether HMS Core is installed.
```

## Rules
- Weapon, loot, zone, tree, bot, score, map and block numbers live in `assets/data/*.json`. Balance there,
  not in code. `blocks.json` holds block colours, hardness, recipes and where resource patches are seeded.
- Every Huawei service sits behind an interface with a fake so the game runs without HMS (emulator, web).
- 60 fps on a mid-range phone with 25 bots: static spatial grid for walls/obstacles, per-frame spatial hash
  for actors/trees, pooled projectiles/effects, bots far from the camera think at a lower rate,
  static map cached as per-chunk `Picture`s, only visible things are drawn.
- `MatchSimulation` must stay free of Flutter widgets/rendering so `test/` can run full headless matches.
- Release APK under 50 MB (hard limit 100 MB): `flutter build apk --release --split-per-abi`.
  Graphics are drawn in code (no image files). Audio is synthesised by `tool/gen_audio.py` into
  assets/audio/*.wav (22 kHz mono, ~2.3 MB total); re-run it after changing a sound.
- Camera: `Camera3D` can be turned (`yaw`) and tilted (`tilt`, 0.42–1.30 rad from straight down). The move
  and aim sticks are rotated into camera space in `HazeRoyaleGame.update`, so turning never inverts the
  controls. At a low tilt the real horizon appears: the ground pass is clipped to below `horizonY`,
  because a plane transform folds back on itself past that line.
- Rendering perf: the ground is baked per 500x500 chunk into textures (all 36, prebaked during the landing
  countdown) — put static ground detail in `_recordChunk`, never per frame. Baked art is daylight art, so
  `_tintGround` multiplies the time-of-day light over it. Repeated flat things (loot glows, splats, smoke,
  droplets, mined-block cubes) come from one sprite atlas (`render/sprites.dart`) drawn as `AtlasBatch`
  groups (one `drawRawAtlas` each). Everything upright — buildings, voxels, trees, characters — goes into
  one `TriangleBatch` (bucket-sorted by depth, one `drawVertices`); cast shadows go into a second batch
  drawn first, always one quad per object so nothing double-darkens. No `saveLayer` in the game view (the
  haze is one `Path.combine` shape). `HazeRoyaleGame.quality` (3 ultra → 0) drops voxel texel detail, cast
  shadows, sea glitter and particles, automatically when fps stays under 48 and by hand in Settings.
  Visual-only effects live in `render/fx.dart` (pooled, not in the simulation).
  Grid lookups use `StaticGrid.gather` with a reused buffer (no allocation per query).
  `test/tmp/frame_capture_test.dart` (dev only, run with `SHOT_DIR` set) renders reference frames and
  prints the CPU cost per frame; `test/tmp/perf_test.dart` splits update vs render.
- Sound: `AudioService` → `GameAudioService` over `services/audio/` backends: Web Audio API on web
  (decoded buffers: ~10 ms latency, gapless loops, cross-faded music), audioplayers low-latency SoundPool on
  Android with a serialised music player. Browsers start audio after the first tap (`unlock()` from a root
  Listener). Music is generated on an exact sample grid in `tool/gen_audio.py`.
  `test/audio_assets_test.dart` checks every referenced sound exists and is preloaded.
- Native-code plugins that compile C/C++ during the build (e.g. flutter_soloud) break `flutter test` on
  machines without Visual Studio — avoid them.

## Deploy (web demo)
Live: https://haze-royale.vercel.app. Vercel builds from the GitHub repo (aunsyedd/huawei-game, branch main)
on every push, using `tool/vercel_build.sh` (clones Flutter 3.47.5, runs `flutter build web`) as configured
in `vercel.json`. Keep those two files. Claude Code is intentionally NOT connected to Vercel (no CLI login,
plugin or MCP): deploy by pushing to main, and don't set up Vercel access again unless the user asks.

## Status / open items
- HMS kits (Account, Game Service, Push) are wired as interfaces + fakes only; real implementations come
  after the 16–18 Oct HMS workshop (see HMS_SETUP.md).
