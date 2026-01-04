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
const DriftTeamColors = preload("res://client/team_colors.gd")

var _failures: int = 0
var _ran: int = 0


func _initialize() -> void:
	_test_controls_actions_present()
	_test_controls_default_bindings_wasd()
	_test_controls_weapon_defaults_present()
	_test_no_hardcoded_keys_in_gameplay()
	_test_welcome_includes_ruleset_payload()
	_test_energy_deterministic_recharge_and_costs()
	_test_abilities_continuous_drain_and_auto_disable()
	_test_safe_zone_mechanics()
	_test_energy_fire_costs_and_damage_safe_zone()
	_test_safe_zone_brake_persistent()
	_test_safe_zone_time_limit_forces_non_safe_respawn()
	_test_spawn_protection_blocks_damage()
	_test_team_auto_balance_assigns_even_teams()
	_test_set_freq_rejects_when_force_even_violated()
	_test_team_color_mapping_flips_with_freq()
	_test_team_color_objective_carrier_override()
	_test_team_colors_radar_mapping_helpers()
	_test_ffa_allows_damage_even_same_freq_when_friendly_fire_enabled()
	_test_friendly_fire_blocks_damage()
	_test_enemy_damage_applies()
	_test_death_spend_to_zero_does_not_kill()
	_test_death_damage_to_zero_kills_and_respawns()
	_test_death_safe_zone_damage_impossible()
	_test_determinism_checksum_fixed_input()
	_test_prizes_spawn_walkable()
	print("[SMOKE] Done: ", _ran, " checks, ", _failures, " failures")
	quit(0 if _failures == 0 else 1)


func _test_team_color_mapping_flips_with_freq() -> void:
	_ran += 1
	# Client friendliness rendering derives from freq: same freq => friendly, else enemy.
	var my_freq := 1
	var friendly_idx := DriftTeamColors.get_nameplate_color_index(my_freq, 1, 0)
	var enemy_idx := DriftTeamColors.get_nameplate_color_index(my_freq, 2, 0)
	if friendly_idx == enemy_idx:
		_fail("team_colors (expected different friendly/enemy indices)")
		return
	if int(friendly_idx) != 1:
		_fail("team_colors (expected friendly index=1 green got %d)" % [int(friendly_idx)])
		return
	if int(enemy_idx) != 3:
		_fail("team_colors (expected enemy index=3 red got %d)" % [int(enemy_idx)])
		return
	# Flip my_freq: the same other becomes enemy.
	var flipped := DriftTeamColors.get_nameplate_color_index(2, 1, 0)
	if int(flipped) != 3:
		_fail("team_colors (expected flip to enemy index=3 got %d)" % [int(flipped)])
		return
	_pass("team_color_mapping_flips_with_freq")


func _test_team_color_objective_carrier_override() -> void:
	_ran += 1
	var flags := int(DriftTeamColors.FLAG_OBJECTIVE_CARRIER)
	var expected := int(DriftTeamColors.NAMEPLATE_PRIORITY_COLOR_INDEX)

	# Override should beat friendly team color.
	var friendly_override := int(DriftTeamColors.get_nameplate_color_index(1, 1, flags))
	if friendly_override != expected:
		_fail("team_colors (objective carrier expected %d got %d)" % [expected, friendly_override])
		return

	# Override should beat enemy team color.
	var enemy_override := int(DriftTeamColors.get_nameplate_color_index(1, 2, flags))
	if enemy_override != expected:
		_fail("team_colors (objective carrier expected %d got %d)" % [expected, enemy_override])
		return

	_pass("team_color_objective_carrier_override")


func _test_team_colors_radar_mapping_helpers() -> void:
	_ran += 1
	# Radar/minimap requirements:
	# - Dot color comes from team_colors.gd
	# - Self is a distinct shape, not just color
	# - Objective carrier uses override color

	var my_freq := 1
	var friendly := DriftTeamColors.get_radar_dot_color(my_freq, 1, 0)
	var enemy := DriftTeamColors.get_radar_dot_color(my_freq, 2, 0)
	if friendly == enemy:
		_fail("radar_colors (expected friendly/enemy dot colors to differ)")
		return

	var flags := int(DriftTeamColors.FLAG_OBJECTIVE_CARRIER)
	var expected_priority := DriftTeamColors.RADAR_PRIORITY_MARKER_COLOR
	var prio_friendly := DriftTeamColors.get_radar_dot_color(my_freq, 1, flags)
	var prio_enemy := DriftTeamColors.get_radar_dot_color(my_freq, 2, flags)
	if prio_friendly != expected_priority or prio_enemy != expected_priority:
		_fail("radar_colors (expected objective carrier override color)")
		return

	var self_shape := int(DriftTeamColors.get_radar_shape(true, 0))
	var other_shape := int(DriftTeamColors.get_radar_shape(false, 0))
	if self_shape == other_shape:
		_fail("radar_shape (expected self shape distinct from others)")
		return
	if self_shape == int(DriftTeamColors.RADAR_SHAPE_DOT):
		_fail("radar_shape (expected self not DOT)")
		return
	if not bool(DriftTeamColors.radar_self_should_blink()):
		_fail("radar_shape (expected self blink enabled)")
		return

	_pass("team_colors_radar_mapping_helpers")


