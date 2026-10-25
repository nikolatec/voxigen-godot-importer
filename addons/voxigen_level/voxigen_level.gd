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
## The format: https://github.com/nikolatec/voxigen-godot-importer/blob/main/FORMAT.md

## Emitted once the level is built, with how many modules and placements it has.
signal level_loaded(modules: int, placements: int)

## Emitted for each placement of a marker module (see [member marker_prefix]),
## with the module's name and where it stands, in metres, without scale.
signal marker_found(marker: String, at: Transform3D)

## The newest manifest version this importer reads. Older ones are read too.
const MAX_VERSION := 3

## Fade distances (metres) the importer tries for a level's lights, farthest
## first; it takes the first that keeps [member light_budget].
const LIGHT_FADE_STEPS: Array[float] = [96.0, 80.0, 64.0, 48.0, 40.0, 32.0, 24.0, 20.0, 16.0, 12.0, 8.0]

## A light whose shadow alone fades (shadow_distance_m) keeps its light out to here.
const NO_LIGHT_FADE_M := 100000.0

## The largest number a manifest may state, in voxels or any other unit. Godot
## keeps positions in 32-bit floats, so a value that is finite here (1e300) can
## still become infinite in a transform; a billion voxels is far past any level.
const MAX_MAGNITUDE := 1.0e9

## The level.json to build. Paths inside it are relative to it, so a level
## folder can be moved without editing the file. It may live under res:// (its
## GLBs imported by Godot) or anywhere on disk, user:// included (its GLBs read
## at runtime) — the second is how a game loads levels its players made, so
## nothing in a manifest is trusted: a malformed entry is skipped with a warning.
@export_file("*.json") var manifest_path: String = "":
	set(value):
		manifest_path = value
		_changed()

## Build [member manifest_path] when this node enters the tree. Off for a game
## that picks its level itself and calls [method load_level].
@export var load_on_ready: bool = true

## Metres per voxel. VoxiGen states positions in voxels; what a voxel is worth
## is the game's decision. The default makes a 32-voxel VoxiGen chunk a metre.
@export var voxel_size_m: float = 1.0 / 32.0:
	set(value):
		voxel_size_m = maxf(value, 0.0001)
		_changed()

## Modules whose name starts with this are markers, not geometry: a spawn, a
## pickup, a trigger. In VoxiGen a marker is a small model titled, say,
## "marker_spawn_player", placed like any module. It is not drawn and does not
## collide; it becomes a Marker3D and is reported by [signal marker_found].
## Empty: every module is geometry.
@export var marker_prefix: String = "marker_":
	set(value):
		marker_prefix = value
		_changed()

## Build placements into cells this size (metres), one batch per module per
## cell, so Godot can skip what is off screen and switch level of detail per
## cell. Smaller cells cull finer but make more batches: VOXEN's 390 m
## demo_halls is 31 batches whole, 606 at 32 m, 1071 at 16 m. 0: one batch per
## module for the whole level, drawn in full every frame.
@export var chunk_size_m: float = 32.0:
	set(value):
		chunk_size_m = maxf(value, 0.0)
		_changed()

## For a level outside the project (on disk or in user://, such as one a player
## made), refuse module files outside the level's own folder, so a manifest
## cannot point the importer at other files on the machine. A level under
## res:// may share a modules folder beside it (../modules), as VOXEN's do.
@export var confine_to_level_folder: bool = true:
	set(value):
		confine_to_level_folder = value
		_changed()

@export_group("Collision")
## Give the level static collision: each module's mesh as a trimesh shape,
## built once and shared by every placement. Not built in the editor preview.
@export var collision: bool = true
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1

@export_group("Lights")
## What VoxiGen's light intensity is worth as Godot light energy. VoxiGen's
## number belongs to its own renderer, so calibrate it here by eye.
@export var light_energy_scale: float = 1.0:
	set(value):
		light_energy_scale = value
		_changed()
## Multiplies every light's range. Below 1, fewer lights overlap any surface.
@export var light_range_scale: float = 1.0:
	set(value):
		light_range_scale = value
		_changed()
## Shadowed point and spot lights cast their shadow only this near the camera
## (metres), fading out past it; their light still reaches any distance. A
## shadowed omni light redraws what it reaches six times a frame, so a room of
## torches is expensive without this. 0: shadows at any distance.
@export var shadow_distance_m: float = 0.0:
	set(value):
		shadow_distance_m = maxf(value, 0.0)
		_changed()

