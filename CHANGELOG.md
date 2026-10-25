# Changelog

## 1.0.1 — 2026-10-26

- Light-heavy levels no longer render black in web exports. On the Mobile and
  Compatibility renderers (every web export runs Compatibility) lights fade
  out with distance from the camera, from a distance chosen so no spot in the
  level has more than `light_budget` lights within reach. Forward+ is
  unchanged. New settings: `light_budget`, `light_fade_mode`,
  `light_fade_distance_m`, `light_fade_length_m`. Reported by a Godot
  developer who ships to web.

## 1.0.0 — 2026-10-25

- `VoxiGenLevel` node: builds a VoxiGen `level.json` (versions 1–3) with
  batched modules per chunk, vertex colours, module and level lights, markers,
  shared trimesh collision and level of detail.
- Loads levels under `res://` through Godot's import, and levels anywhere else
  on disk at runtime; malformed entries are skipped with a warning.
- Reloading a level reads its modules again, so a re-export shows up.
- One collision shape per module, shared across every chunk.
- Textured exports keep their texture; vertex colour is used only where a
  mesh has it.
- Every setting that changes the preview refreshes it, once per frame.
- Level of detail warns when `chunk_size_m` is 0.
- Hostile input: non-bool `castsShadow`, numbers too large for a transform and
  module paths outside the level folder are refused.