func _test_set_freq_rejects_when_force_even_violated() -> void:
	_ran += 1
	# When team.force_even=true, manual team changes that would create a team-count
	# variance > 1 must be rejected.

	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("set_freq_force_even (failed to load base ruleset)")
		return
	var rs: Dictionary = rules_res.get("ruleset", {})
	if typeof(rs) != TYPE_DICTIONARY:
		_fail("set_freq_force_even (ruleset missing)")
		return
	rs["team"] = {"max_freq": 2, "force_even": true}
	var valid := DriftValidate.validate_ruleset_dict(rs)
	if not bool(valid.get("ok", false)):
		_fail("set_freq_force_even (ruleset validation failed)")
		return
	var canonical_ruleset: Dictionary = valid.get("ruleset", rs)

	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)

	# Create an uneven-but-allowed distribution: team 0 has 2 ships, team 1 has 1 ship.
	world.add_ship(1, Vector2(64, 64))
	world.add_ship(2, Vector2(96, 64))
	world.add_ship(3, Vector2(128, 64))
	var s1: DriftTypes.DriftShipState = world.ships.get(1)
	var s2: DriftTypes.DriftShipState = world.ships.get(2)
	var s3: DriftTypes.DriftShipState = world.ships.get(3)
	if s1 == null or s2 == null or s3 == null:
		_fail("set_freq_force_even (ship missing)")
		return
	s1.freq = 0
	s2.freq = 1
	s3.freq = 0

	# Now moving ship 2 from team 1 -> team 0 would produce 3 vs 0 (variance 3), reject.
	var res: Dictionary = world.can_set_ship_freq(2, 0)
	if bool(res.get("ok", false)):
		_fail("set_freq_force_even (expected rejection)")
		return
	var reason: int = int(res.get("reason", -1))
	if reason != DriftNet.SET_FREQ_REASON_UNEVEN_TEAMS:
		_fail("set_freq_force_even (expected UNEVEN_TEAMS got %d)" % [reason])
		return
	_pass("set_freq_rejects_when_force_even_violated")


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
		buf.put_32(int(b.owner_id))
		buf.put_64(_q(float(b.position.x), Q_POS))
		buf.put_64(_q(float(b.position.y), Q_POS))
		buf.put_64(_q(float(b.velocity.x), Q_VEL))
		buf.put_64(_q(float(b.velocity.y), Q_VEL))
		buf.put_32(int(b.spawn_tick))
		buf.put_32(int(b.die_tick))
		buf.put_32(int(b.bounces_left))

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
		"abilities": {
			"afterburner": {"drain_per_sec": 30, "speed_mult_pct": 100, "thrust_mult_pct": 160},
			"stealth": {"drain_per_sec": 20},
			"cloak": {"drain_per_sec": 25},
			"xradar": {"drain_per_sec": 15},
			"antiwarp": {"drain_per_sec": 35, "radius_px": 200},
		},
		"energy": {
			"max": 1200,
			"recharge_rate_per_sec": 150,
			"recharge_delay_ms": 300,
			"bullet_energy_cost": 30,
			"multifire_energy_cost": 90,
			"bomb_energy_cost": 150,
		},
	}

	var valid := DriftValidate.validate_ruleset_dict(ruleset)
	if not bool(valid.get("ok", false)):
		_fail("determinism_checksum (ruleset validation failed)")
		return

	var canonical_ruleset: Dictionary = valid.get("ruleset", ruleset)
	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
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