## On the Mobile and Compatibility renderers, how many lights may be within
## the fade's reach of any spot in the level. A web export (Compatibility,
## WebGL 2) with too many lights does not drop the farthest: it renders nearly
## black, with no error. VOXEN's demo_halls on Chrome and Safari stayed lit
## with about 96 lights near the camera, went partly dark around 112 and black
## from 128. Lights fade out past a distance chosen so no spot has more than
## this many within reach. 0: no fade.
@export_range(0, 256) var light_budget: int = 80:
	set(value):
		light_budget = maxi(value, 0)
		_apply_light_fade()
## Where the light fade applies. Auto: on Mobile and Compatibility, as decided
## by the renderer the game runs on, so one level suits every export and
## Forward+ keeps every light. Always: on every renderer. Never: off.
@export_enum("Auto", "Always", "Never") var light_fade_mode: int = 0:
	set(value):
		light_fade_mode = value
		_apply_light_fade()
## Lights fade out past this distance from the camera (metres). 0: chosen from
## the level's own lights to keep [member light_budget].
@export var light_fade_distance_m: float = 0.0:
	set(value):
		light_fade_distance_m = maxf(value, 0.0)
		_apply_light_fade()
## How far a light takes to fade out (metres), so lights do not pop as the
## camera moves.
@export var light_fade_length_m: float = 10.0:
	set(value):
		light_fade_length_m = maxf(value, 0.0)
		_apply_light_fade()

@export_group("Level of detail")
## Where the export's coarser meshes take over (metres from the camera): x for
## half the voxels, y for a quarter. Used only for modules exported with level
## of detail, and measured to the centre of each chunk, so it needs
## [member chunk_size_m] above 0. (0, 0): always draw the full meshes.
@export var lod_distances_m: Vector2 = Vector2.ZERO:
	set(value):
		lod_distances_m = value
		_changed()

## Per load_level: meshes and collision shapes by module file, so placements
## of a module share them. Emptied on every load, so a level re-exported to the
## same path is read again.
var _meshes: Dictionary = {}
var _shapes: Dictionary = {}
var _rebuild_pending := false
## Point and spot lights the level built: what the light fade applies to.
var _positional_lights: Array[Light3D] = []
## The distance lights fade out past, as last applied; 0 when they do not.
var light_fade_applied_m := 0.0
## Stands in for the renderer the game runs on (tests).
var _rendering_method_override := ""

func _ready() -> void:
	if Engine.is_editor_hint():
		_preview()
	elif load_on_ready and not manifest_path.is_empty():
		load_level(manifest_path)

