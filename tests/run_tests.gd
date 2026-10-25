extends SceneTree

# godot --headless --path . -s tests/run_tests.gd
#
# Builds generated levels with VoxiGenLevel and checks what it made. Exits 1 on
# any failure. Headless, a MultiMesh reads its transforms back as zero, so poses
# are checked on the collision shapes, which carry the same placements.

const Fixtures := preload("res://tests/fixtures.gd")
const S := 1.0 / 32.0
## Raise it when adding checks.
const MIN_CHECKS := 70

var failures := 0
var checks := 0

func _initialize() -> void:
	_test_level("user://voxigen_tests/runtime", "loads from disk at runtime")
	if ResourceLoader.exists("res://tests/generated/modules/cube.glb"):
		_test_level("res://tests/generated", "loads GLBs Godot imported", false)
	else:
		failures += 1
		print("  FAIL  no imported fixture: run tests/generate.gd and --import first (see README)")
	_test_lod()
	_test_versions()
	_test_no_chunks()
	_test_reload()
	_test_malformed()
	_test_shared_shapes()
	_test_spot()
	_test_light_fade()
	_test_textured_and_broken()
	_test_hostile()
	# A script error (the add-on failing to compile, say) skips checks rather
	# than failing them, so passing also needs every check to have run.
	if checks < MIN_CHECKS:
		failures += 1
		print("  FAIL  only %d checks ran, expected at least %d: look for script errors above" % [checks, MIN_CHECKS])
	print("\n%s (%d checks)" % ["ALL PASSED" if failures == 0 else "%d FAILED" % failures, checks])
	quit(1 if failures else 0)

func _check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  ok    ", what)
	else:
		failures += 1
		print("  FAIL  ", what)

func _near(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) < 0.001

func _level(path: String, settings := {}) -> VoxiGenLevel:
	var level := VoxiGenLevel.new()
	level.load_on_ready = false
	level.chunk_size_m = 16.0  # the fixture places its far cube 32 m out
	for key: String in settings:
		level.set(key, settings[key])
	root.add_child(level)
	return level

func _of(level: Node, type: String) -> Array:
	return level.find_children("*", type, true, false)

func _test_level(dir: String, label: String, write := true) -> void:
	print("level: ", label)
	var path := Fixtures.write_level(dir) if write else dir.path_join("level.json")
	var level := _level(path)
	var markers := []
	level.marker_found.connect(func(name: String, at: Transform3D) -> void: markers.append([name, at]))
	var placed := level.load_level(path)

	_check(placed == 4, "builds the 4 placements of known modules (got %d)" % placed)

	var instances := 0
	for node: MultiMeshInstance3D in _of(level, "MultiMeshInstance3D"):
		instances += node.multimesh.instance_count
	_check(instances == 4, "batches hold every placement once (got %d)" % instances)
	_check(level.get_node_or_null("cube_0_0_0") != null and level.get_node_or_null("cube_2_0_0") != null,
		"splits the far cube into its own 16 m chunk")

	var cube := level.get_node("cube_0_0_0") as MultiMeshInstance3D
	var material := cube.multimesh.mesh.surface_get_material(0) as BaseMaterial3D
	_check(material != null and material.vertex_color_use_as_albedo, "draws VoxiGen's vertex colours")

	_check(markers.size() == 1 and markers[0][0] == "marker_spawn_player", "reports the marker")
	var marker := level.get_node_or_null("marker_spawn_player") as Marker3D
	_check(marker != null and _near(marker.position, Vector3(16, 32, 16) * S), "places the marker in metres")
	_check(marker != null and marker.basis.get_scale().is_equal_approx(Vector3.ONE), "leaves the marker unscaled")

	var omni := _of(level, "OmniLight3D")
	# The lamp stands at (64, 32, 0), turned 90° about Y; its light at (0, 10, 4)
	# in the module turns to (4, 10, 0).
	_check(omni.size() == 1 and _near((omni[0] as Node3D).position, Vector3(68, 42, 0) * S),
		"poses a module's light with its placement")
	_check(omni.size() == 1 and is_equal_approx((omni[0] as OmniLight3D).omni_range, 240 * S),
		"scales light range to metres")
	var sun := _of(level, "DirectionalLight3D")
	_check(sun.size() == 1 and _near(-(sun[0] as Node3D).basis.z, Vector3.DOWN), "aims the level's directional light")

	var shapes := _of(level, "CollisionShape3D")
	_check(shapes.size() == 4, "gives each placement collision (got %d)" % shapes.size())
	var far: CollisionShape3D = null
	for s: CollisionShape3D in shapes:
		if s.position.x > 30.0:
			far = s
	_check(far != null and _near(far.position, Vector3(1024, 0, 0) * S), "places collision in metres")
	_check(far != null and far.basis.get_scale().is_equal_approx(Vector3.ONE), "keeps collision shapes unscaled")
	var faces := (shapes[0].shape as ConcavePolygonShape3D).get_faces()
	var top := -INF
	for v in faces:
		top = maxf(top, v.y)
	_check(is_equal_approx(top, 32 * S), "builds collision faces in metres (top %.3f m)" % top)

	_check(_of(level, "MultiMeshInstance3D").all(func(n: Node) -> bool: return not n.name.contains("lod")),
		"draws full meshes only while level of detail is off")

	# What the editor's preview builds has no owner, so saving the scene keeps
	# only the node and its settings; the game builds the level when it runs.
	var packed := PackedScene.new()
	packed.pack(level)
	var saved := packed.instantiate()
	_check(saved.get_child_count() == 0, "saving the scene does not save the built level")
	saved.free()

	level.clear()
	_check(level.get_child_count() == 0, "clear() removes the level")
	level.free()