func _test_safe_zone_mechanics() -> void:
	_ran += 1
	# Safe zones must be enforced in shared sim:
	# - no bullets/energy drain when firing
	# - pressing fire instantly stops the ship
	# - abilities cannot be activated and must not drain

	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("safe_zone (failed to load base ruleset)")
		return
	var canonical_ruleset: Dictionary = rules_res.get("ruleset", {})
	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	# Mark tile (2,2) as safe zone.
	world.set_safe_zone_tiles([[2, 2, 0, 0]])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)

	var ship_id := 1
	var start_pos := Vector2(2 * 16 + 8, 2 * 16 + 8)
	world.add_ship(ship_id, start_pos)
	var s: DriftTypes.DriftShipState = world.ships.get(ship_id)
	if s == null:
		_fail("safe_zone (ship missing)")
		return
	# Give the ship velocity so the fire-stop rule is observable.
	s.velocity = Vector2(120.0, -30.0)
	var start_energy := int(s.energy_current)
	var start_bullets := int(world.bullets.size())

	# Press fire: should stop ship, spawn no bullets, drain no energy.
	var fire_cmd := DriftTypes.DriftInputCmd.new(0.0, 0.0, true, false, false)
	world.step_tick({ ship_id: fire_cmd })
	if not bool(s.in_safe_zone):
		_fail("safe_zone (expected in_safe_zone true)")
		return
	if int(world.bullets.size()) != start_bullets:
		_fail("safe_zone (expected no bullets)")
		return
	if int(s.energy_current) != start_energy:
		_fail("safe_zone (expected no energy drain)")
		return
	if s.velocity != Vector2.ZERO:
		_fail("safe_zone (expected velocity forced to zero)")
		return
	if s.position != start_pos:
		_fail("safe_zone (expected no movement on fire-stop)")
		return

	# Attempt abilities: should not activate and should not drain.
	var abil_cmd := DriftTypes.DriftInputCmd.new(1.0, 0.0, false, false, true, true, true, true, true)
	world.step_tick({ ship_id: abil_cmd })
	if bool(s.afterburner_on) or bool(s.stealth_on) or bool(s.cloak_on) or bool(s.xradar_on) or bool(s.antiwarp_on):
		_fail("safe_zone (expected abilities to remain off)")
		return
	if int(s.energy_current) != start_energy:
		_fail("safe_zone (expected abilities to cost no energy)")
		return

	_pass("safe_zone_mechanics")


func _test_death_spend_to_zero_does_not_kill() -> void:
	_ran += 1
	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("death_spend_to_zero (failed to load base ruleset)")
		return
	var canonical_ruleset: Dictionary = rules_res.get("ruleset", {})
	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.set_safe_zone_tiles([])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)
	world.add_ship(1, Vector2(64, 64))
	var s: DriftTypes.DriftShipState = world.ships.get(1)
	if s == null:
		_fail("death_spend_to_zero (ship missing)")
		return

	# Spend down to 0 via a cost reason; must NOT trigger death.
	var cur := int(s.energy_current)
	if cur <= 0:
		_fail("death_spend_to_zero (expected positive starting energy)")
		return
	var ok := world.adjust_energy(1, -cur, int(DriftWorld.EnergyReason.COST_FIRE_PRIMARY), 1)
	if not ok:
		_fail("death_spend_to_zero (expected spend to succeed)")
		return
	if int(s.energy_current) != 0:
		_fail("death_spend_to_zero (expected energy_current == 0)")
		return
	if int(s.dead_until_tick) != 0:
		_fail("death_spend_to_zero (expected not dead)")
		return

	_pass("death_spend_to_zero_does_not_kill")


func _test_death_damage_to_zero_kills_and_respawns() -> void:
	_ran += 1
	# Use an explicit schema v2 ruleset so combat.respawn_delay_ms is supported.
	var ruleset := {
		"format": "driftline.ruleset",
		"schema_version": 2,
		"physics": {"wall_restitution": 0.85},
		"weapons": {"ball_friction": 0.98},
		"abilities": {
			"afterburner": {"drain_per_sec": 0, "speed_mult_pct": 100, "thrust_mult_pct": 160},
			"stealth": {"drain_per_sec": 0},
			"cloak": {"drain_per_sec": 0},
			"xradar": {"drain_per_sec": 0},
			"antiwarp": {"drain_per_sec": 0, "radius_px": 0}
		},
		"energy": {
			"max": 200,
			"recharge_rate_per_sec": 0,
			"recharge_delay_ms": 300,
			"bullet_energy_cost": 0,
			"multifire_energy_cost": 0,
			"bomb_energy_cost": 0
		},
		"combat": {"spawn_protect_ms": 300, "respawn_delay_ms": 100},
	}
	var valid := DriftValidate.validate_ruleset(ruleset)
	if not bool(valid.get("ok", false)):
		_fail("death_damage_to_zero (ruleset validation failed: %s)" % [str(valid.get("errors", []))])
		return
	var canonical_ruleset: Dictionary = valid.get("ruleset", ruleset)

	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	# Provide a safe zone so respawn selects it.
	world.set_safe_zone_tiles([[2, 2, 0, 0]])
	world.set_spawn_rng_seed(1234)
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)
	world.add_ship(1, Vector2(64, 64))
	var s: DriftTypes.DriftShipState = world.ships.get(1)
	if s == null:
		_fail("death_damage_to_zero (ship missing)")
		return

	# Apply damage that reduces energy to 0; must trigger death.
	var did := world.apply_damage(-1, 1, 9999, "bullet")
	if not did:
		_fail("death_damage_to_zero (expected damage to apply)")
		return
	if int(s.energy_current) != 0:
		_fail("death_damage_to_zero (expected energy_current == 0 after damage)")
		return
	if int(s.dead_until_tick) <= int(world.tick):
		_fail("death_damage_to_zero (expected dead_until_tick in the future)")
		return

	# Step until respawn happens.
	var safety := 300
	while int(s.dead_until_tick) > 0 and safety > 0:
		world.step_tick({})
		safety -= 1
		if int(s.dead_until_tick) == 0:
			break
	if safety <= 0:
		_fail("death_damage_to_zero (respawn did not occur)")
		return
	if int(s.energy_current) <= 0:
		_fail("death_damage_to_zero (expected energy reset on respawn)")
		return
	if int(s.damage_protect_until_tick) <= int(world.tick):
		_fail("death_damage_to_zero (expected spawn protection after respawn)")
		return
	if not bool(s.in_safe_zone):
		_fail("death_damage_to_zero (expected respawn into safe zone)")
		return

	_pass("death_damage_to_zero_kills_and_respawns")


