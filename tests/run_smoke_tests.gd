## Headless smoke tests for Driftline runtime semantics.
##
## These tests are NOT contract-vector tests; they assert higher-level invariants.
##
## Run:
##   godot --headless --quit --path . --script res://tests/run_smoke_tests.gd

extends SceneTree

const DriftNet = preload("res://shared/drift_net.gd")
const DriftRuleset = preload("res://shared/drift_ruleset.gd")
const DriftValidate = preload("res://shared/drift_validate.gd")
const DriftWorld = preload("res://shared/drift_world.gd")
const DriftTypes = preload("res://shared/drift_types.gd")

var _failures: int = 0
var _ran: int = 0


func _initialize() -> void:
	_test_controls_actions_present()
	_test_controls_default_bindings_wasd()
	_test_controls_weapon_defaults_present()
	_test_no_hardcoded_keys_in_gameplay()
	_test_welcome_includes_ruleset_payload()
	_test_prizes_spawn_walkable()
	print("[SMOKE] Done: ", _ran, " checks, ", _failures, " failures")
	quit(0 if _failures == 0 else 1)


func _test_controls_actions_present() -> void:
	_ran += 1
	var required := [
		"drift_thrust_forward",
		"drift_thrust_reverse",
		"drift_rotate_left",
		"drift_rotate_right",
		"drift_fire_primary",
		"drift_fire_secondary",
		"drift_modifier_ability",
	]
	for a in required:
		if not InputMap.has_action(a):
			_fail("controls_actions_present (missing action: %s)" % a)
			return
	_pass("controls_actions_present")


func _test_controls_default_bindings_wasd() -> void:
	_ran += 1
	# Strict default bindings (WASD). These are project defaults, not user remaps.
	# physical_keycode values:
	#   W=87, A=65, S=83, D=68
	var expected := {
		"drift_thrust_forward": 87,
		"drift_thrust_reverse": 83,
		"drift_rotate_left": 65,
		"drift_rotate_right": 68,
	}
	for action_name in expected.keys():
		var events: Array = InputMap.action_get_events(StringName(action_name))
		if events.size() != 1:
			_fail("controls_default_bindings_wasd (action %s expected exactly 1 event, got %d)" % [action_name, events.size()])
			return
		var ev = events[0]
		if not (ev is InputEventKey):
			_fail("controls_default_bindings_wasd (action %s event is not InputEventKey)" % action_name)
			return
		var k := ev as InputEventKey
		if int(k.physical_keycode) != int(expected[action_name]):
			_fail("controls_default_bindings_wasd (action %s physical_keycode=%d expected %d)" % [action_name, int(k.physical_keycode), int(expected[action_name])])
			return
		# Must not require modifiers.
		if k.shift_pressed or k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
			_fail("controls_default_bindings_wasd (action %s unexpectedly requires modifiers)" % action_name)
			return
	_pass("controls_default_bindings_wasd")


func _test_controls_weapon_defaults_present() -> void:
	_ran += 1
	# Weapons must have a default binding (still rebindable in InputMap).
	var required := [
		"drift_fire_primary",
		"drift_fire_secondary",
	]
	for a in required:
		if not InputMap.has_action(a):
			_fail("controls_weapon_defaults_present (missing action: %s)" % a)
			return
		var events: Array = InputMap.action_get_events(StringName(a))
		if events.size() < 1:
			_fail("controls_weapon_defaults_present (action %s has no default binding)" % a)
			return
	_pass("controls_weapon_defaults_present")


func _test_no_hardcoded_keys_in_gameplay() -> void:
	_ran += 1
	# Enforcement hammer: fail if hardcoded key checks or default ui_* actions creep into gameplay code.
	# We scan gameplay-relevant folders only.
	var scan_roots := [
		"res://client",
		"res://shared",
		"res://server",
	]
	var allowlist := {
		# Designated input layer.
		"res://client/client_main.gd": true,
	}
	var needles := [
		"Input.is_key_pressed(",
		"KEY_",
		"\"ui_left\"",
		"\"ui_right\"",
		"\"ui_up\"",
		"\"ui_down\"",
		"'ui_left'",
		"'ui_right'",
		"'ui_up'",
		"'ui_down'",
	]
	var files: Array = []
	for r in scan_roots:
		_collect_gd_files(r, files)
	files.sort()
	for p in files:
		var path: String = String(p)
		if allowlist.has(path):
			continue
		var text := FileAccess.get_file_as_string(path)
		for n in needles:
			if text.find(String(n)) != -1:
				_fail("no_hardcoded_keys_in_gameplay (found %s in %s)" % [String(n), path])
				return
	_pass("no_hardcoded_keys_in_gameplay")


