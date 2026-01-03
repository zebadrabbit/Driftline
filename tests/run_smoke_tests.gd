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
	_test_energy_deterministic_recharge_and_costs()
	_test_determinism_checksum_fixed_input()
	_test_prizes_spawn_walkable()
	print("[SMOKE] Done: ", _ran, " checks, ", _failures, " failures")
	quit(0 if _failures == 0 else 1)


func _sha256_hex_bytes(bytes: PackedByteArray) -> String:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	var digest: PackedByteArray = ctx.finish()
	return digest.hex_encode()


func _q(f: float, scale: int) -> int:
	return int(round(f * float(scale)))


func _determinism_state_bytes(world) -> PackedByteArray:
	# Quantize floats before hashing to reduce cross-platform noise.
	const Q_POS: int = 1000
	const Q_VEL: int = 1000
	const Q_ANG: int = 100000

	var buf = StreamPeerBuffer.new()
	buf.big_endian = true

	buf.put_32(int(world.tick))

	# Ships (sorted by id)
	var ship_ids: Array = world.ships.keys()
	ship_ids.sort()
	buf.put_32(int(ship_ids.size()))
	for sid in ship_ids:
		var ship_id: int = int(sid)
		var s: DriftTypes.DriftShipState = world.ships.get(ship_id)
		if s == null:
			continue
		buf.put_32(ship_id)
		buf.put_64(_q(float(s.position.x), Q_POS))
		buf.put_64(_q(float(s.position.y), Q_POS))
		buf.put_64(_q(float(s.velocity.x), Q_VEL))
		buf.put_64(_q(float(s.velocity.y), Q_VEL))
		buf.put_64(_q(float(s.rotation), Q_ANG))
		buf.put_32(int(s.energy_current))
		buf.put_32(int(s.energy_max))
		buf.put_32(int(s.energy_recharge_wait_ticks))
		buf.put_32(int(s.energy_recharge_fp_accum))
		buf.put_32(int(s.energy_drain_fp_accum))

	# Bullets (sorted by id)
	var bullet_ids: Array = world.bullets.keys()
	bullet_ids.sort()
	buf.put_32(int(bullet_ids.size()))
	for bid in bullet_ids:
		var bullet_id: int = int(bid)
		var b: DriftTypes.DriftBulletState = world.bullets.get(bullet_id)
		if b == null:
			continue
		buf.put_32(bullet_id)
		buf.put_32(int(b.owner_ship_id))
		buf.put_64(_q(float(b.position.x), Q_POS))
		buf.put_64(_q(float(b.position.y), Q_POS))
		buf.put_64(_q(float(b.velocity.x), Q_VEL))
		buf.put_64(_q(float(b.velocity.y), Q_VEL))
		buf.put_32(int(b.spawn_tick))
		buf.put_32(int(b.die_tick))
		buf.put_32(int(b.bounces_remaining))

	# Ball
	buf.put_64(_q(float(world.ball.position.x), Q_POS))
	buf.put_64(_q(float(world.ball.position.y), Q_POS))
	buf.put_64(_q(float(world.ball.velocity.x), Q_VEL))
	buf.put_64(_q(float(world.ball.velocity.y), Q_VEL))

	return buf.data_array


