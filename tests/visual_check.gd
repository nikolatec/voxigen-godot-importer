extends SceneTree

# godot --path . -s tests/visual_check.gd      (needs a window, not --headless)
#
# What the headless tests cannot see: whether a level draws. Renders the test
# level (res://tests/generated, see README) with level of detail off and on,
# from a camera near the cube, and checks the cube's colour is on screen.
# Level of detail once drew nothing at all here, while every headless check
# passed.

const CUBE := Color(0.8, 0.2, 0.1)
var failures := 0

func _initialize() -> void:
	for lod: Vector2 in [Vector2.ZERO, Vector2(4, 8), Vector2(1, 2)]:
		var level := VoxiGenLevel.new()
		level.load_on_ready = false
		level.voxel_size_m = 1.0 / 16.0
		level.chunk_size_m = 16.0
		level.lod_distances_m = lod
		root.add_child(level)
		level.load_level("res://tests/generated/level.json")
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.look_at_from_position(Vector3(3, 2.2, 3), Vector3(1, 1, 0))
		cam.make_current()
		var light := DirectionalLight3D.new()
		root.add_child(light)
		light.look_at_from_position(Vector3(0, 5, 5), Vector3.ZERO)
		for i in 10:
			await process_frame
		var image := root.get_viewport().get_texture().get_image()
		var seen := 0
		for y in range(0, image.get_height(), 4):
			for x in range(0, image.get_width(), 4):
				var c := image.get_pixel(x, y)
				if c.r > 0.3 and c.r > c.g * 1.8 and c.r > c.b * 1.8:
					seen += 1
		var ok := seen > 100
		if not ok:
			failures += 1
		print("  %s  level of detail %s: %d cube pixels" % ["ok  " if ok else "FAIL", lod, seen])
		level.free()
		cam.free()
		light.free()
	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
