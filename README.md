# VoxiGen Level Importer for Godot

Build levels made in [VoxiGen Studio](https://voxigen.io/en/studio) — the free
browser voxel editor — as Godot 4 scenes: every module batched, lit, colliding
and with level of detail, from one node.

VoxiGen exports a level as one GLB per module plus a `level.json` saying where
each module goes. This add-on reads that folder and builds it:

- **Batched modules.** Every placement of a module shares one mesh, drawn as a
  `MultiMeshInstance3D` per module per chunk of the level. A 400-piece dungeon
  made of 12 modules is a handful of draw calls, not 400.
- **Colours as exported.** VoxiGen writes vertex colours; Godot leaves them
  unused by default and everything renders white. The importer turns them on.
- **Lights.** The level's own lights, and the lights a module carries (a
  torch's flame), posed with every placement of it.
- **Markers.** Modules named `marker_…` (a spawn point, a pickup) become
  `Marker3D`s and are reported by a signal instead of being drawn.
- **Collision.** A trimesh per module, built once and shared, at unscaled poses.
- **Level of detail.** Modules exported with LODs switch to half and a quarter
  of their voxels at the distances you set.
- **Loads from anywhere.** Levels under `res://` use Godot's import; levels on
  disk or in `user://` are read at runtime — so a game can load levels its
  players made.

VOXEN, a voxel shooter, builds every one of its levels this way. Below is its
demo_halls level — 8,165 placements — built, lit and drawn by this add-on
alone, in a plain Godot project:

https://github.com/user-attachments/assets/70ca9e32-ba28-404e-9939-7025baceb1b8

## Install

Copy `addons/voxigen_level` into your project's `addons/` folder and enable
**VoxiGen Level Importer** in *Project → Project Settings → Plugins*. Requires
Godot 4.4 or later; tested on 4.7.

## Use

1. In VoxiGen Studio, export the scene as a **Level** (a zip). Level export is
   part of VoxiGen's one-time Founder licence.
2. Unzip it into your project, e.g. `res://levels/dungeon/`. Godot imports the
   GLBs. (The `sources/` folder holds the editable VoxiGen models; Godot can
   ignore it.)
3. Add a **VoxiGenLevel** node to a scene and set **Manifest Path** to the
   level's `level.json`. The level appears in the editor as a preview; it is
   built again when the game runs, and never saved into your scene file.

From code:

```gdscript
var level := VoxiGenLevel.new()
level.voxel_size_m = 1.0 / 32.0
level.marker_found.connect(func(marker: String, at: Transform3D) -> void:
	if marker == "marker_spawn_player":
		$Player.global_transform = at)
add_child(level)
level.load_level("res://levels/dungeon/level.json")
```

### Levels inside and outside the project

A level under `res://` is drawn from the GLBs Godot imported, with your
project's import settings: by default Godot generates its own mesh LODs and
shadow meshes. A level loaded from disk at runtime gets neither, so the two
can render slightly differently. If you use VoxiGen's LODs (`lod_distances_m`),
turn off **Meshes → Generate LODs** in the import settings of the `modules`
folder so the two kinds don't stack.

### Web, Mobile and Compatibility

A Godot web export runs the Compatibility renderer (WebGL 2), and a level
with more than about a hundred lights near the camera renders nearly black
there: the lighting fails as a whole, with no error. VOXEN's demo_halls (331
lights) stayed lit in Chrome and Safari with about 96 lights near the camera,
went partly dark around 112 and black from 128. Smaller chunks and a higher
`rendering/limits/opengl/max_renderable_lights` did not help.

So on Mobile and Compatibility the importer fades lights out with distance
from the camera, decided by the renderer the game runs on: one imported level
works on every export, and Forward+ keeps every light. The fade distance is
chosen from the level's own lights so no spot has more than `light_budget`
(80) within reach; demo_halls gets 24 m. Set `light_fade_distance_m` to choose
it yourself, or `light_fade_mode` to Always or Never.

Levels loaded at runtime are read as untrusted input: a malformed module,
placement or light is skipped with a warning instead of being built wrong, and
modules must sit inside the level's own folder (`confine_to_level_folder`).

## Settings

| Property | Default | |
|---|---|---|
| `manifest_path` | | The `level.json` to build. |
| `load_on_ready` | `true` | Build when the node enters the tree. |
| `voxel_size_m` | `1/32` | Metres per voxel. VoxiGen works in voxels; the scale is yours. |
| `marker_prefix` | `marker_` | Modules starting with this are markers. Empty: none are. |
| `confine_to_level_folder` | `true` | For a level outside the project, refuse module files outside its folder. Levels under `res://` may share a `../modules` folder. |
| `chunk_size_m` | `32` | Batch cell size. Smaller culls finer but makes more batches; `0` batches each module whole. |
| `collision`, `collision_layer`, `collision_mask` | on, 1, 1 | Static trimesh collision. |
| `light_energy_scale`, `light_range_scale` | `1`, `1` | Calibrate VoxiGen's light intensity and range for your renderer. |
| `shadow_distance_m` | `0` | Shadowed point/spot lights cast shadows only this near the camera. `0`: always. |
| `light_budget` | `80` | On Mobile and Compatibility, the most lights within the fade's reach of any spot. 0: no fade. |
| `light_fade_mode` | Auto | Auto: fade on Mobile and Compatibility only. Always, Never. |
| `light_fade_distance_m`, `light_fade_length_m` | `0`, `10` | Where lights start fading (0: chosen from the level) and how far they take to fade out. |
| `lod_distances_m` | `(0, 0)` | Where half-detail (x) and quarter-detail (y) meshes take over, measured to each chunk's centre — so it needs `chunk_size_m` above 0. `(0, 0)`: off. |

Signals: `level_loaded(modules, placements)` and `marker_found(marker, at)`.

## The format

[FORMAT.md](FORMAT.md) describes `level.json`. The importer reads versions 1–3
and refuses newer ones rather than building them wrongly.

## Developing

```sh
godot --headless --path . -s tests/generate.gd   # writes a test level into the project
godot --headless --path . --import               # lets Godot import its GLBs
godot --headless --path . -s tests/run_tests.gd  # builds test levels and checks them
godot --path . -s tests/visual_check.gd          # renders them (needs a window)
```

The test levels are generated cubes; the repository holds no art.

## License

MIT — see [LICENSE](LICENSE). VoxiGen Studio itself is a separate, proprietary
product by Nikolatec.