## Replaces whatever this node holds with the level at [param path]. Returns
## how many placements were built: 0 for a level that could not be read.
func load_level(path: String) -> int:
	clear()
	_meshes.clear()
	_shapes.clear()
	var manifest := _read_manifest(path)
	if manifest.is_empty():
		return 0
	if lod_distances_m.x > 0.0 and chunk_size_m <= 0.0:
		push_warning("VoxiGenLevel: level of detail needs chunk_size_m above 0; with one batch per module, every module switches at once")

	var base_dir := path.get_base_dir()
	var meshes := {}  # module name -> [full, lod1, lod2] (lods may be null)
	var failed := {}  # module names whose GLB did not load
	var module_lights := {}
	for entry: Variant in _array(manifest.get("modules")):
		if typeof(entry) != TYPE_DICTIONARY:
			push_warning("VoxiGenLevel: a module entry that is not an object was skipped")
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
		if not _allowed(base_dir, full_path):
			push_warning("VoxiGenLevel: module '%s' points outside the level folder; skipped" % name)
			failed[name] = true
			continue
		var mesh := _load_mesh(full_path)
		if mesh == null:
			failed[name] = true
			continue
		var lods: Array = [mesh, null, null]
		var named := _array(module.get("lods"))
		for k in [1, 2]:
			var lod_path := full_path.trim_suffix(".glb") + ".lod%d.glb" % k
			if named.size() >= k:
				lod_path = _resolve(base_dir, str(named[k - 1]))
			if _allowed(base_dir, lod_path) and _file_exists(lod_path):
				lods[k] = _load_mesh(lod_path)
		meshes[name] = lods
		var carried := _array(module.get("lights"))
		if not carried.is_empty():
			module_lights[name] = carried

	# Placements, grouped by module and cell: a MultiMesh draws one mesh.
	var batches := {}  # [module, cell] -> Array[Transform3D]
	var placed := 0
	for entry: Variant in _array(manifest.get("placements")):
		if typeof(entry) != TYPE_DICTIONARY:
			push_warning("VoxiGenLevel: a placement that is not an object was skipped")
			continue
		var placement := entry as Dictionary
		var module := str(placement.get("module", ""))
		var position := _numbers(placement.get("position"), 3)
		var rotation := _numbers(placement.get("rotation"), 4)
		if position.is_empty() or rotation.is_empty():
			push_warning("VoxiGenLevel: a placement of '%s' with a malformed position or rotation was skipped" % module)
			continue
		var pose := _pose_of(position, rotation)
		if _is_marker(module):
			_add_marker(module, _rigid(pose))
			continue
		if not meshes.has(module):
			if not failed.has(module):
				push_warning("VoxiGenLevel: a placement names unknown module '%s'; skipped" % module)
			continue
		var key := [module, _cell_of(pose.origin)]
		if not batches.has(key):
			batches[key] = []
		batches[key].append(pose)
		placed += 1
		for light: Variant in module_lights.get(module, []):
			_add_light(light, _rigid(pose))

	for key: Array in batches:
		_add_batch(key[0], key[1], meshes[key[0]], batches[key])

	for light: Variant in _array(manifest.get("lights")):
		_add_light(light)

	for child in get_children():
		if child.has_meta("voxigen_level") and (child is OmniLight3D or child is SpotLight3D):
			_positional_lights.append(child)
	_apply_light_fade()
	if not light_fade_active() and light_budget > 0 and _positional_lights.size() > light_budget \
			and _rendering_method() != "forward_plus" and not Engine.is_editor_hint():
		push_warning("VoxiGenLevel: %d lights on the %s renderer with the light fade off; past %d in view, lights go missing and the level can render dark." \
			% [_positional_lights.size(), _rendering_method(), light_budget])

	level_loaded.emit(meshes.size(), placed)
	return placed

## Removes the level this node built.
func clear() -> void:
	_positional_lights.clear()
	light_fade_applied_m = 0.0
	for child in get_children():
		if child.has_meta("voxigen_level"):
			remove_child(child)
			child.queue_free()

## True when lights fade with distance here: on Mobile or Compatibility under
## Auto, on any renderer under Always; never in the editor, which shows the
## level as built.
func light_fade_active() -> bool:
	if Engine.is_editor_hint() or light_budget <= 0 or light_fade_mode == 2:
		return false
	return light_fade_mode == 1 or _rendering_method() != "forward_plus"

func _rendering_method() -> String:
	if not _rendering_method_override.is_empty():
		return _rendering_method_override
	return RenderingServer.get_current_rendering_method()

# Sets every light's distance fade from the current settings. It shares
# Godot's distance fade with shadow_distance_m: that fades only the shadow
# (distance_fade_shadow, never touched here), so turning the light fade off
# puts back the shadow-only fade rather than none.
func _apply_light_fade() -> void:
	var distance := 0.0
	if light_fade_active() and not _positional_lights.is_empty():
		distance = light_fade_distance_m if light_fade_distance_m > 0.0 else fade_distance_for(light_budget)
	light_fade_applied_m = distance
	for light in _positional_lights:
		if not is_instance_valid(light):
			continue
		if distance > 0.0:
			light.distance_fade_enabled = true
			light.distance_fade_begin = distance
			light.distance_fade_length = maxf(light_fade_length_m, 0.01)
		elif light.get_meta("voxigen_shadow_fade", false):
			light.distance_fade_enabled = true
			light.distance_fade_begin = NO_LIGHT_FADE_M
			light.distance_fade_length = maxf(shadow_distance_m * 0.25, 0.01)
		else:
			light.distance_fade_enabled = false

