extends SceneTree

# godot --headless --path . -s tests/generate.gd && godot --headless --path . --import
#
# Writes the test level into the project (res://tests/generated), where Godot
# imports its GLBs the way a user's levels are imported, so run_tests.gd can
# check that path as well as loading from disk at runtime.

const Fixtures := preload("res://tests/fixtures.gd")

func _initialize() -> void:
	Fixtures.write_level("res://tests/generated")
	quit()