func _test_lod() -> void:
	print("level: level of detail")
	var path := Fixtures.write_level("user://voxigen_tests/lod")
	var level := _level(path, {"lod_distances_m": Vector2(10, 20)})
	level.load_level(path)
	var full := level.get_node_or_null("cube_0_0_0") as GeometryInstance3D
	var half := level.get_node_or_null("cube_0_0_0_lod1") as GeometryInstance3D
	var quarter := level.get_node_or_null("cube_0_0_0_lod2") as GeometryInstance3D
	_check(full != null and is_equal_approx(full.visibility_range_end, 10.0), "full mesh ends at 10 m")
	_check(half != null and is_equal_approx(half.visibility_range_begin, 10.0) \
		and is_equal_approx(half.visibility_range_end, 20.0), "half-detail mesh covers 10–20 m")
	_check(quarter != null and is_equal_approx(quarter.visibility_range_begin, 20.0), "quarter-detail mesh from 20 m")
	_check(level.get_node_or_null("lamp_2_1_0_lod1") == null, "a module exported without LODs stays whole")
	level.free()

	level = _level(path, {"lod_distances_m": Vector2(10, 0)})
	level.load_level(path)
	_check(level.get_node_or_null("cube_0_0_0_lod2") == null \
		and is_equal_approx((level.get_node("cube_0_0_0_lod1") as GeometryInstance3D).visibility_range_end, 0.0),
		"without a second distance, half detail draws to any distance")
	level.free()

func _test_versions() -> void:
	print("level: manifest versions")
	var path := Fixtures.write_level("user://voxigen_tests/v4", 4)
	var level := _level(path)
	_check(level.load_level(path) == 0 and level.get_child_count() == 0, "refuses a newer manifest")
	level.free()

	path = Fixtures.write_level("user://voxigen_tests/v1", 1)
	level = _level(path)
	_check(level.load_level(path) == 4 and _of(level, "Light3D").is_empty(), "reads a version 1 manifest (no lights)")
	level.free()

	level = _level("")
	_check(level.load_level("user://voxigen_tests/nothing_here.json") == 0, "returns 0 for a missing manifest")
	level.free()