func _test_death_safe_zone_damage_impossible() -> void:
	_ran += 1
	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("death_safe_zone_damage (failed to load base ruleset)")
		return
	var canonical_ruleset: Dictionary = rules_res.get("ruleset", {})
	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	# Mark tile (2,2) as safe zone.
	world.set_safe_zone_tiles([[2, 2, 0, 0]])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)
	var ship_id := 1
	var start_pos := Vector2(2 * 16 + 8, 2 * 16 + 8)
	world.add_ship(ship_id, start_pos)
	var s: DriftTypes.DriftShipState = world.ships.get(ship_id)
	if s == null:
		_fail("death_safe_zone_damage (ship missing)")
		return
	# Step once so in_safe_zone is derived.
	world.step_tick({ ship_id: DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false) })
	if not bool(s.in_safe_zone):
		_fail("death_safe_zone_damage (expected in_safe_zone true)")
		return
	var did := world.apply_damage(-1, ship_id, 9999, "bullet")
	if did:
		_fail("death_safe_zone_damage (expected damage blocked)")
		return
	if int(s.dead_until_tick) != 0:
		_fail("death_safe_zone_damage (expected not dead)")
		return
	_pass("death_safe_zone_damage_impossible")


func _test_energy_fire_costs_and_damage_safe_zone() -> void:
	_ran += 1
	# Explicit energy accounting smoke test:
	# - rejected FIRE_PRIMARY in safe zone does not reduce energy
	# - accepted FIRE_PRIMARY outside safe zone does reduce energy
	# - apply_damage against a safe-zone ship is rejected and does not change energy

	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("energy_safe_zone (failed to load base ruleset)")
		return
	var canonical_ruleset: Dictionary = rules_res.get("ruleset", {})
	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.set_safe_zone_tiles([[2, 2, 0, 0]])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)

	var safe_id := 1
	var outside_id := 2
	var safe_pos := Vector2(2 * 16 + 8, 2 * 16 + 8)
	var outside_pos := Vector2(5 * 16 + 8, 5 * 16 + 8)
	world.add_ship(safe_id, safe_pos)
	world.add_ship(outside_id, outside_pos)
	var s_safe: DriftTypes.DriftShipState = world.ships.get(safe_id)
	var s_out: DriftTypes.DriftShipState = world.ships.get(outside_id)
	if s_safe == null or s_out == null:
		_fail("energy_safe_zone (ship missing)")
		return

	var start_energy_safe := int(s_safe.energy_current)
	var start_bullets := int(world.bullets.size())
	world.step_tick({
		safe_id: DriftTypes.DriftInputCmd.new(0.0, 0.0, true, false, false),
		outside_id: DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false),
	})
	if not bool(s_safe.in_safe_zone):
		_fail("energy_safe_zone (expected safe ship in safe zone)")
		return
	if int(s_safe.energy_current) != start_energy_safe:
		_fail("energy_safe_zone (expected no energy drain on rejected fire)")
		return
	if int(world.bullets.size()) != start_bullets:
		_fail("energy_safe_zone (expected no bullets from safe-zone fire)")
		return

	var start_energy_out := int(s_out.energy_current)
	world.step_tick({
		outside_id: DriftTypes.DriftInputCmd.new(0.0, 0.0, true, false, false),
	})
	if bool(s_out.in_safe_zone):
		_fail("energy_safe_zone (expected outside ship not in safe zone)")
		return
	if int(world.bullets.size()) <= start_bullets:
		_fail("energy_safe_zone (expected bullet spawned outside safe zone)")
		return
	var cost_single := int(world.bullet_energy_cost)
	var cost_multi := int(world.bullet_multifire_energy_cost)
	var delta := int(start_energy_out - int(s_out.energy_current))
	if delta <= 0:
		_fail("energy_safe_zone (expected outside fire to reduce energy)")
		return
	if delta != cost_single and delta != cost_multi:
		_fail("energy_safe_zone (unexpected fire cost delta %d)" % [delta])
		return

	var before_damage_safe := int(s_safe.energy_current)
	var dmg_ok := world.apply_damage(outside_id, safe_id, 10, "bullet")
	if dmg_ok:
		_fail("energy_safe_zone (expected damage blocked in safe zone)")
		return
	if int(s_safe.energy_current) != before_damage_safe:
		_fail("energy_safe_zone (expected no energy change on blocked damage)")
		return

	_pass("energy_fire_costs_and_damage_safe_zone")