func _collect_gd_files(root: String, out_files: Array) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect_gd_files(root.path_join(sub), out_files)
	for f in dir.get_files():
		if String(f).ends_with(".gd"):
			out_files.append(root.path_join(f))


func _test_welcome_includes_ruleset_payload() -> void:
	_ran += 1

	# Emulate server behavior: load+validate ruleset and include its canonical JSON in welcome.
	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("welcome_ruleset_payload (failed to load res://rulesets/base.json)")
		return

	var canonical_ruleset: Dictionary = rules_res.get("ruleset", {})
	var ruleset_json: String = JSON.stringify(canonical_ruleset)

	# Requirement: welcome must include either:
	#  (A) non-empty ruleset_json
	#  (B) ruleset_checksum + ruleset_path
	# Driftline currently uses (A). Empty payloads are a failure.
	if ruleset_json.strip_edges() == "":
		_fail("welcome_ruleset_payload (ruleset_json was empty)")
		return

	var packet := DriftNet.pack_welcome_packet(
		1, # ship_id
		PackedByteArray(),
		"res://maps/default.json",
		1,
		0.6,
		ruleset_json,
		float((canonical_ruleset.get("physics", {}) as Dictionary).get("tangent_damping", 0.0)),
	)
	var w: Dictionary = DriftNet.unpack_welcome_packet(packet)
	if w.is_empty():
		_fail("welcome_ruleset_payload (unpack failed)")
		return

	var got_json: String = String(w.get("ruleset_json", "")).strip_edges()
	if got_json == "":
		_fail("welcome_ruleset_payload (welcome missing ruleset_json)")
		return

	# If JSON is included, it must validate with validate_ruleset_dict.
	var parsed = JSON.parse_string(got_json)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_fail("welcome_ruleset_payload (ruleset_json not parseable as object)")
		return

	var res := DriftValidate.validate_ruleset_dict(parsed)
	if not bool(res.get("ok", false)):
		_fail("welcome_ruleset_payload (ruleset_json failed validation)")
		return

	# Smoke: tangent_damping must be finite if included.
	var td: float = float(w.get("tangent_damping", -1.0))
	if td >= 0.0 and (is_nan(td) or is_inf(td)):
		_fail("welcome_ruleset_payload (tangent_damping not finite)")
		return

	_pass("welcome_ruleset_payload")


func _test_prizes_spawn_walkable() -> void:
	_ran += 1
	var world := DriftWorld.new()
	# Simple empty map with boundary walls.
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(32, 32)
	world.set_map_dimensions(32, 32)

	# Deterministic prize config in ticks.
	var cfg := {
		"prize_delay_ticks": 1,
		"prize_hide_count": 2,
		"prize_min_exist_ticks": 10,
		"prize_max_exist_ticks": 10,
		"prize_negative_factor": 0,
		"death_prize_time_ticks": 10,
		"multi_prize_count": 2,
		"engine_shutdown_time_ticks": 5,
		"minimum_virtual": 0,
		"upgrade_virtual": 0,
	}
	var weights := {
		"Gun": 10,
		"Bomb": 5,
		"MultiFire": 5,
		"BouncingBullets": 5,
		"MultiPrize": 2,
	}
	world.apply_prize_config(cfg, weights)
	world.set_prize_rng_seed(12345)

	# Step one tick with prize processing; should spawn.
	var snap: DriftTypes.DriftWorldSnapshot = world.step_tick({}, true, 1)
	if snap == null:
		_fail("prizes_spawn_walkable (snapshot null)")
		return
	if snap.prizes.size() != 2:
		_fail("prizes_spawn_walkable (expected 2 prizes, got %d)" % snap.prizes.size())
		return
	for p in snap.prizes:
		if p == null:
			_fail("prizes_spawn_walkable (null prize in snapshot)")
			return
		if world.is_position_blocked(p.pos, 6.0):
			_fail("prizes_spawn_walkable (prize spawned in blocked position)")
			return
	_pass("prizes_spawn_walkable")


func _pass(name: String) -> void:
	print("[SMOKE] PASS ", name)


func _fail(msg: String) -> void:
	_failures += 1
	print("[SMOKE] FAIL ", msg)