## The farthest of [constant LIGHT_FADE_STEPS] at which no light of this level
## has more than [param budget] lights (itself included) within the fade's
## reach, counting the fade length. A camera stands near some light, so that
## bounds what it can see. The nearest step, with a warning, when none fits.
func fade_distance_for(budget: int) -> float:
	var positions := PackedVector3Array()
	for light in _positional_lights:
		positions.append(light.position)
	var crowd := 0
	for step: float in LIGHT_FADE_STEPS:
		crowd = _most_within(positions, step + light_fade_length_m)
		if crowd <= budget:
			return step
	var nearest: float = LIGHT_FADE_STEPS[-1]
	push_warning("VoxiGenLevel: up to %d lights within %d m of one another; above light_budget (%d) even at the nearest fade. Some lights will go missing on Mobile and Compatibility." \
		% [crowd, int(nearest + light_fade_length_m), budget])
	return nearest

# The most points within `reach` of any one of them, itself included, found
# through a grid of `reach`-sized cells: only neighbouring cells can hold one.
func _most_within(points: PackedVector3Array, reach: float) -> int:
	var cells := {}
	for i in points.size():
		var key := Vector3i((points[i] / reach).floor())
		if not cells.has(key):
			cells[key] = PackedInt32Array()
		cells[key].append(i)
	var most := 0
	for i in points.size():
		var home := Vector3i((points[i] / reach).floor())
		var count := 0
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for j: int in cells.get(home + Vector3i(dx, dy, dz), PackedInt32Array()):
						if points[i].distance_to(points[j]) <= reach:
							count += 1
		most = maxi(most, count)
	return most

func _changed() -> void:
	# Once per frame however many settings change in it: dragging a slider in
	# the inspector would otherwise rebuild the level on every step.
	if is_inside_tree() and Engine.is_editor_hint() and not _rebuild_pending:
		_rebuild_pending = true
		_preview.call_deferred()

func _preview() -> void:
	_rebuild_pending = false
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
	var version := int(manifest.get("version", 0)) if typeof(manifest.get("version")) in [TYPE_INT, TYPE_FLOAT] else 0
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

# A manifest field that should be an array: itself, or empty if it is missing
# or anything else.
func _array(value: Variant) -> Array:
	return value as Array if value is Array else []