func _test_safe_zone_brake_persistent() -> void:
	_ran += 1
	# Safe-zone braking must be persistent:
	# - build velocity outside
	# - enter safe zone and attempt FIRE_PRIMARY -> velocity becomes 0
	# - subsequent idle ticks stay at 0 (no inertia resuming)
	# - applying thrust again resumes movement

	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("safe_zone_brake (failed to load base ruleset)")
		return
	var canonical_ruleset: Dictionary = rules_res.get("ruleset", {})
	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.set_safe_zone_tiles([[2, 2, 0, 0]])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)

	var ship_id := 1
	var outside_pos := Vector2(3 * 16 + 8, 2 * 16 + 8)
	var safe_pos := Vector2(2 * 16 + 8, 2 * 16 + 8)
	world.add_ship(ship_id, outside_pos)
	var s: DriftTypes.DriftShipState = world.ships.get(ship_id)
	if s == null:
		_fail("safe_zone_brake (ship missing)")
		return

	# Build velocity outside the safe zone.
	for _i in range(10):
		world.step_tick({ ship_id: DriftTypes.DriftInputCmd.new(1.0, 0.0, false, false, false) })
	if s.velocity.length() <= 1.0:
		_fail("safe_zone_brake (expected non-zero velocity after thrust)")
		return

	# Enter safe zone while drifting.
	s.position = safe_pos
	world.step_tick({ ship_id: DriftTypes.DriftInputCmd.new(0.0, 0.0, true, false, false) })
	if not bool(s.in_safe_zone):
		_fail("safe_zone_brake (expected ship in safe zone)")
		return
	if s.velocity != Vector2.ZERO:
		_fail("safe_zone_brake (expected velocity zero after fire-brake)")
		return

	# No inertia resuming on following ticks.
	for _j in range(5):
		world.step_tick({ ship_id: DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false) })
		if s.velocity != Vector2.ZERO:
			_fail("safe_zone_brake (expected velocity to remain zero)")
			return

	# Thrust again resumes movement.
	world.step_tick({ ship_id: DriftTypes.DriftInputCmd.new(1.0, 0.0, false, false, false) })
	if s.velocity.length() <= 1.0:
		_fail("safe_zone_brake (expected velocity to resume after thrust)")
		return

	_pass("safe_zone_brake_persistent")


