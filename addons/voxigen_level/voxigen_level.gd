@tool
@icon("res://addons/voxigen_level/icon.svg")
class_name VoxiGenLevel
extends Node3D

## Builds a level exported from VoxiGen Studio: one GLB per module, plus a
## level.json saying where each one goes.
##
## Every placement of a module shares one mesh, drawn as a MultiMesh per module
## and per chunk of the level, so a 400-piece dungeon made of 12 modules costs a
## handful of draw calls rather than 400. The manifest states everything in
## voxels; this node turns voxels into metres with [member voxel_size_m].
##
## The format is described in FORMAT.md, next to this add-on's README.

## Emitted once the level is built, with how many modules and placements it has.
signal level_loaded(modules: int, placements: int)

## Emitted for each placement of a marker module (see [member marker_prefix]),
## with the module's name and where it stands, in metres, without scale.
signal marker_found(marker: String, at: Transform3D)

## The newest manifest version this importer reads. Older ones are read too.
const MAX_VERSION := 3

## The level.json to build. Paths inside it are relative to it, so a level
## folder can be moved without editing the file. It may live under res:// (its
## GLBs imported by Godot) or anywhere on disk, user:// included (its GLBs read
## at runtime) — the second is how a game loads levels its players made.
@export_file("*.json") var manifest_path: String = "":
	set(value):
		manifest_path = value
		if is_inside_tree() and Engine.is_editor_hint():
			_preview()

## Build [member manifest_path] when this node enters the tree. Off for a game
## that picks its level itself and calls [method load_level].
@export var load_on_ready: bool = true

## Metres per voxel. VoxiGen states positions in voxels; what a voxel is worth
## is the game's decision. The default makes a 32-voxel VoxiGen chunk a metre.
@export var voxel_size_m: float = 1.0 / 32.0:
	set(value):
		voxel_size_m = maxf(value, 0.0001)
		if is_inside_tree() and Engine.is_editor_hint():
			_preview()

## Modules whose name starts with this are markers, not geometry: a spawn, a
## pickup, a trigger. In VoxiGen a marker is a small model titled, say,
## "marker_spawn_player", placed like any module. It is not drawn and does not
## collide; it becomes a Marker3D and is reported by [signal marker_found].
## Empty: every module is geometry.
@export var marker_prefix: String = "marker_"

## Build placements into cells this size (metres), one batch per module per
## cell, so Godot can skip what is off screen and switch level of detail per
## cell. Smaller cells cull finer but make more batches: VOXEN's 390 m
## demo_halls is 31 batches whole, 606 at 32 m, 1071 at 16 m. 0: one batch per
## module for the whole level, drawn in full every frame.
@export var chunk_size_m: float = 32.0

@export_group("Collision")
## Give the level static collision: each module's mesh as a trimesh shape,
## built once and shared by every placement.
@export var collision: bool = true
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1

@export_group("Lights")
## What VoxiGen's light intensity is worth as Godot light energy. VoxiGen's
## number belongs to its own renderer, so calibrate it here by eye.
@export var light_energy_scale: float = 1.0
## Multiplies every light's range. Below 1, fewer lights overlap any surface.
@export var light_range_scale: float = 1.0
## Shadowed point and spot lights cast their shadow only this near the camera
## (metres), fading out past it; their light still reaches any distance. A
## shadowed omni light redraws what it reaches six times a frame, so a room of
## torches is expensive without this. 0: shadows at any distance.
@export var shadow_distance_m: float = 0.0

@export_group("Level of detail")
## Where the export's coarser meshes take over (metres from the camera): x for
## half the voxels, y for a quarter. Used only for modules exported with level
## of detail. (0, 0): always draw the full meshes.
@export var lod_distances_m: Vector2 = Vector2.ZERO

## Mesh and collision faces per module file, for this node's levels.
var _meshes: Dictionary = {}
var _faces: Dictionary = {}

