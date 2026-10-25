# VoxiGen level format

A level exported from VoxiGen Studio is a folder (shipped as a zip):

```
level.json        where every module goes
modules/          one GLB per module, and its level-of-detail GLBs
sources/          each module as an editable VoxiGen model — games ignore it
```

Modules are separate files so an engine can draw every placement of one module
as a single batch.

## Units and axes

- **Voxels.** Every position and range is in voxels, one GLB unit per voxel.
  Metres are the game's choice.
- **Right-handed, Y up,** as glTF. A module's GLB has its origin at the
  module's bottom centre.
- A placement is rigid: position and rotation, never scale.

## `level.json`

```json
{
  "version": 3,
  "generator": "voxigen",
  "modules": [
    {
      "name": "torch",
      "file": "modules/torch.glb",
      "lods": ["modules/torch.lod1.glb", "modules/torch.lod2.glb"],
      "lights": [
        { "type": "point", "position": [0, 26, 9], "direction": [0, -1, 0],
          "color": [1, 0.55, 0.22], "intensity": 2, "range": 240, "castsShadow": true }
      ]
    }
  ],
  "placements": [
    { "module": "torch", "position": [64, 32, 0], "rotation": [0, 0.7071068, 0, 0.7071068] }
  ],
  "lights": []
}
```

### `modules[]`

| Field | | |
|---|---|---|
| `name` | string | Unique in the level; lowercase letters, digits and `_`. |
| `file` | string | The GLB, relative to `level.json`. |
| `lods` | string[] | Optional. The module at half and a quarter of its voxels, finest first, in the same frame as `file`. When absent, a reader may look for `<file>.lod1.glb` and `.lod2.glb` beside it. |
| `lights` | light[] | Optional (v3). Lights the module carries to every placement of it, in the GLB's own frame. |

### `placements[]`

| Field | | |
|---|---|---|
| `module` | string | A `modules[].name`. |
| `position` | [x, y, z] | Voxels, where the module's GLB origin goes. |
| `rotation` | [x, y, z, w] | Unit quaternion. |

### lights (`lights[]` and `modules[].lights[]`)

| Field | | |
|---|---|---|
| `type` | `point` \| `spot` \| `directional` | |
| `position` | [x, y, z] | Voxels. Unused by `directional`. |
| `direction` | [x, y, z] | Unit vector the light shines along. Unused by `point`. |
| `color` | [r, g, b] | 0–1, as picked in the editor (sRGB). |
| `intensity` | number | VoxiGen's own scale, not candela or lux — calibrate per engine. |
| `range` | number | Voxels. Unused by `directional`. |
| `innerDegrees`, `outerDegrees` | number | Spot only: from the axis to the cone's inner and outer edge. |
| `castsShadow` | bool | |

The level's own `lights` are in the placements' frame; a module's are in its
GLB's frame and move with each placement of it.

## Markers

The format has no markers, spawns or triggers: those are a game's vocabulary.
By convention a marker is a small module whose name starts with `marker_`
(`marker_spawn_player`), placed like any other; a reader treats it as a
position and facing, not geometry.

## Versions

| Version | Added |
|---|---|
| 1 | `modules`, `placements` |
| 2 | `lights` |
| 3 | `modules[].lights` |

A reader should refuse a version newer than it knows: a newer level may carry
something it would otherwise place wrongly. `modules[].lods` is optional at
every version.