func _test_safe_zone_time_limit_forces_non_safe_respawn() -> void:
	_ran += 1
	# Safe-zone time limit (zones.safe_zone_max_ms):
	# - accumulates only while alive + in safe zone
	# - on exceed, forces respawn to a non-safe spawn deterministically
	var ruleset := {
		"format": "driftline.ruleset",
		"schema_version": 2,
		"physics": {"wall_restitution": 0.85},
		"weapons": {"ball_friction": 0.98},
		"abilities": {
			"afterburner": {"drain_per_sec": 0, "speed_mult_pct": 100, "thrust_mult_pct": 160},
			"stealth": {"drain_per_sec": 0},
			"cloak": {"drain_per_sec": 0},
			"xradar": {"drain_per_sec": 0},
			"antiwarp": {"drain_per_sec": 0, "radius_px": 0}
		},
		"energy": {
			"max": 200,
			"recharge_rate_per_sec": 0,
			"recharge_delay_ms": 0,
			"bullet_energy_cost": 0,
			"multifire_energy_cost": 0,
			"bomb_energy_cost": 0
		},
		"combat": {"spawn_protect_ms": 0, "respawn_delay_ms": 0},
		"zones": {"safe_zone_max_ms": 100}
	}
	var valid := DriftValidate.validate_ruleset(ruleset)
	if not bool(valid.get("ok", false)):
		_fail("safe_zone_time_limit (ruleset validation failed: %s)" % [str(valid.get("errors", []))])
		return
	var canonical_ruleset: Dictionary = valid.get("ruleset", ruleset)

	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.set_safe_zone_tiles([[2, 2, 0, 0]])
	world.set_spawn_rng_seed(1234)
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)

	var ship_id := 1
	var safe_pos := Vector2(2 * 16 + 8, 2 * 16 + 8)
	world.add_ship(ship_id, safe_pos)
	var s: DriftTypes.DriftShipState = world.ships.get(ship_id)
	if s == null:
		_fail("safe_zone_time_limit (ship missing)")
		return

	# Step until the safe-zone limit is exceeded and a forced respawn occurs.
	var pre_pos := s.position
	var saw_in_safe := false
	var relocated := false
	for _i in range(120):
		world.step_tick({ ship_id: DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false) })
		if bool(s.in_safe_zone):
			saw_in_safe = true
		if s.position != pre_pos:
			relocated = true
			break
	if not saw_in_safe:
		_fail("safe_zone_time_limit (expected ship to be in safe zone during test)")
		return
	if not relocated:
		_fail("safe_zone_time_limit (expected forced relocation)")
		return
	if bool(s.in_safe_zone):
		_fail("safe_zone_time_limit (expected respawn outside safe zone)")
		return
	if int(s.safe_zone_time_used_ticks) != 0:
		_fail("safe_zone_time_limit (expected timer reset on respawn)")
		return
	if int(s.safe_zone_time_max_ticks) <= 0:
		_fail("safe_zone_time_limit (expected replicated max ticks > 0)")
		return

	_pass("safe_zone_time_limit_forces_non_safe_respawn")


func _test_spawn_protection_blocks_damage() -> void:
	_ran += 1
	# apply_damage() must respect spawn protection timers and safe-zone immunity.
	# This is a low-level invariant test; it does not depend on bullets/bombs existing yet.

	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("spawn_protection (failed to load base ruleset)")
		return
	var rs: Dictionary = rules_res.get("ruleset", {})
	# Enable a short spawn protection window.
	rs["combat"] = {"spawn_protect_ms": 250}
	var valid := DriftValidate.validate_ruleset(rs)
	if not bool(valid.get("ok", false)):
		_fail("spawn_protection (ruleset validation failed)")
		return
	var canonical_ruleset: Dictionary = valid.get("ruleset", {})

	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)

	world.add_ship(1, Vector2(32, 32))
	world.add_ship(2, Vector2(64, 64))
	# Use the spawn/reset primitive so the protection timestamp is initialized.
	world.reset_ship_for_spawn(2, Vector2(64, 64))

	var attacker: DriftTypes.DriftShipState = world.ships.get(1)

	var target: DriftTypes.DriftShipState = world.ships.get(2)
	if attacker == null:
		_fail("spawn_protection (attacker ship missing)")
		return
	if target == null:
		_fail("spawn_protection (target ship missing)")
		return

	# Ensure friendly-fire prevention doesn't interfere with this test.
	attacker.freq = 1
	target.freq = 2
	# Give the target energy to "damage".
	target.energy_current = 100
	target.energy = float(target.energy_current)

	# During protection, apply_damage must be rejected.
	var ok0 := world.apply_damage(1, 2, 25, "test")
	if ok0:
		_fail("spawn_protection (apply_damage succeeded during protection)")
		return
	if int(target.energy_current) != 100:
		_fail("spawn_protection (energy changed during protection)")
		return

	# Advance to the first unprotected tick.
	var pt: int = maxi(0, int(world.spawn_protect_ticks))
	for _i in range(pt):
		world.step_tick({})
	var pre_energy: int = int(target.energy_current)
	var ok1 := world.apply_damage(1, 2, 25, "test")
	if not ok1:
		_fail("spawn_protection (apply_damage rejected after protection window)")
		return
	var expected_after: int = maxi(0, pre_energy - 25)
	if int(target.energy_current) != expected_after:
		_fail("spawn_protection (expected energy_current %d, got %d)" % [expected_after, int(target.energy_current)])
		return

	# Safe-zone immunity: cannot damage a ship in a safe zone.
	world.set_safe_zone_tiles([[4, 4, 0, 0]])
	target.position = Vector2(4 * 16 + 8, 4 * 16 + 8)
	# Recompute safe zone flag.
	world.step_tick({})
	if not bool(target.in_safe_zone):
		_fail("spawn_protection (expected target in safe zone)")
		return
	var pre_safe: int = int(target.energy_current)
	var ok2 := world.apply_damage(1, 2, 25, "test")
	if ok2:
		_fail("spawn_protection (apply_damage succeeded in safe zone)")
		return
	if int(target.energy_current) != pre_safe:
		_fail("spawn_protection (energy changed in safe zone)")
		return

	_pass("spawn_protection_blocks_damage")


