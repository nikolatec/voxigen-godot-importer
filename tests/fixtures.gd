extends RefCounted

# Writes small VoxiGen-shaped levels for the tests: coloured cubes standing in
# for modules, a lamp module carrying a light, a marker, and their level.json.
# Generated rather than committed, so the repository holds no art.

const S := 32.0  # voxels per module edge, as VoxiGen modules are sized

static func write_level(dir: String, version := 3, extra := {}) -> String:
	DirAccess.make_dir_recursive_absolute(dir.path_join("modules"))
	_write_glb(dir.path_join("modules/cube.glb"), S, Color(0.8, 0.2, 0.1))
	_write_glb(dir.path_join("modules/cube.lod1.glb"), S, Color(0.8, 0.2, 0.1))
	_write_glb(dir.path_join("modules/cube.lod2.glb"), S, Color(0.8, 0.2, 0.1))
	_write_glb(dir.path_join("modules/lamp.glb"), 8.0, Color(1.0, 0.8, 0.3))
	_write_glb(dir.path_join("modules/marker_spawn_player.glb"), 2.0, Color.WHITE)

	var q90 := Quaternion(Vector3.UP, PI / 2.0)
	var manifest := {
		"version": version,
		"generator": "voxigen-tests",
		"modules": [
			{"name": "cube", "file": "modules/cube.glb",
				"lods": ["modules/cube.lod1.glb", "modules/cube.lod2.glb"]},
			{"name": "lamp", "file": "modules/lamp.glb"},
			{"name": "marker_spawn_player", "file": "modules/marker_spawn_player.glb"},
		],
		"placements": [
			{"module": "cube", "position": [0, 0, 0], "rotation": [0, 0, 0, 1]},
			{"module": "cube", "position": [32, 0, 0], "rotation": [0, 0, 0, 1]},
			# 1024 voxels out: 32 m, another 16 m chunk.
			{"module": "cube", "position": [1024, 0, 0], "rotation": [q90.x, q90.y, q90.z, q90.w]},
			{"module": "lamp", "position": [64, 32, 0], "rotation": [q90.x, q90.y, q90.z, q90.w]},
			{"module": "marker_spawn_player", "position": [16, 32, 16], "rotation": [0, 0, 0, 1]},
			{"module": "missing_module", "position": [0, 0, 0], "rotation": [0, 0, 0, 1]},
		],
	}
	if version >= 2:
		manifest["lights"] = [{"type": "directional", "position": [0, 0, 0], "direction": [0, -1, 0],
			"color": [1, 1, 1], "intensity": 0.5, "range": 0, "castsShadow": true}]
	if version >= 3:
		manifest["modules"][1]["lights"] = [{"type": "point", "position": [0, 10, 4],
			"direction": [0, -1, 0], "color": [1, 0.55, 0.22], "intensity": 2, "range": 240,
			"castsShadow": true}]
	manifest.merge(extra, true)
	var path := dir.path_join("level.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  "))
	file.close()
	return path

## Writes `level.json` with exactly `manifest` (plus version 3), beside the
## modules write_level made in `dir`.
static func write_manifest(dir: String, manifest: Dictionary) -> String:
	var body := {"version": 3, "generator": "voxigen-tests", "modules": [], "placements": [], "lights": []}
	body.merge(manifest, true)
	var path := dir.path_join("level.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(body, "  "))
	file.close()
	return path

## A module coloured by a texture rather than vertex colours, as VoxiGen's
## textured export writes it.
static func write_textured_glb(path: String, size: float) -> void:
	_write_glb(path, size, Color.WHITE, true)

## A file named .glb that is not one.
static func write_broken_glb(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("not a glb")
	file.close()

# A cube `size` voxels on an edge, standing on its bottom centre as VoxiGen's
# modules do, coloured by COLOR_0 over a white base colour as VoxiGen writes —
# or, `textured`, by an albedo texture and no vertex colour.
static func _write_glb(path: String, size: float, color: Color, textured := false) -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	var arrays := box.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	for i in verts.size():
		verts[i].y += size / 2.0
		colors.append(color)
	arrays[Mesh.ARRAY_VERTEX] = verts
	if not textured:
		arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	if textured:
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.2, 0.6, 0.3))
		material.albedo_texture = ImageTexture.create_from_image(image)
	mesh.surface_set_material(0, material)
	var root := Node3D.new()
	root.name = path.get_file().get_basename()
	var instance := MeshInstance3D.new()
	instance.name = "mesh"
	instance.mesh = mesh
	root.add_child(instance)
	instance.owner = root
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	document.append_from_scene(root, state)
	document.write_to_filesystem(state, path)
	root.free()