func _test_determinism_checksum_fixed_input() -> void:
	_ran += 1
	# "Final boss" determinism test: fixed input script -> fixed state hash.
	# This is meant to catch accidental nondeterminism from refactors.

	var ruleset := {
		"format": "driftline.ruleset",
		"schema_version": 2,
		"physics": {
			"wall_restitution": 0.85,
			"tangent_damping": 0.5,
			"ship_turn_rate": 3.5,
			"ship_thrust_accel": 520.0,
			"ship_reverse_accel": 400.0,
			"ship_max_speed": 720.0,
			"ship_base_drag": 0.35,
			"ship_overspeed_drag": 2.0,
			"ship_bounce_min_normal_speed": 160.0,
		},
		"weapons": {
			"ball_friction": 0.98,
			"ball_max_speed": 600.0,
			"ball_kick_speed": 700.0,
			"ball_knock_impulse": 250.0,
			"ball_stick_offset": 18.0,
			"ball_steal_padding": 4.0,
			"bullet": {
				"speed": 950.0,
				"lifetime_s": 0.8,
				"muzzle_offset": 28.0,
				"bounces": 1,
				"bounce_restitution": 1.0,
			},
		},
		"energy": {
			"max": 1200,
			"recharge_rate_per_sec": 150,
			"recharge_delay_ms": 300,
			"afterburner_drain_per_s": 30,
			"bullet_energy_cost": 30,
			"multifire_energy_cost": 90,
			"bomb_energy_cost": 150,
		},
	}

	var valid := DriftValidate.validate_ruleset_dict(ruleset)
	if not bool(valid.get("ok", false)):
		_fail("determinism_checksum (ruleset validation failed)")
		return

	var world = DriftWorld.new()
	world.apply_ruleset(ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(128, 128)
	world.set_map_dimensions(128, 128)
	world.add_ship(1, Vector2(1024, 1024))

	# Fixed input script (120 ticks @ 60 Hz = 2 seconds)
	var idle := DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false)
	for t in range(120):
		var thrust := 1.0 if t < 40 else 0.0
		var turn := 0.35 if (t >= 10 and t < 30) else 0.0
		var fire := (t == 5 or t == 25 or t == 60)
		var modifier := (t >= 15 and t < 20)
		var cmd := DriftTypes.DriftInputCmd.new(thrust, turn, fire, false, modifier)
		world.step_tick({ 1: cmd })

	var state_bytes: PackedByteArray = _determinism_state_bytes(world)
	var got := _sha256_hex_bytes(state_bytes)

	# If this changes unexpectedly, determinism likely broke.
	# Update only when you intentionally change sim semantics.
	const EXPECTED := "935345939f2555efdc0aa7cbe4fd3b0adb101a7da23dddb85cec787cd1d92340"
	if got != EXPECTED:
		_fail("determinism_checksum (got %s expected %s)" % [got, EXPECTED])
		return

	_pass("determinism_checksum_fixed_input")


func _test_energy_deterministic_recharge_and_costs() -> void:
	_ran += 1
	# Goal: assert energy behavior without relying on floats:
	# - weapon firing drains energy and sets recharge delay
	# - energy does not recharge during delay
	# - energy starts recharging deterministically after delay
	# - firing with insufficient energy does not spawn bullets

	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("energy_deterministic (failed to load base ruleset)")
		return

	var canonical_ruleset: Dictionary = rules_res.get("ruleset", {})
	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)

	var ship_id := 1
	world.add_ship(ship_id, Vector2(64, 64))
	var s: DriftTypes.DriftShipState = world.ships.get(ship_id)
	if s == null:
		_fail("energy_deterministic (ship missing)")
		return
	if int(s.energy_max) <= 0 or int(s.energy_current) != int(s.energy_max):
		_fail("energy_deterministic (expected ship start full energy)")
		return

	# Fire once; must drain energy and set recharge wait.
	var start_energy := int(s.energy_current)
	var start_bullets := int(world.bullets.size())
	var fire_cmd := DriftTypes.DriftInputCmd.new(0.0, 0.0, true, false, false)
	world.step_tick({ ship_id: fire_cmd })
	var after_fire_energy := int(s.energy_current)
	if after_fire_energy >= start_energy:
		_fail("energy_deterministic (energy did not decrease on fire)")
		return
	if int(s.energy_recharge_wait_ticks) <= 0:
		_fail("energy_deterministic (expected recharge wait ticks after drain)")
		return
	if int(world.bullets.size()) <= start_bullets:
		_fail("energy_deterministic (expected bullet spawn on fire)")
		return

	# During the wait period, energy must not increase.
	var wait_ticks := int(s.energy_recharge_wait_ticks)
	var idle_cmd := DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false)
	for _i in range(wait_ticks):
		var before := int(s.energy_current)
		world.step_tick({ ship_id: idle_cmd })
		var after := int(s.energy_current)
		if after != before:
			_fail("energy_deterministic (energy changed during recharge delay)")
			return
	# Next tick should begin recharge (unless already at max).
	var before_recharge := int(s.energy_current)
	world.step_tick({ ship_id: idle_cmd })
	var after_recharge := int(s.energy_current)
	if after_recharge <= before_recharge and before_recharge < int(s.energy_max):
		_fail("energy_deterministic (energy did not recharge after delay elapsed)")
		return

	# Gating: with zero energy, firing should NOT spawn bullets.
	s.energy_current = 0
	s.energy_recharge_wait_ticks = 0
	var bullets_before_gate := int(world.bullets.size())
	world.step_tick({ ship_id: fire_cmd })
	var bullets_after_gate := int(world.bullets.size())
	if bullets_after_gate != bullets_before_gate:
		_fail("energy_deterministic (bullet spawned with insufficient energy)")
		return

	_pass("energy_deterministic_recharge_and_costs")


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
	var world = DriftWorld.new()
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