func _ready() -> void:
	if Engine.is_editor_hint():
		_preview()
	elif load_on_ready and not manifest_path.is_empty():
		load_level(manifest_path)

## Replaces whatever this node holds with the level at [param path]. Returns
## how many placements were built: 0 for a level that could not be read.
func load_level(path: String) -> int:
	clear()
	var manifest := _read_manifest(path)
	if manifest.is_empty():
		return 0

	var base_dir := path.get_base_dir()
	var meshes := {}  # module name -> [full, lod1, lod2] (lods may be null)
	var module_lights := {}
	for entry: Variant in manifest.get("modules", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module := entry as Dictionary
		var name := str(module.get("name", ""))
		var file := str(module.get("file", ""))
		if name.is_empty() or file.is_empty():
			push_warning("VoxiGenLevel: a module with no name or file was skipped")
			continue
		if _is_marker(name):
			continue
		var full_path := _resolve(base_dir, file)
		var mesh := _load_mesh(full_path)
		if mesh == null:
			continue
		var lods: Array = [mesh, null, null]
		var named: Array = module.get("lods", [])
		for k in [1, 2]:
			var lod_path := _resolve(base_dir, str(named[k - 1])) if named.size() >= k \
				else full_path.trim_suffix(".glb") + ".lod%d.glb" % k
			if _file_exists(lod_path):
				lods[k] = _load_mesh(lod_path)
		meshes[name] = lods
		var carried: Variant = module.get("lights", [])
		if carried is Array and not (carried as Array).is_empty():
			module_lights[name] = carried

	# Placements, grouped by module and cell: a MultiMesh draws one mesh.
	var batches := {}  # [module, cell] -> Array[Transform3D]
	var placed := 0
	var markers := 0
	for entry: Variant in manifest.get("placements", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var placement := entry as Dictionary
		var module := str(placement.get("module", ""))
		var pose := _pose_of(placement)
		if _is_marker(module):
			_add_marker(module, _rigid(pose))
			markers += 1
			continue
		if not meshes.has(module):
			push_warning("VoxiGenLevel: a placement names unknown module '%s'; skipped" % module)
			continue
		var key := [module, _cell_of(pose.origin)]
		if not batches.has(key):
			batches[key] = []
		batches[key].append(pose)
		placed += 1
		for light: Variant in module_lights.get(module, []):
			if typeof(light) == TYPE_DICTIONARY:
				_add_light(light as Dictionary, _rigid(pose))

	for key: Array in batches:
		_add_batch(key[0], key[1], meshes[key[0]], batches[key])

	for light: Variant in manifest.get("lights", []):
		if typeof(light) == TYPE_DICTIONARY:
			_add_light(light as Dictionary)

	level_loaded.emit(meshes.size(), placed)
	return placed

## Removes the level this node built.
func clear() -> void:
	for child in get_children():
		if child.has_meta("voxigen_level"):
			remove_child(child)
			child.queue_free()

func _preview() -> void:
	# In the editor the level is drawn for a look, not saved into the scene:
	# its nodes have no owner, so the scene file keeps only this node and its
	# settings, and the game builds the level itself when it runs.
	clear()
	if not manifest_path.is_empty():
		load_level(manifest_path)

func _read_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("VoxiGenLevel: no level manifest at %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("VoxiGenLevel: %s is not a level manifest" % path)
		return {}
	var manifest := parsed as Dictionary
	var version := int(manifest.get("version", 0))
	if version < 1:
		push_error("VoxiGenLevel: %s has no version; is it a VoxiGen level.json?" % path)
		return {}
	if version > MAX_VERSION:
		# A newer level may carry what this would place wrongly; refuse rather
		# than build half of it.
		push_error("VoxiGenLevel: %s is version %d; this importer reads up to %d. Update the add-on." \
			% [path, version, MAX_VERSION])
		return {}
	return manifest

func _resolve(base_dir: String, file: String) -> String:
	return base_dir.path_join(file).simplify_path()

func _file_exists(path: String) -> bool:
	return (_in_project(path) and ResourceLoader.exists(path)) or FileAccess.file_exists(path)

# Only a file under res:// is Godot's to have imported. Outside the project a
# GLB can still sit beside a .import file — written by the project it came
# from — that points into that project's cache, so it is read directly.
func _in_project(path: String) -> bool:
	return path.begins_with("res://")

# A module GLB's mesh, ready to draw. Godot's importer leaves glTF vertex colour
# unmultiplied — VoxiGen writes colour as COLOR_0 over a white base colour, and
# without vertex_color_use_as_albedo every module draws white — so the mesh is
# copied with its materials told to use it.
func _load_mesh(path: String) -> Mesh:
	if _meshes.has(path):
		return _meshes[path]
	var root: Node = null
	if _in_project(path) and ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed:
			root = packed.instantiate()
	if root == null and FileAccess.file_exists(path):
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(path, state) == OK:
			root = document.generate_scene(state)
	if root == null:
		push_error("VoxiGenLevel: could not load module %s" % path)
		_meshes[path] = null
		return null
	var found := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		found.push_front(root)
	var source: Mesh = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
	if found.size() > 1:
		push_warning("VoxiGenLevel: module %s holds %d meshes; only the first is used" % [path, found.size()])
	root.free()
	if source == null:
		push_error("VoxiGenLevel: module %s has no mesh" % path)
		_meshes[path] = null
		return null
	var mesh := source.duplicate() as Mesh
	for i in mesh.get_surface_count():
		var material := mesh.surface_get_material(i) as BaseMaterial3D
		if material:
			material = material.duplicate() as BaseMaterial3D
			material.vertex_color_use_as_albedo = true
			mesh.surface_set_material(i, material)
	_meshes[path] = mesh
	return mesh

# Voxels to metres, and the manifest's xyzw quaternion to a basis. The scale is
# in the pose so a placement draws at its size; collision gets rigid poses and
# faces already in metres instead (_add_batch), since physics shapes should not
# be scaled.
func _pose_of(placement: Dictionary) -> Transform3D:
	var p: Array = placement.get("position", [0, 0, 0])
	var q: Array = placement.get("rotation", [0, 0, 0, 1])
	var rotation := Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3])).normalized()
	var origin := Vector3(float(p[0]), float(p[1]), float(p[2])) * voxel_size_m
	return Transform3D(Basis(rotation).scaled(Vector3.ONE * voxel_size_m), origin)