func _test_friendly_fire_blocks_damage() -> void:
	_ran += 1
	# Minimal friendly-fire prevention: same-freq damage must be rejected.

	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("friendly_fire (failed to load base ruleset)")
		return
	var rs: Dictionary = rules_res.get("ruleset", {})
	# Ensure spawn protection can't interfere with the invariant under test.
	rs["combat"] = {"spawn_protect_ms": 0}
	var valid := DriftValidate.validate_ruleset(rs)
	if not bool(valid.get("ok", false)):
		_fail("friendly_fire (ruleset validation failed)")
		return
	var canonical_ruleset: Dictionary = valid.get("ruleset", {})

	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)

	world.add_ship(1, Vector2(32, 32))
	world.add_ship(2, Vector2(64, 64))
	var attacker: DriftTypes.DriftShipState = world.ships.get(1)
	var target: DriftTypes.DriftShipState = world.ships.get(2)
	if attacker == null or target == null:
		_fail("friendly_fire (ship missing)")
		return

	attacker.freq = 1
	target.freq = 1

	target.energy_current = 100
	target.energy = float(target.energy_current)

	var ok := world.apply_damage(1, 2, 25, "test")
	if ok:
		_fail("friendly_fire (apply_damage succeeded for same-freq)")
		return
	if int(target.energy_current) != 100:
		_fail("friendly_fire (energy changed on same-freq damage)")
		return

	_pass("friendly_fire_blocks_damage")


func _test_enemy_damage_applies() -> void:
	_ran += 1
	# Damage must still apply against different freq.

	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("enemy_damage (failed to load base ruleset)")
		return
	var rs: Dictionary = rules_res.get("ruleset", {})
	# Ensure spawn protection can't interfere with the invariant under test.
	rs["combat"] = {"spawn_protect_ms": 0}
	var valid := DriftValidate.validate_ruleset(rs)
	if not bool(valid.get("ok", false)):
		_fail("enemy_damage (ruleset validation failed)")
		return
	var canonical_ruleset: Dictionary = valid.get("ruleset", {})

	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)

	world.add_ship(1, Vector2(32, 32))
	world.add_ship(2, Vector2(64, 64))
	var attacker: DriftTypes.DriftShipState = world.ships.get(1)
	var target: DriftTypes.DriftShipState = world.ships.get(2)
	if attacker == null or target == null:
		_fail("enemy_damage (ship missing)")
		return

	attacker.freq = 1
	target.freq = 2

	target.energy_current = 100
	target.energy = float(target.energy_current)

	var ok := world.apply_damage(1, 2, 25, "test")
	if not ok:
		_fail("enemy_damage (apply_damage rejected for different-freq)")
		return
	var expected_after: int = 75
	if int(target.energy_current) != expected_after:
		_fail("enemy_damage (expected energy_current %d, got %d)" % [expected_after, int(target.energy_current)])
		return

	_pass("enemy_damage_applies")


func _test_team_auto_balance_assigns_even_teams() -> void:
	_ran += 1
	# When team.max_freq=2, respawning ships should be auto-balanced deterministically.

	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("team_auto_balance (failed to load base ruleset)")
		return
	var rs: Dictionary = rules_res.get("ruleset", {})
	rs["team"] = {"max_freq": 2, "force_even": true}
	# Ensure spawn protection can't interfere with later damage tests.
	rs["combat"] = {"spawn_protect_ms": 0, "friendly_fire": false}
	var valid := DriftValidate.validate_ruleset(rs)
	if not bool(valid.get("ok", false)):
		_fail("team_auto_balance (ruleset validation failed)")
		return
	var canonical_ruleset: Dictionary = valid.get("ruleset", {})

	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.set_safe_zone_tiles([])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)

	world.respawn_ship(1)
	world.respawn_ship(2)
	world.respawn_ship(3)
	world.respawn_ship(4)

	var s1: DriftTypes.DriftShipState = world.ships.get(1)
	var s2: DriftTypes.DriftShipState = world.ships.get(2)
	var s3: DriftTypes.DriftShipState = world.ships.get(3)
	var s4: DriftTypes.DriftShipState = world.ships.get(4)
	if s1 == null or s2 == null or s3 == null or s4 == null:
		_fail("team_auto_balance (ship missing)")
		return
	var f1: int = int(s1.freq)
	var f2: int = int(s2.freq)
	var f3: int = int(s3.freq)
	var f4: int = int(s4.freq)
	if f1 != 0 or f2 != 1 or f3 != 0 or f4 != 1:
		_fail("team_auto_balance (expected freqs 0,1,0,1 got %d,%d,%d,%d)" % [f1, f2, f3, f4])
		return

	_pass("team_auto_balance_assigns_even_teams")