func _test_no_chunks() -> void:
	print("level: one batch per module")
	var path := Fixtures.write_level("user://voxigen_tests/nochunk")
	var level := _level(path, {"chunk_size_m": 0.0, "collision": false})
	level.load_level(path)
	var cube := level.get_node_or_null("cube") as MultiMeshInstance3D
	_check(cube != null and cube.multimesh.instance_count == 3, "chunk_size_m 0 batches a module whole")
	_check(_of(level, "CollisionShape3D").is_empty(), "collision off builds no shapes")
	level.collision = true
	level.voxel_size_m = 1.0 / 16.0
	level.load_level(path)
	var top := -INF
	for v in ((_of(level, "CollisionShape3D")[0] as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces():
		top = maxf(top, v.y)
	_check(is_equal_approx(top, 32.0 / 16.0), "collision follows a changed voxel size")
	level.free()

func _top_of_collision(level: Node) -> float:
	var top := -INF
	for v in ((_of(level, "CollisionShape3D")[0] as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces():
		top = maxf(top, v.y)
	return top

func _test_reload() -> void:
	print("level: re-exported to the same path")
	var dir := "user://voxigen_tests/reload"
	var path := Fixtures.write_level(dir)
	var level := _level(path)
	level.load_level(path)
	var before := _top_of_collision(level)
	# The same file names, a different cube: what a re-export does.
	Fixtures._write_glb(dir.path_join("modules/cube.glb"), 64.0, Color.BLUE)
	level.load_level(path)
	_check(is_equal_approx(before, 32 * S) and is_equal_approx(_top_of_collision(level), 64 * S),
		"reloading reads the module again, not a cached copy")
	level.free()

func _test_malformed() -> void:
	print("level: malformed manifest entries")
	var dir := "user://voxigen_tests/malformed"
	Fixtures.write_level(dir)
	var path := Fixtures.write_manifest(dir, {
		"modules": [
			{"name": "cube", "file": "modules/cube.glb", "lods": null, "lights": "torch"},
			"not a module",
		],
		"placements": [
			{"module": "cube", "position": [0, 0, 0], "rotation": [0, 0, 0, 1]},
			{"module": "cube", "position": [32, 0], "rotation": [0, 0, 0, 1]},
			{"module": "cube", "position": [64, 0, 0], "rotation": "none"},
			{"module": "cube", "position": [96, "0", 0], "rotation": [0, 0, 0, 1]},
			{"module": "cube", "position": [128, 0, 0], "rotation": [0, 0, 0, 0]},
			42,
		],
		"lights": [
			{"type": "point", "position": [0, 0], "color": [1, 1, 1], "range": 10},
			{"type": "point", "position": [0, 8, 0], "color": [1, 1, 1], "range": "far", "intensity": null},
			"sun",
		],
	})
	var level := _level(path)
	var placed := level.load_level(path)
	_check(placed == 2, "builds only the well-formed placements (got %d)" % placed)
	var origins := []
	for shape: CollisionShape3D in _of(level, "CollisionShape3D"):
		origins.append(shape.position)
	_check(origins.size() == 2 and origins.all(func(o: Vector3) -> bool: return o.x < 0.01 or _near(o, Vector3(128, 0, 0) * S)),
		"never builds a bad placement at the origin at the wrong scale")
	var lights := _of(level, "OmniLight3D")
	_check(lights.size() == 1 and is_equal_approx((lights[0] as OmniLight3D).omni_range, 0.0) \
		and is_equal_approx((lights[0] as OmniLight3D).light_energy, 1.0),
		"skips a malformed light; falls back on a mistyped number")
	_check(level.get_node_or_null("cube_lod1") == null, "a null lods list means none")
	level.free()

func _test_shared_shapes() -> void:
	print("level: collision shared across chunks")
	var path := Fixtures.write_level("user://voxigen_tests/shared")
	var level := _level(path)
	level.load_level(path)
	var cube_shapes := {}
	for shape: CollisionShape3D in _of(level, "CollisionShape3D"):
		if shape.get_parent().name.begins_with("cube"):
			cube_shapes[shape.shape] = true
	_check(level.get_node_or_null("cube_0_0_0_collision") != null and level.get_node_or_null("cube_2_0_0_collision") != null \
		and cube_shapes.size() == 1, "every chunk's placements share one shape per module")
	level.free()

func _test_spot() -> void:
	print("level: spot light")
	var dir := "user://voxigen_tests/spot"
	Fixtures.write_level(dir)
	var path := Fixtures.write_manifest(dir, {"lights": [
		{"type": "spot", "position": [0, 64, 0], "direction": [1, 0, 0], "color": [1, 1, 1],
			"intensity": 3, "range": 320, "innerDegrees": 20, "outerDegrees": 40, "castsShadow": false},
		{"type": "spot", "position": [0, 0, 0], "direction": [0, -1, 0], "color": [1, 1, 1],
			"intensity": 1, "range": 32, "innerDegrees": 40, "outerDegrees": 40, "castsShadow": false},
	]})
	var level := _level(path)
	level.load_level(path)
	var spots := _of(level, "SpotLight3D")
	var spot := spots[0] as SpotLight3D if spots.size() == 2 else null
	_check(spot != null and is_equal_approx(spot.spot_angle, 40.0) and is_equal_approx(spot.spot_range, 10.0),
		"spot: outer angle and range in metres")
	_check(spot != null and is_equal_approx(spot.spot_angle_attenuation, 0.2 / 0.5 - 0.1),
		"spot: inner cone becomes Godot's angular attenuation")
	_check(spot != null and _near(-spot.basis.z, Vector3.RIGHT), "spot: shines along its direction")
	_check(spots.size() == 2 and is_finite((spots[1] as SpotLight3D).spot_angle_attenuation),
		"spot: a hard edge (inner = outer) stays finite")
	level.free()

func _test_light_fade() -> void:
	print("level: light fade")
	var dir := "user://voxigen_tests/light_fade"
	Fixtures.write_level(dir)
	# Ten lights in a row, 10 m (320 voxels) apart; the first casts a shadow.
	var lights := []
	for i in 10:
		lights.append({"type": "point", "position": [i * 320, 32, 0], "color": [1, 1, 1], "range": 128,
			"castsShadow": i == 0})
	var path := Fixtures.write_manifest(dir, {"lights": lights})
	var level := _level(path, {"light_budget": 3, "light_fade_length_m": 2.0, "shadow_distance_m": 12.0})
	level._rendering_method_override = "gl_compatibility"
	level.load_level(path)
	var omni := _of(level, "OmniLight3D")
	_check(level.light_fade_active(), "Auto fades lights on Compatibility")
	# 16 m (+2 m of fade) reaches a light's two neighbours; 20 m would reach four.
	_check(is_equal_approx(level.light_fade_applied_m, 16.0), "fades from the farthest distance that keeps the budget")
	_check(omni.size() == 10 and omni.all(func(l: OmniLight3D) -> bool: return l.distance_fade_enabled \
		and is_equal_approx(l.distance_fade_begin, 16.0) and is_equal_approx(l.distance_fade_length, 2.0)),
		"every light fades from there")
	var shadowed := omni.filter(func(l: OmniLight3D) -> bool: return l.shadow_enabled)
	_check(shadowed.size() == 1 and is_equal_approx((shadowed[0] as OmniLight3D).distance_fade_shadow, 12.0),
		"the shadow fade is kept alongside")
	level.light_fade_distance_m = 30.0
	_check(is_equal_approx(level.light_fade_applied_m, 30.0) and is_equal_approx((omni[3] as OmniLight3D).distance_fade_begin, 30.0),
		"a set distance overrides the computed one")
	level.light_fade_mode = 2
	_check(not level.light_fade_active() and is_equal_approx(level.light_fade_applied_m, 0.0) \
		and omni.filter(func(l: OmniLight3D) -> bool: return not l.shadow_enabled).all(
			func(l: OmniLight3D) -> bool: return not l.distance_fade_enabled),
		"Never turns the fade back off")
	var shadow := shadowed[0] as OmniLight3D
	_check(shadow.distance_fade_enabled and shadow.distance_fade_begin > 1000.0 and is_equal_approx(shadow.distance_fade_shadow, 12.0),
		"Never puts the shadow-only fade back")
	level.light_fade_mode = 0
	level._rendering_method_override = "forward_plus"
	level.load_level(path)
	_check(not level.light_fade_active() and _of(level, "OmniLight3D").all(
		func(l: OmniLight3D) -> bool: return l.shadow_enabled or not l.distance_fade_enabled),
		"Auto leaves Forward+ as built")
	level.free()

func _test_textured_and_broken() -> void:
	print("level: textured and broken modules")
	var dir := "user://voxigen_tests/textured"
	Fixtures.write_level(dir)
	Fixtures.write_textured_glb(dir.path_join("modules/tile.glb"), 32.0)
	Fixtures.write_broken_glb(dir.path_join("modules/broken.glb"))
	var path := Fixtures.write_manifest(dir, {
		"modules": [
			{"name": "tile", "file": "modules/tile.glb"},
			{"name": "broken", "file": "modules/broken.glb"},
		],
		"placements": [
			{"module": "tile", "position": [0, 0, 0], "rotation": [0, 0, 0, 1]},
			{"module": "broken", "position": [32, 0, 0], "rotation": [0, 0, 0, 1]},
		],
	})
	var level := _level(path)
	var placed := level.load_level(path)
	var tile := level.get_node_or_null("tile_0_0_0") as MultiMeshInstance3D
	var material := tile.multimesh.mesh.surface_get_material(0) as BaseMaterial3D if tile else null
	_check(material != null and material.albedo_texture != null and not material.vertex_color_use_as_albedo,
		"a textured module keeps its texture, without vertex colour")
	_check(placed == 1 and level.get_node_or_null("broken_1_0_0") == null,
		"a module that fails to load is skipped, the rest still built")
	level.free()

func _test_hostile() -> void:
	print("level: hostile manifest")
	var dir := "user://voxigen_tests/hostile"
	Fixtures.write_level(dir)
	var outside := "user://voxigen_tests/outside"
	DirAccess.make_dir_recursive_absolute(outside)
	Fixtures._write_glb(outside.path_join("secret.glb"), 32.0, Color.RED)
	var path := Fixtures.write_manifest(dir, {
		"modules": [
			{"name": "cube", "file": "modules/cube.glb",
				"lights": [{"type": "point", "position": [0, 8, 0], "color": [1, 1, 1], "range": 64, "castsShadow": "yes"}]},
			{"name": "secret", "file": "../outside/secret.glb"},
		],
		"placements": [
			{"module": "cube", "position": [0, 0, 0], "rotation": [0, 0, 0, 1]},
			{"module": "cube", "position": [1e300, 0, 0], "rotation": [0, 0, 0, 1]},
			{"module": "secret", "position": [0, 0, 0], "rotation": [0, 0, 0, 1]},
		],
		"lights": [{"type": "point", "position": [0, 0, 0], "color": [1, 1, 1], "range": 1e300}],
	})
	var level := _level(path)
	var placed := level.load_level(path)
	_check(placed == 1, "builds only the one sound placement (got %d)" % placed)
	var omni := _of(level, "OmniLight3D")
	_check(omni.size() == 2 and not (omni[0] as Light3D).shadow_enabled,
		"a non-bool castsShadow means no shadow, and the light is still built")
	_check(omni.size() == 2 and is_finite((omni[1] as OmniLight3D).omni_range),
		"a non-finite range falls back instead of building an infinite light")
	_check(level.get_node_or_null("secret_0_0_0") == null, "refuses a module outside the level folder")
	level.free()

	level = _level(path, {"confine_to_level_folder": false})
	_check(level.load_level(path) == 2, "confine_to_level_folder off allows a shared folder outside")
	level.free()
