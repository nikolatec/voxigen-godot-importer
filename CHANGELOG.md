# Changelog

## 1.0.0 — unreleased

- `VoxiGenLevel` node: builds a VoxiGen `level.json` (versions 1–3) with
  batched modules per chunk, vertex colours, module and level lights, markers,
  shared trimesh collision and level of detail.
- Loads levels under `res://` through Godot's import, and levels anywhere else
  on disk at runtime.