# `count` numbers from a manifest array, or an empty array if it is not exactly
# that: a short or mistyped vector is skipped, never read as zeros.
func _numbers(value: Variant, count: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if not value is Array or (value as Array).size() != count:
		return out
	for item: Variant in value:
		if not _sane(item):
			return PackedFloat64Array()
		out.append(float(item))
	return out

func _resolve(base_dir: String, file: String) -> String:
	return base_dir.path_join(file).simplify_path()

func _allowed(base_dir: String, path: String) -> bool:
	if not confine_to_level_folder or _in_project(base_dir + "/"):
		return true
	var root := base_dir.simplify_path().trim_suffix("/") + "/"
	return path.begins_with(root)

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
# copied with its materials told to use it. A textured export carries no
# vertex colour and is left as it is.
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
		push_error("VoxiGenLevel: module %s failed to load; its placements are skipped" % path)
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
		push_error("VoxiGenLevel: module %s has no mesh; its placements are skipped" % path)
		_meshes[path] = null
		return null
	var mesh := source.duplicate() as Mesh
	for i in mesh.get_surface_count():
		var material := mesh.surface_get_material(i) as BaseMaterial3D
		if material and mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR:
			material = material.duplicate() as BaseMaterial3D
			material.vertex_color_use_as_albedo = true
			mesh.surface_set_material(i, material)
	_meshes[path] = mesh
	return mesh

# Voxels to metres, and the manifest's xyzw quaternion to a basis. The scale is
# in the pose so a placement draws at its size; collision gets rigid poses and
# a shape already in metres instead (_shape_of), since physics shapes should
# not be scaled.
func _pose_of(p: PackedFloat64Array, q: PackedFloat64Array) -> Transform3D:
	var rotation := Quaternion(q[0], q[1], q[2], q[3])
	rotation = rotation.normalized() if rotation.length_squared() > 0.0 else Quaternion.IDENTITY
	var origin := Vector3(p[0], p[1], p[2]) * voxel_size_m
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
			# No margins: without a fade, Godot treats a margin as hysteresis
			# that can leave every detail of a module hidden until the camera
			# crosses a switch distance (tests/visual_check.gd).
		_own(node)

	if not collision or Engine.is_editor_hint():
		return
	var shape := _shape_of(lods[0])
	if shape == null:
		return
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

# A module's collision shape, in metres: built once per mesh and shared by every
# placement in every chunk, unscaled, at rigid poses.
func _shape_of(mesh: Mesh) -> ConcavePolygonShape3D:
	if _shapes.has(mesh):
		return _shapes[mesh]
	var faces := mesh.get_faces()
	for i in faces.size():
		faces[i] *= voxel_size_m
	var shape: ConcavePolygonShape3D = null
	if not faces.is_empty():
		shape = ConcavePolygonShape3D.new()
		shape.set_faces(faces)
	_shapes[mesh] = shape
	return shape

# A light in voxels, right-handed: the level's own in the placements' frame, or
# a module's in its GLB's frame with `at` the placement carrying it. Godot's
# lights shine down their own -Z, so spot and directional lights are turned to
# look along the manifest's direction.
func _add_light(entry: Variant, at: Transform3D = Transform3D.IDENTITY) -> Light3D:
	if typeof(entry) != TYPE_DICTIONARY:
		push_warning("VoxiGenLevel: a light that is not an object was skipped")
		return null
	var light := entry as Dictionary
	var type := str(light.get("type", ""))
	var position := _numbers(light.get("position", [0, 0, 0]), 3)
	var direction := _numbers(light.get("direction", [0, -1, 0]), 3)
	var color := _numbers(light.get("color", [1, 1, 1]), 3)
	if position.is_empty() or direction.is_empty() or color.is_empty():
		push_warning("VoxiGenLevel: a %s light with a malformed position, direction or colour was skipped" % type)
		return null
	# Every value read and checked before a node exists, so nothing below can
	# fail half-way and leave a light built but never added.
	var shadow: Variant = light.get("castsShadow", false)
	var casts_shadow: bool = typeof(shadow) == TYPE_BOOL and bool(shadow)
	var range_m := _number(light, "range", 0.0) * voxel_size_m * light_range_scale
	var energy := _number(light, "intensity", 1.0) * light_energy_scale
	var outer_deg := clampf(_number(light, "outerDegrees", 45.0), 0.0, 180.0)
	var inner_deg := clampf(_number(light, "innerDegrees", 0.0), 0.0, outer_deg) if light.has("innerDegrees") else -1.0
	var node: Light3D
	match type:
		"point":
			var omni := OmniLight3D.new()
			omni.omni_range = range_m
			node = omni
		"spot":
			var spot := SpotLight3D.new()
			spot.spot_range = range_m
			spot.spot_angle = outer_deg
			# Godot has angular attenuation rather than an inner cone; this is
			# the approximation its own glTF light importer uses.
			if inner_deg >= 0.0:
				var ratio := inner_deg / outer_deg if outer_deg > 0.0 else 0.0
				spot.spot_angle_attenuation = 0.2 / maxf(1.0 - ratio, 0.000001) - 0.1
			node = spot
		"directional":
			node = DirectionalLight3D.new()
		_:
			push_warning("VoxiGenLevel: a light of unknown type '%s' was skipped" % type)
			return null
	node.light_color = Color(color[0], color[1], color[2])
	node.light_energy = energy
	node.shadow_enabled = casts_shadow
	if node.shadow_enabled and type != "directional" and shadow_distance_m > 0.0:
		node.set_meta("voxigen_shadow_fade", true)
		node.distance_fade_enabled = true
		node.distance_fade_shadow = shadow_distance_m
		node.distance_fade_begin = NO_LIGHT_FADE_M
		node.distance_fade_length = maxf(shadow_distance_m * 0.25, 0.01)
	node.position = Vector3(position[0], position[1], position[2]) * voxel_size_m
	if type != "point":
		var dir := Vector3(direction[0], direction[1], direction[2]).normalized()
		if dir.length() > 0.0:
			var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
			node.basis = Basis.looking_at(dir, up)
	node.transform = at * node.transform
	node.name = type + "_light"
	_own(node)
	return node

func _number(from: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = from.get(key, fallback)
	return float(value) if _sane(value) else fallback

# A number a manifest may state: an int or float, finite and within MAX_MAGNITUDE.
func _sane(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and absf(number) <= MAX_MAGNITUDE