func _rigid(pose: Transform3D) -> Transform3D:
	return Transform3D(pose.basis.orthonormalized(), pose.origin)

func _cell_of(at: Vector3) -> Vector3i:
	if chunk_size_m <= 0.0:
		return Vector3i.ZERO
	return Vector3i((at / chunk_size_m).floor())

func _is_marker(module: String) -> bool:
	return not marker_prefix.is_empty() and module.begins_with(marker_prefix)

func _own(node: Node) -> void:
	node.set_meta("voxigen_level", true)
	add_child(node, true)

func _add_marker(module: String, at: Transform3D) -> void:
	var marker := Marker3D.new()
	marker.name = module
	marker.transform = at
	_own(marker)
	marker_found.emit(module, at)

func _add_batch(module: String, cell: Vector3i, lods: Array, poses: Array) -> void:
	var suffix := "" if chunk_size_m <= 0.0 else "_%d_%d_%d" % [cell.x, cell.y, cell.z]
	var use_lods := lod_distances_m.x > 0.0 and lods[1] != null
	# The quarter-voxel mesh only past a second, farther distance.
	var use_lod2 := use_lods and lods[2] != null and lod_distances_m.y > lod_distances_m.x
	for k in 3:
		if lods[k] == null or (k > 0 and not use_lods) or (k == 2 and not use_lod2):
			continue
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = lods[k]
		batch.instance_count = poses.size()
		for i in poses.size():
			batch.set_instance_transform(i, poses[i])
		var node := MultiMeshInstance3D.new()
		node.name = module + suffix + ("" if k == 0 else "_lod%d" % k)
		node.multimesh = batch
		if use_lods:
			var far := lod_distances_m.y if use_lod2 else 0.0
			match k:
				0:
					node.visibility_range_end = lod_distances_m.x
				1:
					node.visibility_range_begin = lod_distances_m.x
					node.visibility_range_end = far
				2:
					node.visibility_range_begin = lod_distances_m.y
		_own(node)

	if not collision or Engine.is_editor_hint():
		return
	var faces := _faces_of(lods[0])
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = module + suffix + "_collision"
	body.collision_layer = collision_layer
	body.collision_mask = collision_mask
	for pose: Transform3D in poses:
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.transform = _rigid(pose)
		body.add_child(collider)
	_own(body)

