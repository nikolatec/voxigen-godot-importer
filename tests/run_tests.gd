extends SceneTree

# godot --headless --path . -s tests/run_tests.gd
#
# Builds generated levels with VoxiGenLevel and checks what it made. Exits 1 on
# any failure. Headless, a MultiMesh reads its transforms back as zero, so poses
# are checked on the collision shapes, which carry the same placements.

const Fixtures := preload("res://tests/fixtures.gd")
const S := 1.0 / 32.0

var failures := 0

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
	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)

func _check(ok: bool, what: String) -> void:
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