func _test_ffa_allows_damage_even_same_freq_when_friendly_fire_enabled() -> void:
	_ran += 1
	# In FFA mode (team.max_freq=0), damage must be allowed even if both ships are freq=0,
	# as long as friendly_fire is enabled.

	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("ffa_friendly_fire (failed to load base ruleset)")
		return
	var rs: Dictionary = rules_res.get("ruleset", {})
	rs["team"] = {"max_freq": 0, "force_even": true}
	rs["combat"] = {"spawn_protect_ms": 0, "friendly_fire": true}
	var valid := DriftValidate.validate_ruleset(rs)
	if not bool(valid.get("ok", false)):
		_fail("ffa_friendly_fire (ruleset validation failed)")
		return
	var canonical_ruleset: Dictionary = valid.get("ruleset", {})

	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.set_safe_zone_tiles([])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)

	world.respawn_ship(1)
	world.respawn_ship(2)
	var a: DriftTypes.DriftShipState = world.ships.get(1)
	var t: DriftTypes.DriftShipState = world.ships.get(2)
	if a == null or t == null:
		_fail("ffa_friendly_fire (ship missing)")
		return
	if int(a.freq) != 0 or int(t.freq) != 0:
		_fail("ffa_friendly_fire (expected both ships freq=0)")
		return

	t.energy_current = 100
	t.energy = float(t.energy_current)
	var ok := world.apply_damage(1, 2, 25, "test")
	if not ok:
		_fail("ffa_friendly_fire (apply_damage rejected)")
		return
	if int(t.energy_current) != 75:
		_fail("ffa_friendly_fire (expected energy_current 75, got %d)" % [int(t.energy_current)])
		return

	_pass("ffa_allows_damage_even_same_freq_when_friendly_fire_enabled")


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


func _test_abilities_continuous_drain_and_auto_disable() -> void:
	_ran += 1
	# Goal: assert sustained abilities behave deterministically:
	# - toggles are edge-triggered in the shared sim
	# - sustained drain blocks recharge
	# - abilities auto-disable when energy hits 0
	# - recharge resumes after the configured delay

	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("abilities_continuous (failed to load base ruleset)")
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
		_fail("abilities_continuous (ship missing)")
		return

	# Toggle stealth on (button-down for one tick; edge detection lives in the sim).
	var toggle_stealth := DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false, true, false, false, false)
	world.step_tick({ ship_id: toggle_stealth })
	if not bool(s.stealth_on):
		_fail("abilities_continuous (expected stealth_on after toggle)")
		return

	# While stealth is on, energy must monotonically decrease (never recharge).
	var idle := DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false)
	var before := int(s.energy_current)
	for _i in range(120):
		var e0 := int(s.energy_current)
		world.step_tick({ ship_id: idle })
		var e1 := int(s.energy_current)
		if e1 > e0:
			_fail("abilities_continuous (energy increased while sustained ability active)")
			return
	var after := int(s.energy_current)
	if after >= before:
		_fail("abilities_continuous (expected energy to drain while stealth_on)")
		return

	# Force low energy and ensure ability auto-disables when drained.
	s.energy_current = 1
	s.energy_recharge_wait_ticks = 0
	s.energy_drain_fp_accum = 0
	s.stealth_on = true
	for _i in range(240):
		world.step_tick({ ship_id: idle })
		if int(s.energy_current) <= 0:
			break
	if int(s.energy_current) != 0:
		_fail("abilities_continuous (expected energy to reach 0)")
		return
	if bool(s.stealth_on):
		_fail("abilities_continuous (expected stealth_on to auto-disable at 0 energy)")
		return

	# After delay elapses, recharge should resume.
	var wait_ticks := int(s.energy_recharge_wait_ticks)
	for _i in range(wait_ticks):
		var e_before := int(s.energy_current)
		world.step_tick({ ship_id: idle })
		if int(s.energy_current) != e_before:
			_fail("abilities_continuous (energy changed during recharge delay after disable)")
			return
	var e0r := int(s.energy_current)
	world.step_tick({ ship_id: idle })
	var e1r := int(s.energy_current)
	if e1r <= e0r and e0r < int(s.energy_max):
		_fail("abilities_continuous (energy did not recharge after delay)")
		return

	_pass("abilities_continuous_drain_and_auto_disable")


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
		"drift_ability_stealth",
		"drift_ability_cloak",
		"drift_ability_xradar",
		"drift_ability_antiwarp",
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
	var allowlist := {}
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
