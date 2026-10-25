# Changelog

## 1.0.0 — unreleased

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
