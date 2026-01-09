## Headless tool: print classic ruleset ship names + count.
##
## Run:
##   godot --headless --quit --path . --script res://tools/print_classic_ruleset_ships.gd

extends SceneTree

const DriftClassicRuleset = preload("res://shared/drift_classic_ruleset.gd")


func _initialize() -> void:
	var loader := DriftClassicRuleset.new()
	if not loader.load():
		push_error("[CLASSIC] load failed")
		quit(1)
		return

	var names: PackedStringArray = loader.get_loaded_ship_names()
	print("Classic ships loaded: ", names.size())
	for n in names:
		print("- ", n)
	quit(0)