# A module's triangles in metres, once per mesh: the shape every placement of
# it shares, unscaled, at a rigid pose.
func _faces_of(mesh: Mesh) -> PackedVector3Array:
	var key := [mesh, voxel_size_m]  # in metres, so per scale
	if _faces.has(key):
		return _faces[key]
	var faces := mesh.get_faces()
	for i in faces.size():
		faces[i] *= voxel_size_m
	_faces[key] = faces
	return faces

# A light in voxels, right-handed: the level's own in the placements' frame, or
# a module's in its GLB's frame with `at` the placement carrying it. Godot's
# lights shine down their own -Z, so spot and directional lights are turned to
# look along the manifest's direction.
func _add_light(light: Dictionary, at: Transform3D = Transform3D.IDENTITY) -> Light3D:
	var type := str(light.get("type", ""))
	var node: Light3D
	match type:
		"point":
			var omni := OmniLight3D.new()
			omni.omni_range = float(light.get("range", 0.0)) * voxel_size_m * light_range_scale
			node = omni
		"spot":
			var spot := SpotLight3D.new()
			spot.spot_range = float(light.get("range", 0.0)) * voxel_size_m * light_range_scale
			spot.spot_angle = float(light.get("outerDegrees", 45.0))
			# Godot has angular attenuation rather than an inner cone; this is
			# the approximation its own glTF light importer uses.
			if light.has("innerDegrees"):
				var outer := spot.spot_angle
				var inner := clampf(float(light["innerDegrees"]), 0.0, outer)
				var ratio := inner / outer if outer > 0.0 else 0.0
				spot.spot_angle_attenuation = 0.2 / maxf(1.0 - ratio, 0.000001) - 0.1
			node = spot
		"directional":
			node = DirectionalLight3D.new()
		_:
			push_warning("VoxiGenLevel: a light of unknown type '%s' was skipped" % type)
			return null
	var c: Array = light.get("color", [1, 1, 1])
	node.light_color = Color(float(c[0]), float(c[1]), float(c[2]))
	node.light_energy = float(light.get("intensity", 1.0)) * light_energy_scale
	node.shadow_enabled = bool(light.get("castsShadow", false))
	if node.shadow_enabled and type != "directional" and shadow_distance_m > 0.0:
		node.distance_fade_enabled = true
		node.distance_fade_shadow = shadow_distance_m
		node.distance_fade_begin = 100000.0
		node.distance_fade_length = maxf(shadow_distance_m * 0.25, 0.01)
	var p: Array = light.get("position", [0, 0, 0])
	node.position = Vector3(float(p[0]), float(p[1]), float(p[2])) * voxel_size_m
	if type != "point":
		var d: Array = light.get("direction", [0, -1, 0])
		var dir := Vector3(float(d[0]), float(d[1]), float(d[2])).normalized()
		if dir.length() > 0.0:
			var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
			node.basis = Basis.looking_at(dir, up)
	node.transform = at * node.transform
	node.name = type + "_light"
	_own(node)
	return node
