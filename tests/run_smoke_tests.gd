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
const DriftInput = preload("res://shared/drift_input.gd")
const DriftClassicRuleset = preload("res://shared/drift_classic_ruleset.gd")
const DriftReplayRecorder = preload("res://shared/replay/drift_replay_recorder.gd")
# NOTE: DriftReplayVerifier is a class_name; avoid shadowing it with a preload.
const DriftReplayVerifierScript = preload("res://shared/replay/drift_replay_verifier.gd")
const ScriptedReplayInputs = preload("res://tests/helpers/scripted_replay_inputs.gd")
const BugReportWriter = preload("res://client/replay/bug_report_writer.gd")
const ReplayMeta = preload("res://client/replay/replay_meta.gd")
const DriftTeamColors = preload("res://client/team_colors.gd")
const DriftShipAtlas = preload("res://client/ship_atlas.gd")
const SettingsManager = preload("res://client/settings/settings_manager.gd")
const DriftUiIconAtlas = preload("res://client/ui/ui_icon_atlas.gd")
const DriftPrizeTypes = preload("res://client/ui/prize_types.gd")
const PrizeFeedbackPipeline = preload("res://client/ui/prize_feedback_pipeline.gd")
const DriftShipRegistry = preload("res://shared/drift_ship_registry.gd")

var _failures: int = 0
var _ran: int = 0


func _initialize() -> void:
	_test_drift_input_roundtrip()
	_test_tick_increments_at_end()
	_test_user_settings_roundtrip()
	_test_controls_actions_present()
	_test_controls_default_bindings_wasd()
	_test_controls_weapon_defaults_present()
	_test_no_hardcoded_keys_in_gameplay()
	_test_hud_name_and_bounty_present()
	_test_welcome_includes_ruleset_payload()
	_test_energy_deterministic_recharge_and_costs()
	_test_energy_spend_and_recharge()
	_test_classic_warbird_vs_terrier_bullet_cooldown_and_energy_spend()
	_test_abilities_continuous_drain_and_auto_disable()
	_test_safe_zone_mechanics()
	_test_safe_zone_blocks_actions()
	_test_safe_zone_blocks_damage()
	_test_safe_zone_fire_cancels_velocity()
	_test_spawn_prefers_safe_zone()
	_test_reverse_thrust_does_not_hard_stop_outside_safe_zone()
	_test_energy_fire_costs_and_damage_safe_zone()
	_test_safe_zone_brake_persistent()
	_test_safe_zone_time_limit_forces_non_safe_respawn()
	_test_spawn_protection_blocks_damage()
	_test_bullet_bounce_restitution_is_level_based_per_projectile()
	_test_bullet_swept_collision_prevents_tunneling()
	_test_projectile_velocity_inheritance_sanity()
	_test_mine_trigger_leave_explodes_immediately()
	_test_emp_bomb_applies_engine_shutdown()
	_test_bomb_bounce_depletes_then_explodes()
	_test_bomb_and_mine_max_active_caps_enforced()
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
	_test_world_hash_matches_across_worlds()
	_test_deterministic_collision_order()
	_test_replay_recorder_writes_jsonl()
	_test_replay_verifier_replays_and_hashes()
	_test_replay_verifier_detects_mismatch()
	_test_replay_deterministic_hash_stable()
	if _should_run_replay_hash_soak():
		_test_replay_deterministic_hash_stable_soak()
	_test_weaponized_deterministic_replay_scripted_inputs()
	_test_deterministic_replay_bullets()
	_test_bugreport_writes_artifact()
	_test_bugreport_cleanup_after_zip()
	_test_prizes_spawn_walkable()
	_test_ship_sprite_atlas_mapping()
	_test_ui_icon_atlas_contract_mapping()
	_test_prize_types_mapping_contract()
	_test_prize_feedback_pipeline_transient_non_stacking()
	_test_all_eight_ship_specs_load()
	_test_ship_type_change_respawns_with_correct_spec()
	_test_ship_type_persists_across_snapshot_roundtrip()
	_test_repel_pushes_nearby_ships()
	_test_burst_fires_shrapnel_ring()
	_test_shields_absorb_damage()
	_test_warp_teleports_ship()
	_test_antiwarp_blocks_warp()
	_test_thor_fires_ring()
	_test_rocket_boosts_speed()
	_test_decoy_spawns_and_expires()
	_test_shrapnel_prize_adds_bonus()
	_test_rotation_prize_adds_bonus()
	_test_all_weapons_prize()
	_test_quickcharge_prize_fills_energy()
	_test_stealth_prize_toggles_ability()
	_test_portal_prize_and_use()
	_test_decoy_snapshot_roundtrip()
	_test_brick_places_and_expires()
	_test_items_persist_across_snapshot_roundtrip()
	_test_kill_event_packet_roundtrip()
	_test_chat_message_packet_roundtrip()
	_test_chat_broadcast_packet_roundtrip()
	_test_kill_death_stats_in_snapshot()
	_test_king_ship_id_snapshot_roundtrip()
	_test_server_hello_sets_username()
	_test_kill_scoring_awards_points()
	_test_classic_ship_stats()
	_test_thor_and_burst_classic()
	_test_portal_beacon_roundtrip()
	_test_wormhole_pull_and_teleport()
	_test_two_worlds_do_not_share_arena()
	_test_multifire_toggle_requires_capability()
	_test_multifire_input_roundtrip()
	_test_truncated_packets_rejected()
	_test_chat_commands()
	_test_chat_macros()
	_test_special_negative_prizes()
	_test_insert_spawn_warp()
	_test_default_keybindings_match_original_layout()
	_test_ship_wall_bounce_feel()
	_test_music_library_loads()
	_test_map_editor_undo_and_tools()
	_test_ship_starting_loadouts()
	_test_ability_ownership_and_item_caps()
	_test_king_of_the_hill()
	_test_ball_gated_on_goal_entities()
	print("[SMOKE] Done: ", _ran, " checks, ", _failures, " failures")
	quit(0 if _failures == 0 else 1)


func _test_bullet_swept_collision_prevents_tunneling() -> void:
	_ran += 1
	# Regression: bullets must not tunnel through walls at any speed.
	# This test deliberately sets an absurdly high velocity so the bullet would cross
	# many tiles in a single tick if using discrete end-position checks.
	var world := DriftWorld.new()
	world.set_map_dimensions(80, 60)
	# No tactical fragmentation; focus purely on wall collision correctness.
	world.bullet_shrapnel_count = 0
	world.bullet_bounces = 0
	world.bullet_radius = 2.0

	# Build a solid vertical wall at tile x=20.
	var wall_x: int = 20
	var solids: Array = []
	for y in range(0, 60):
		solids.append([wall_x, y, 0, 0])
	world.set_solid_tiles(solids)

	# Fire many bullets from the left toward the wall at different y positions.
	# Each bullet should be consumed by the wall within the first tick.
	var speed_px_s: float = 250000.0
	var dt: float = float(DriftWorld.DriftConstants.TICK_DT)
	var tile_size: int = int(DriftWorld.TILE_SIZE)

	for i in range(40):
		world.bullets.clear()
		world.next_bullet_id = 1
		var y_tile: int = 2 + i
		var start_pos := Vector2(float((wall_x - 8) * tile_size), float(y_tile * tile_size + int(tile_size / 2)))
		var vel := Vector2(speed_px_s, 0.0)
		# Ensure the discrete end position would land far beyond the wall (tunneling case).
		var end_pos := start_pos + vel * dt
		if end_pos.x <= float((wall_x + 1) * tile_size):
			_fail("bullet_swept_collision_prevents_tunneling (test misconfigured: end_pos not beyond wall)")
			return
		var b := DriftTypes.DriftBulletState.new(1, 123, 1, start_pos, vel, 0, -1, 0, 0)
		world.bullets[1] = b
		# Step one tick with no inputs and no ships.
		world.step_tick({}, false, 0)
		if world.bullets.size() != 0:
			_fail("bullet_swept_collision_prevents_tunneling (bullet tunneled; y_tile=%d pos=%s)" % [y_tile, str((world.bullets.get(1) as DriftTypes.DriftBulletState).position)])
			return

	_pass("bullet_swept_collision_prevents_tunneling")


func _test_projectile_velocity_inheritance_sanity() -> void:
	_ran += 1
	# Physics sanity check (not a damage test): verify projectile velocity inheritance.
	# Logs ship vs bullet velocities for manual verification.
	#
	# Scenarios:
	# 1) High-speed ship firing "forward" (along bullet direction) cannot outrun its own bullet.
	# 2) High-speed ship firing opposite its velocity produces a slower *world-space* bullet
	#    relative to its movement (i.e., "backward relative bullets").
	# 3) Stationary ship behaves like legacy (bullet vel == dir * base_speed).

	var base_text := FileAccess.get_file_as_string("res://rulesets/base.json")
	var base_parsed_v: Variant = JSON.parse_string(base_text)
	if typeof(base_parsed_v) != TYPE_DICTIONARY:
		_fail("projectile_velocity_inheritance (failed to parse res://rulesets/base.json)")
		return

	var ruleset: Dictionary = (base_parsed_v as Dictionary).duplicate(true)
	# Keep velocity stable for this test to make expectations exact.
	ruleset["physics"]["ship_thrust_accel"] = 0.0
	ruleset["physics"]["ship_reverse_accel"] = 0.0
	ruleset["physics"]["ship_max_speed"] = 1000.0
	ruleset["physics"]["ship_base_drag"] = 0.0
	ruleset["physics"]["ship_overspeed_drag"] = 0.0
	ruleset["weapons"]["bullet"]["speed"] = 900.0
	ruleset["weapons"]["bullet"]["lifetime_s"] = 1.0
	ruleset["weapons"]["bullet"]["muzzle_offset"] = 0.0
	ruleset["weapons"]["bullet"]["bounces"] = 0
	ruleset["energy"]["max"] = 9999
	ruleset["energy"]["recharge_rate_per_sec"] = 0
	ruleset["energy"]["recharge_delay_ms"] = 0
	ruleset["energy"]["bullet_energy_cost"] = 0
	ruleset["energy"]["multifire_energy_cost"] = 0
	ruleset["energy"]["bomb_energy_cost"] = 0

	var valid := DriftValidate.validate_ruleset_dict(ruleset)
	if not bool(valid.get("ok", false)):
		_fail("projectile_velocity_inheritance (ruleset validation failed)")
		return
	var canonical_ruleset: Dictionary = valid.get("ruleset", ruleset)
	var bullet_speed: float = float(canonical_ruleset["weapons"]["bullet"]["speed"])

	# Helper: step once and fetch the spawned bullet.
	var _spawn_and_get := func(world: DriftWorld, ship_id: int, cmd: DriftTypes.DriftInputCmd) -> Dictionary:
		world.step_tick({ship_id: cmd}, false, 0)
		var ids: Array = world.bullets.keys()
		ids.sort()
		if ids.is_empty():
			return {"ok": false, "error": "no_bullet"}
		var bid: int = int(ids[0])
		return {"ok": true, "bid": bid, "b": world.bullets.get(bid), "s": world.ships.get(ship_id)}

	# --- 1) Forward: ship cannot outrun its own bullet ---
	var w1 := DriftWorld.new()
	w1.apply_ruleset(canonical_ruleset)
	w1.set_solid_tiles([])
	w1.set_door_tiles([])
	w1.add_boundary_tiles(64, 64)
	w1.set_map_dimensions(64, 64)
	w1.add_ship(1, Vector2(400, 400))  # off arena center: the powerball spawns there and fire = kick
	var s1: DriftTypes.DriftShipState = w1.ships.get(1)
	s1.rotation = 0.0
	s1.velocity = Vector2(650.0, 0.0)
	var r1: Dictionary = _spawn_and_get.call(w1, 1, DriftTypes.DriftInputCmd.new(0.0, 0.0, true, false, false))
	if not bool(r1.get("ok", false)):
		_fail("projectile_velocity_inheritance (forward: no bullet spawned)")
		return
	var b1: DriftTypes.DriftBulletState = r1.get("b")
	var ship_v1: Vector2 = (r1.get("s") as DriftTypes.DriftShipState).velocity
	var dir1 := Vector2(1.0, 0.0)
	var rel1: float = (b1.velocity - ship_v1).dot(dir1)
	print("[PHYS_SANITY] forward ship_v=", ship_v1, " bullet_v=", b1.velocity, " rel_fwd=", rel1)
	if not (b1.velocity.dot(dir1) > ship_v1.dot(dir1) + 0.1):
		_fail("projectile_velocity_inheritance (forward: bullet not faster than ship)")
		return
	if absf(rel1 - bullet_speed) > 0.01:
		_fail("projectile_velocity_inheritance (forward: expected inherited rel speed %f, got %f)" % [bullet_speed, rel1])
		return

	# --- 2) "Backward relative": ship moving +X but firing toward -X ---
	var w2 := DriftWorld.new()
	w2.apply_ruleset(canonical_ruleset)
	w2.set_solid_tiles([])
	w2.set_door_tiles([])
	w2.add_boundary_tiles(64, 64)
	w2.set_map_dimensions(64, 64)
	w2.add_ship(1, Vector2(400, 400))  # off arena center: the powerball spawns there and fire = kick
	var s2: DriftTypes.DriftShipState = w2.ships.get(1)
	s2.rotation = PI # face -X
	s2.velocity = Vector2(650.0, 0.0) # still moving +X
	var r2: Dictionary = _spawn_and_get.call(w2, 1, DriftTypes.DriftInputCmd.new(0.0, 0.0, true, false, false))
	if not bool(r2.get("ok", false)):
		_fail("projectile_velocity_inheritance (backward: no bullet spawned)")
		return
	var b2: DriftTypes.DriftBulletState = r2.get("b")
	var ship_v2: Vector2 = (r2.get("s") as DriftTypes.DriftShipState).velocity
	var dir2 := Vector2(-1.0, 0.0)
	var rel2: float = (b2.velocity - ship_v2).dot(dir2)
	print("[PHYS_SANITY] backward ship_v=", ship_v2, " bullet_v=", b2.velocity, " rel_back=", rel2)
	# Bullet should be slower along +X than the ship (since it was fired toward -X).
	if not (b2.velocity.x < ship_v2.x - 0.1):
		_fail("projectile_velocity_inheritance (backward: expected bullet.x < ship.x)")
		return
	if absf(rel2 - bullet_speed) > 0.01:
		_fail("projectile_velocity_inheritance (backward: expected rel speed %f along dir, got %f)" % [bullet_speed, rel2])
		return

	# --- 3) Stationary: legacy behavior preserved ---
	var w3 := DriftWorld.new()
	w3.apply_ruleset(canonical_ruleset)
	w3.set_solid_tiles([])
	w3.set_door_tiles([])
	w3.add_boundary_tiles(64, 64)
	w3.set_map_dimensions(64, 64)
	w3.add_ship(1, Vector2(400, 400))  # off arena center: the powerball spawns there and fire = kick
	var s3: DriftTypes.DriftShipState = w3.ships.get(1)
	s3.rotation = 0.0
	s3.velocity = Vector2.ZERO
	var r3: Dictionary = _spawn_and_get.call(w3, 1, DriftTypes.DriftInputCmd.new(0.0, 0.0, true, false, false))
	if not bool(r3.get("ok", false)):
		_fail("projectile_velocity_inheritance (stationary: no bullet spawned)")
		return
	var b3: DriftTypes.DriftBulletState = r3.get("b")
	var ship_v3: Vector2 = (r3.get("s") as DriftTypes.DriftShipState).velocity
	var dir3 := Vector2(1.0, 0.0)
	var rel3: float = (b3.velocity - ship_v3).dot(dir3)
	print("[PHYS_SANITY] stationary ship_v=", ship_v3, " bullet_v=", b3.velocity, " rel_fwd=", rel3)
	if ship_v3.length() > 0.001:
		_fail("projectile_velocity_inheritance (stationary: ship unexpectedly moved)")
		return
	if absf(rel3 - bullet_speed) > 0.01:
		_fail("projectile_velocity_inheritance (stationary: expected base speed %f, got %f)" % [bullet_speed, rel3])
		return

	_pass("projectile_velocity_inheritance_sanity")


func _test_mine_trigger_leave_explodes_immediately() -> void:
	_ran += 1
	# Proximity mine rule: once triggered, if the triggering enemy leaves the trigger radius,
	# the mine must explode immediately (no waiting out the fuse).

	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("mine_trigger_leave (failed to load base ruleset)")
		return
	var rs: Dictionary = rules_res.get("ruleset", {})
	if typeof(rs) != TYPE_DICTIONARY:
		_fail("mine_trigger_leave (ruleset missing)")
		return
	# Ensure teams exist so mine hostility logic is unambiguous.
	rs["team"] = {"max_freq": 2, "force_even": false}
	var valid := DriftValidate.validate_ruleset_dict(rs)
	if not bool(valid.get("ok", false)):
		_fail("mine_trigger_leave (ruleset validation failed)")
		return
	var canonical_ruleset: Dictionary = valid.get("ruleset", rs)

	var world := DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(64, 64)
	world.set_map_dimensions(64, 64)

	# Enable ship_spec weapon overrides so we can force 0 cost/0 delay deterministically.
	world.set_ship_spec_overrides_weapons(true)
	world.set_ship_spec({
		"energy": {"InitialEnergy": 9999, "LandmineFireEnergy": 0, "LandmineFireEnergyUpgrade": 0},
		"weapons": {"LandmineFireDelay": 0, "MaxMines": 10},
	})

	world.add_ship(1, Vector2(512, 512))
	world.add_ship(2, Vector2(800, 512))
	world.set_ship_freq(1, 0)
	world.set_ship_freq(2, 1)
	var s1: DriftTypes.DriftShipState = world.ships.get(1)
	var s2: DriftTypes.DriftShipState = world.ships.get(2)
	if s1 == null or s2 == null:
		_fail("mine_trigger_leave (ship missing)")
		return
	s1.rotation = 0.0
	s1.velocity = Vector2.ZERO
	s2.velocity = Vector2.ZERO

	# Lay exactly one mine.
	var lay_cmd := DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false, false, false, false, false, true)
	world.step_tick({1: lay_cmd}, false, 0)
	if world.mines.size() != 1:
		_fail("mine_trigger_leave (expected 1 mine laid; got %d)" % int(world.mines.size()))
		return
	var mine_ids: Array = world.mines.keys()
	mine_ids.sort()
	var mid: int = int(mine_ids[0])
	var m: DriftTypes.DriftMineState = world.mines.get(mid)
	if m == null:
		_fail("mine_trigger_leave (mine missing)")
		return

	# Move enemy into trigger radius and step once -> should trigger but not explode.
	s2.position = m.position + Vector2(float(DriftWorld.MINE_TRIGGER_RADIUS_PX) - 1.0, 0.0)
	world.step_tick({}, false, 0)
	if not world.mines.has(mid):
		_fail("mine_trigger_leave (mine exploded on trigger tick; expected triggered state first)")
		return
	var m2: DriftTypes.DriftMineState = world.mines.get(mid)
	if m2 == null or not bool(m2.triggered):
		_fail("mine_trigger_leave (expected mine triggered after enemy enters radius)")
		return

	# Now move enemy outside trigger radius and step once -> must explode immediately.
	s2.position = m2.position + Vector2(float(DriftWorld.MINE_TRIGGER_RADIUS_PX) + 10.0, 0.0)
	world.step_tick({}, false, 0)
	if world.mines.size() != 0:
		_fail("mine_trigger_leave (expected mine removed after leave-radius; mines=%d)" % int(world.mines.size()))
		return
	var saw_explode := false
	for ev_any in world.collision_events:
		if typeof(ev_any) != TYPE_DICTIONARY:
			continue
		var ev: Dictionary = ev_any
		if str(ev.get("type", "")) == "mine_explode":
			saw_explode = true
			break
	if not saw_explode:
		_fail("mine_trigger_leave (expected mine_explode event)")
		return

	_pass("mine_trigger_leave_explodes_immediately")


func _test_emp_bomb_applies_engine_shutdown() -> void:
	_ran += 1
	# EMP bombs must apply engine shutdown deterministically when they explode.

	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("emp_bomb (failed to load base ruleset)")
		return
	var rs: Dictionary = rules_res.get("ruleset", {})
	if typeof(rs) != TYPE_DICTIONARY:
		_fail("emp_bomb (ruleset missing)")
		return
	rs["team"] = {"max_freq": 2, "force_even": false}
	var valid := DriftValidate.validate_ruleset_dict(rs)
	if not bool(valid.get("ok", false)):
		_fail("emp_bomb (ruleset validation failed)")
		return
	var canonical_ruleset: Dictionary = valid.get("ruleset", rs)

	var world := DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(64, 64)
	world.set_map_dimensions(64, 64)
	world.set_ship_spec_overrides_weapons(true)
	world.set_ship_spec({
		"energy": {"InitialEnergy": 9999, "BombFireEnergy": 0, "BombFireEnergyUpgrade": 0},
		"weapons": {"BombFireDelay": 0, "BombSpeed": 0, "BombBounceCount": 0, "MaxBombs": 10, "EmpBomb": 1},
	})

	world.add_ship(1, Vector2(512, 512))
	world.add_ship(2, Vector2(512, 512))
	world.set_ship_freq(1, 0)
	world.set_ship_freq(2, 1)
	var s1: DriftTypes.DriftShipState = world.ships.get(1)
	var s2: DriftTypes.DriftShipState = world.ships.get(2)
	if s1 == null or s2 == null:
		_fail("emp_bomb (ship missing)")
		return
	s1.rotation = 0.0
	s1.velocity = Vector2.ZERO
	s2.velocity = Vector2.ZERO
	s2.engine_shutdown_until_tick = 0

	# Place enemy exactly at the bomb spawn position so detonation occurs immediately.
	var fwd := Vector2(1.0, 0.0)
	var spawn_pos := s1.position + fwd * (float(DriftConstants.SHIP_RADIUS) + float(DriftWorld.BOMB_RADIUS_PX) + 2.0)
	s2.position = spawn_pos

	var t0: int = int(world.tick)
	var fire_cmd := DriftTypes.DriftInputCmd.new(0.0, 0.0, false, true, false)
	world.step_tick({1: fire_cmd}, false, 0)

	# Bomb should have exploded in the same tick.
	if world.bombs.size() != 0:
		_fail("emp_bomb (expected bombs cleared after immediate detonation)")
		return
	var s2_after: DriftTypes.DriftShipState = world.ships.get(2)
	if s2_after == null:
		_fail("emp_bomb (enemy ship missing after step)")
		return
	if int(s2_after.engine_shutdown_until_tick) < t0 + int(DriftWorld.EMP_DEFAULT_TICKS):
		_fail("emp_bomb (expected engine_shutdown_until_tick >= %d; got %d)" % [t0 + int(DriftWorld.EMP_DEFAULT_TICKS), int(s2_after.engine_shutdown_until_tick)])
		return
	var saw_emp_explode := false
	for ev_any in world.collision_events:
		if typeof(ev_any) != TYPE_DICTIONARY:
			continue
		var ev: Dictionary = ev_any
		if str(ev.get("type", "")) == "bomb_explode" and bool(ev.get("emp", false)):
			saw_emp_explode = true
			break
	if not saw_emp_explode:
		_fail("emp_bomb (expected bomb_explode event with emp=true)")
		return

	_pass("emp_bomb_applies_engine_shutdown")


func _test_bomb_bounce_depletes_then_explodes() -> void:
	_ran += 1
	# Bombs with bounces_left>0 should bounce off walls consuming a bounce.
	# When bounces_left==0, the next wall impact should detonate.

	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("bomb_bounce (failed to load base ruleset)")
		return
	var rs: Dictionary = rules_res.get("ruleset", {})
	if typeof(rs) != TYPE_DICTIONARY:
		_fail("bomb_bounce (ruleset missing)")
		return
	rs["team"] = {"max_freq": 2, "force_even": false}
	var valid := DriftValidate.validate_ruleset_dict(rs)
	if not bool(valid.get("ok", false)):
		_fail("bomb_bounce (ruleset validation failed)")
		return
	var canonical_ruleset: Dictionary = valid.get("ruleset", rs)

	var world := DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_door_tiles([])
	world.add_boundary_tiles(64, 64)
	world.set_map_dimensions(64, 64)
	world.set_ship_spec_overrides_weapons(true)
	world.set_ship_spec({
		"energy": {"InitialEnergy": 9999, "BombFireEnergy": 0, "BombFireEnergyUpgrade": 0},
		"weapons": {"BombFireDelay": 0, "BombSpeed": 2000, "BombBounceCount": 1, "MaxBombs": 10, "EmpBomb": 0},
	})

	# Create two vertical walls so the bomb will ping-pong: first hit consumes bounce, second hit detonates.
	var solids: Array = []
	var wall_x1: int = 20
	var wall_x2: int = 30
	for y in range(0, 64):
		solids.append([wall_x1, y, 0, 0])
		solids.append([wall_x2, y, 0, 0])
	world.set_solid_tiles(solids)

	world.add_ship(1, Vector2(float(25 * 16), float(25 * 16)))
	world.set_ship_freq(1, 0)
	var s1: DriftTypes.DriftShipState = world.ships.get(1)
	if s1 == null:
		_fail("bomb_bounce (ship missing)")
		return
	s1.rotation = 0.0
	s1.velocity = Vector2.ZERO

	# Fire one bomb.
	world.step_tick({1: DriftTypes.DriftInputCmd.new(0.0, 0.0, false, true, false)}, false, 0)
	if world.bombs.size() != 1:
		_fail("bomb_bounce (expected 1 bomb spawned; got %d)" % int(world.bombs.size()))
		return
	var bomb_ids: Array = world.bombs.keys()
	bomb_ids.sort()
	var bid: int = int(bomb_ids[0])
	var b: DriftTypes.DriftBombState = world.bombs.get(bid)
	if b == null:
		_fail("bomb_bounce (bomb missing)")
		return

	# Move owner away from the corridor so the bomb doesn't detonate on self.
	s1.position = Vector2(s1.position.x, s1.position.y + 400.0)

	# Step until we observe the first bounce (bounces_left becomes 0) and later detonation.
	var saw_bounces_depleted := false
	var saw_explode := false
	for i in range(0, 120):
		world.step_tick({}, false, 0)
		if world.bombs.has(bid):
			var bb: DriftTypes.DriftBombState = world.bombs.get(bid)
			if bb != null and int(bb.bounces_left) == 0:
				saw_bounces_depleted = true
		else:
			for ev_any in world.collision_events:
				if typeof(ev_any) != TYPE_DICTIONARY:
					continue
				var ev: Dictionary = ev_any
				if str(ev.get("type", "")) == "bomb_explode":
					saw_explode = true
					break
			break

	if not saw_bounces_depleted:
		_fail("bomb_bounce (expected to observe bounces_left depleted to 0 before detonation)")
		return
	if not saw_explode:
		_fail("bomb_bounce (expected bomb_explode after second wall hit)")
		return

	_pass("bomb_bounce_depletes_then_explodes")


func _test_bomb_and_mine_max_active_caps_enforced() -> void:
	_ran += 1
	# Enforce MaxBombs/MaxMines: even with 0 delay and 0 energy cost, we must not spawn
	# more than the configured active count.

	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("weapon_caps (failed to load base ruleset)")
		return
	var rs: Dictionary = rules_res.get("ruleset", {})
	if typeof(rs) != TYPE_DICTIONARY:
		_fail("weapon_caps (ruleset missing)")
		return
	rs["team"] = {"max_freq": 2, "force_even": false}
	var valid := DriftValidate.validate_ruleset_dict(rs)
	if not bool(valid.get("ok", false)):
		_fail("weapon_caps (ruleset validation failed)")
		return
	var canonical_ruleset: Dictionary = valid.get("ruleset", rs)

	var world := DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(64, 64)
	world.set_map_dimensions(64, 64)
	world.set_ship_spec_overrides_weapons(true)
	world.set_ship_spec({
		"energy": {
			"InitialEnergy": 9999,
			"BombFireEnergy": 0,
			"BombFireEnergyUpgrade": 0,
			"LandmineFireEnergy": 0,
			"LandmineFireEnergyUpgrade": 0,
		},
		"weapons": {
			"BombFireDelay": 0,
			"BombSpeed": 0,
			"BombBounceCount": 0,
			"MaxBombs": 1,
			"EmpBomb": 0,
			"LandmineFireDelay": 0,
			"MaxMines": 1,
		},
	})
	world.add_ship(1, Vector2(512, 512))
	world.set_ship_freq(1, 0)
	var s1: DriftTypes.DriftShipState = world.ships.get(1)
	if s1 == null:
		_fail("weapon_caps (ship missing)")
		return
	s1.rotation = 0.0
	s1.velocity = Vector2.ZERO

	# Spam bomb fire for a few ticks; cap must hold at 1.
	for i in range(0, 5):
		world.step_tick({1: DriftTypes.DriftInputCmd.new(0.0, 0.0, false, true, false)}, false, 0)
		if world.bombs.size() > 1:
			_fail("weapon_caps (expected MaxBombs=1; got %d)" % int(world.bombs.size()))
			return
	if world.bombs.size() != 1:
		_fail("weapon_caps (expected exactly 1 bomb active; got %d)" % int(world.bombs.size()))
		return

	# Spam mine lay for a few ticks; cap must hold at 1.
	var lay_cmd := DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false, false, false, false, false, true)
	for i in range(0, 5):
		world.step_tick({1: lay_cmd}, false, 0)
		if world.mines.size() > 1:
			_fail("weapon_caps (expected MaxMines=1; got %d)" % int(world.mines.size()))
			return
	if world.mines.size() != 1:
		_fail("weapon_caps (expected exactly 1 mine active; got %d)" % int(world.mines.size()))
		return

	_pass("bomb_and_mine_max_active_caps_enforced")


func _test_prize_types_mapping_contract() -> void:
	_ran += 1
	# Ensure the logical PrizeType mapping exists for the explicitly supported kinds,
	# and that any mapped icons are renderable in the contracted atlas.
	var kinds := [
		DriftTypes.PrizeKind.Gun,
		DriftTypes.PrizeKind.Bomb,
		DriftTypes.PrizeKind.MultiFire,
		DriftTypes.PrizeKind.BouncingBullets,
		DriftTypes.PrizeKind.Proximity,
		DriftTypes.PrizeKind.Shrapnel,
		DriftTypes.PrizeKind.Burst,
		DriftTypes.PrizeKind.Repel,
		DriftTypes.PrizeKind.Decoy,
		DriftTypes.PrizeKind.Thor,
		DriftTypes.PrizeKind.Brick,
		DriftTypes.PrizeKind.Rocket,
		DriftTypes.PrizeKind.Portal,
		DriftTypes.PrizeKind.Energy,
		DriftTypes.PrizeKind.QuickCharge,
		DriftTypes.PrizeKind.Stealth,
		DriftTypes.PrizeKind.XRadar,
		DriftTypes.PrizeKind.AntiWarp,
	]
	for k in kinds:
		var t: int = DriftPrizeTypes.prize_type_from_prize_kind(int(k))
		if t < 0:
			_fail("prize_types_mapping_contract (missing PrizeType for kind=%s)" % str(k))
			return
		var label: String = DriftPrizeTypes.label_for_prize_kind(int(k))
		if label == "":
			_fail("prize_types_mapping_contract (empty label for kind=%s)" % str(k))
			return
		var sid: String = DriftPrizeTypes.sound_id_for_prize_kind(int(k))
		if sid == "":
			_fail("prize_types_mapping_contract (empty sound_id for kind=%s)" % str(k))
			return
		var atlas: Vector2i = DriftPrizeTypes.icon_atlas_coords_for_prize_kind(int(k))
		if atlas.x >= 0:
			if not DriftUiIconAtlas.coords_is_renderable(atlas):
				_fail("prize_types_mapping_contract (non-renderable icon for kind=%s atlas=%s)" % [str(k), str(atlas)])
				return
	_pass("prize_types_mapping_contract")


func _test_prize_feedback_pipeline_transient_non_stacking() -> void:
	_ran += 1
	# Pipeline must be tick-based (replay safe), transient, and non-stacking.
	var p = PrizeFeedbackPipeline.new()
	# Seed cache with a few prize states.
	var st1 := DriftTypes.DriftPrizeState.new(100, Vector2.ZERO, 0, 999, DriftTypes.PrizeKind.Gun, false, false)
	var st2 := DriftTypes.DriftPrizeState.new(101, Vector2.ZERO, 0, 999, DriftTypes.PrizeKind.Burst, false, false)
	p.cache_prize_states([st1, st2])

	# Two local pickups in same event batch: last one wins.
	var events := [
		{"type": "pickup", "ship_id": 7, "prize_id": 100},
		{"type": "pickup", "ship_id": 7, "prize_id": 101},
	]
	p.consume_prize_events(500, events, 7)
	if not p.take_pickup_sfx_trigger():
		_fail("prize_feedback_pipeline (expected one-shot sfx trigger)")
		return
	if p.take_pickup_sfx_trigger():
		_fail("prize_feedback_pipeline (sfx trigger must not repeat)")
		return
	var txt := p.get_feedback_text_for_tick(500)
	if txt.find("Burst") < 0:
		_fail("prize_feedback_pipeline (expected last pickup label to win; got '%s')" % txt)
		return
	var icon := p.get_feedback_icon_for_tick(500)
	# Burst icon is contract row3 col3 => atlas (col=3,row=3).
	if icon != DriftUiIconAtlas.rc(3, 3):
		_fail("prize_feedback_pipeline (expected burst icon atlas (3,3); got %s)" % str(icon))
		return
	var pt := p.get_feedback_prize_type_for_tick(500)
	if pt != int(DriftPrizeTypes.PrizeType.BURST):
		_fail("prize_feedback_pipeline (expected prize_type BURST; got %s)" % str(pt))
		return
	var toast_lbl := p.get_feedback_toast_label_for_tick(500)
	if toast_lbl.find("Burst") < 0:
		_fail("prize_feedback_pipeline (expected toast label to contain Burst; got '%s')" % toast_lbl)
		return
	# Should still be visible before expiry.
	if p.get_feedback_text_for_tick(p.get_feedback_until_tick() - 1) == "":
		_fail("prize_feedback_pipeline (expected visible before expiry)")
		return
	# Must expire at until_tick.
	if p.get_feedback_text_for_tick(p.get_feedback_until_tick()) != "":
		_fail("prize_feedback_pipeline (expected expired at until_tick)")
		return
	_pass("prize_feedback_pipeline_transient_non_stacking")


func _test_ui_icon_atlas_contract_mapping() -> void:
	_ran += 1
	# Strictly validate the fixed icon atlas mapping contract.
	# This does not render; it asserts that our selection code returns exactly the
	# contracted (row,col) cells and never marks reserved blanks as renderable.

	# Guns row 0 (no bounce) and row 1 (bounce).
	if DriftUiIconAtlas.gun_icon_coords(1, false, false, false) != DriftUiIconAtlas.rc(0, 0):
		_fail("ui_icon_atlas (gun L1 single expected (0,0))")
		return
	if DriftUiIconAtlas.gun_icon_coords(2, false, true, true) != DriftUiIconAtlas.rc(0, 4):
		_fail("ui_icon_atlas (gun L2 multishot enabled expected (0,4))")
		return
	if DriftUiIconAtlas.gun_icon_coords(3, true, true, false) != DriftUiIconAtlas.rc(1, 8):
		_fail("ui_icon_atlas (gun L3 multishot owned single-fire+bounce expected (1,8))")
		return

	# Bombs row 2 base variants; row 3 prox+shrap.
	if DriftUiIconAtlas.bomb_icon_coords(2, false, false) != DriftUiIconAtlas.rc(2, 1):
		_fail("ui_icon_atlas (bomb L2 no prox no shrap expected (2,1))")
		return
	if DriftUiIconAtlas.bomb_icon_coords(3, true, false) != DriftUiIconAtlas.rc(2, 5):
		_fail("ui_icon_atlas (bomb L3 prox no shrap expected (2,5))")
		return
	if DriftUiIconAtlas.bomb_icon_coords(1, false, true) != DriftUiIconAtlas.rc(2, 6):
		_fail("ui_icon_atlas (bomb L1 no prox shrap expected (2,6))")
		return
	if DriftUiIconAtlas.bomb_icon_coords(2, true, true) != DriftUiIconAtlas.rc(3, 1):
		_fail("ui_icon_atlas (bomb L2 prox+shrap expected (3,1))")
		return

	# Misc (row 3/4 toggles).
	if DriftUiIconAtlas.inventory_icon_coords(&"burst") != DriftUiIconAtlas.rc(3, 3):
		_fail("ui_icon_atlas (burst expected (3,3))")
		return
	if DriftUiIconAtlas.inventory_icon_coords(&"repel") != DriftUiIconAtlas.rc(3, 4):
		_fail("ui_icon_atlas (repel expected (3,4))")
		return
	if DriftUiIconAtlas.toggle_icon_coords(&"radar", true) != DriftUiIconAtlas.rc(3, 5):
		_fail("ui_icon_atlas (radar ON expected (3,5))")
		return
	if DriftUiIconAtlas.toggle_icon_coords(&"radar", false) != DriftUiIconAtlas.rc(3, 6):
		_fail("ui_icon_atlas (radar OFF expected (3,6))")
		return
	if DriftUiIconAtlas.toggle_icon_coords(&"stealth", true) != DriftUiIconAtlas.rc(3, 7):
		_fail("ui_icon_atlas (stealth ON expected (3,7))")
		return
	if DriftUiIconAtlas.toggle_icon_coords(&"stealth", false) != DriftUiIconAtlas.rc(3, 8):
		_fail("ui_icon_atlas (stealth OFF expected (3,8))")
		return
	if DriftUiIconAtlas.toggle_icon_coords(&"xradar", true) != DriftUiIconAtlas.rc(4, 0):
		_fail("ui_icon_atlas (xradar ON expected (4,0))")
		return
	if DriftUiIconAtlas.toggle_icon_coords(&"xradar", false) != DriftUiIconAtlas.rc(4, 1):
		_fail("ui_icon_atlas (xradar OFF expected (4,1))")
		return
	if DriftUiIconAtlas.toggle_icon_coords(&"antiwarp", true) != DriftUiIconAtlas.rc(4, 2):
		_fail("ui_icon_atlas (antiwarp ON expected (4,2))")
		return
	if DriftUiIconAtlas.toggle_icon_coords(&"antiwarp", false) != DriftUiIconAtlas.rc(4, 3):
		_fail("ui_icon_atlas (antiwarp OFF expected (4,3))")
		return

	# Inventory row 4.
	if DriftUiIconAtlas.inventory_icon_coords(&"decoy") != DriftUiIconAtlas.rc(4, 4):
		_fail("ui_icon_atlas (decoy expected (4,4))")
		return
	if DriftUiIconAtlas.inventory_icon_coords(&"thor") != DriftUiIconAtlas.rc(4, 5):
		_fail("ui_icon_atlas (thor expected (4,5))")
		return
	if DriftUiIconAtlas.inventory_icon_coords(&"brick") != DriftUiIconAtlas.rc(4, 6):
		_fail("ui_icon_atlas (brick expected (4,6))")
		return
	if DriftUiIconAtlas.inventory_icon_coords(&"thruster") != DriftUiIconAtlas.rc(4, 7):
		_fail("ui_icon_atlas (thruster expected (4,7))")
		return
	if DriftUiIconAtlas.inventory_icon_coords(&"rocket") != DriftUiIconAtlas.rc(4, 8):
		_fail("ui_icon_atlas (rocket expected (4,8))")
		return

	# Keys / teleport / placeholders.
	if DriftUiIconAtlas.key_icon_coords() != DriftUiIconAtlas.rc(5, 0):
		_fail("ui_icon_atlas (key expected (5,0))")
		return
	if DriftUiIconAtlas.teleport_icon_coords() != DriftUiIconAtlas.rc(5, 1):
		_fail("ui_icon_atlas (teleport expected (5,1))")
		return
	if DriftUiIconAtlas.empty_placeholder_coords(DriftUiIconAtlas.Side.RIGHT) != DriftUiIconAtlas.rc(5, 3):
		_fail("ui_icon_atlas (right placeholder expected (5,3))")
		return
	if DriftUiIconAtlas.empty_placeholder_coords(DriftUiIconAtlas.Side.LEFT) != DriftUiIconAtlas.rc(5, 5):
		_fail("ui_icon_atlas (left placeholder expected (5,5))")
		return

	# Reserved blanks must never be renderable.
	var blanks: Array[Vector2i] = [
		DriftUiIconAtlas.rc(5, 2),
		DriftUiIconAtlas.rc(5, 4),
		DriftUiIconAtlas.rc(5, 6),
		DriftUiIconAtlas.rc(5, 7),
		DriftUiIconAtlas.rc(5, 8),
	]
	for b in blanks:
		if not DriftUiIconAtlas.coords_is_blank(b):
			_fail("ui_icon_atlas (expected blank at %s)" % str(b))
			return
		if DriftUiIconAtlas.coords_is_renderable(b):
			_fail("ui_icon_atlas (blank must not be renderable at %s)" % str(b))
			return

	# Placeholders are renderable.
	var ph_r := DriftUiIconAtlas.empty_placeholder_coords(DriftUiIconAtlas.Side.RIGHT)
	var ph_l := DriftUiIconAtlas.empty_placeholder_coords(DriftUiIconAtlas.Side.LEFT)
	if not DriftUiIconAtlas.coords_is_renderable(ph_r) or not DriftUiIconAtlas.coords_is_renderable(ph_l):
		_fail("ui_icon_atlas (placeholders should be renderable)")
		return

	_pass("ui_icon_atlas_contract_mapping")


func _test_bugreport_cleanup_after_zip() -> void:
	_ran += 1
	# Validate bugreport retention policy options:
	# 1) cleanup flag false -> folder exists after (attempted) zip
	# 2) cleanup flag true + zip succeeds -> folder removed
	# 3) cleanup flag true + zip fails -> folder remains
	#
	# This runs headless and uses a deterministic forced zip failure for case 3.
	var world := DriftWorld.new()
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)
	world.add_ship(1, Vector2(64, 64))

	var records: Array = [
		{"t": 0, "inputs": [[1, {"thrust": 0, "turn": 0, "fire": false}]]},
		{"t": 1, "inputs": [[1, {"thrust": 1, "turn": 0, "fire": true}]]},
	]
	var meta: Dictionary = ReplayMeta.build_replay_meta(world, {"map_path": "res://maps/default.json", "ruleset_hash": 0})
	meta["bugreport_trigger"] = "smoke_test"
	var mismatch: Dictionary = {"reason": "smoke_bugreport_cleanup", "detail": {"note": "test"}}

	# Use user:// to avoid relying on res:// writability.
	var root: String = "user://.ci_artifacts/bugreports_smoke_cleanup"

	# Case 1: cleanup false -> folder exists after zip.
	var res1: Dictionary = BugReportWriter.save_bug_report("smoke_cleanup_false", meta, records, mismatch, {
		"root": root,
		"fallback_root": root,
		"zip": true,
		"bugreport_cleanup_after_zip": false,
	})
	if not bool(res1.get("ok", false)):
		_fail("bugreport_cleanup_after_zip (case1 save failed: %s)" % String(res1.get("error", "unknown")))
		return
	var folder1: String = String(res1.get("folder", ""))
	var zip1: String = String(res1.get("zip", ""))
	if folder1 == "":
		_fail("bugreport_cleanup_after_zip (case1 missing folder)")
		return
	var folder1_abs: String = ProjectSettings.globalize_path(folder1)
	if not DirAccess.dir_exists_absolute(folder1_abs):
		_fail("bugreport_cleanup_after_zip (case1 folder missing after save)")
		return
	if zip1 == "" or not FileAccess.file_exists(zip1):
		# Zip should succeed in headless editor/CI; if it doesn't, fail loudly so we notice.
		_fail("bugreport_cleanup_after_zip (case1 zip missing; zip may be unavailable in this environment)")
		return

	# Cleanup case1 artifacts (best-effort).
	BugReportWriter._delete_dir_recursive_absolute(folder1_abs)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(zip1))

	# Case 2: cleanup true + zip succeeds -> folder removed.
	var res2: Dictionary = BugReportWriter.save_bug_report("smoke_cleanup_true", meta, records, mismatch, {
		"root": root,
		"fallback_root": root,
		"zip": true,
		"bugreport_cleanup_after_zip": true,
	})
	if not bool(res2.get("ok", false)):
		_fail("bugreport_cleanup_after_zip (case2 save failed: %s)" % String(res2.get("error", "unknown")))
		return
	var folder2: String = String(res2.get("folder", ""))
	var zip2: String = String(res2.get("zip", ""))
	if folder2 == "":
		_fail("bugreport_cleanup_after_zip (case2 missing folder)")
		return
	if zip2 == "" or not FileAccess.file_exists(zip2):
		_fail("bugreport_cleanup_after_zip (case2 zip missing; cannot validate cleanup-after-zip)")
		return
	var folder2_abs: String = ProjectSettings.globalize_path(folder2)
	if DirAccess.dir_exists_absolute(folder2_abs):
		# If deletion fails, writer should keep folder; this means cleanup didn't happen.
		_fail("bugreport_cleanup_after_zip (case2 expected folder deleted, but it still exists)")
		return

	# Cleanup case2 zip (best-effort).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(zip2))

	# Case 3: cleanup true but zip fails -> folder remains.
	var res3: Dictionary = BugReportWriter.save_bug_report("smoke_cleanup_zipfail", meta, records, mismatch, {
		"root": root,
		"fallback_root": root,
		"zip": true,
		"bugreport_cleanup_after_zip": true,
		"zip_force_fail": true,
	})
	if not bool(res3.get("ok", false)):
		_fail("bugreport_cleanup_after_zip (case3 save failed: %s)" % String(res3.get("error", "unknown")))
		return
	var folder3: String = String(res3.get("folder", ""))
	var zip3: String = String(res3.get("zip", ""))
	if folder3 == "":
		_fail("bugreport_cleanup_after_zip (case3 missing folder)")
		return
	if zip3 != "":
		_fail("bugreport_cleanup_after_zip (case3 expected no zip, got %s)" % zip3)
		return
	var folder3_abs: String = ProjectSettings.globalize_path(folder3)
	if not DirAccess.dir_exists_absolute(folder3_abs):
		_fail("bugreport_cleanup_after_zip (case3 expected folder to remain on zip failure)")
		return

	# Cleanup case3 artifacts (best-effort).
	BugReportWriter._delete_dir_recursive_absolute(folder3_abs)

	_pass("bugreport_cleanup_after_zip")


func _should_run_replay_hash_soak() -> bool:
	# Opt-in only: the soak test is intentionally longer.
	# Enable in CI/dev via env var:
	#   DRIFTLINE_SMOKE_SOAK_REPLAY_HASH=1
	var v: String = String(OS.get_environment("DRIFTLINE_SMOKE_SOAK_REPLAY_HASH"))
	v = v.strip_edges().to_lower()
	return v == "1" or v == "true" or v == "yes" or v == "on"


func _test_weaponized_deterministic_replay_scripted_inputs() -> void:
	_ran += 1
	# CI-friendly deterministic replay test:
	# 1) boot minimal world
	# 2) run scripted movement + firing
	# 3) record replay
	# 4) re-run same script and assert per-tick hashes match
	# On mismatch: dump artifact bundle into res://.ci_artifacts/...
	var test_name: String = "weaponized_deterministic_replay"
	var path_a := "user://replays/%s_a.jsonl" % test_name
	var path_b := "user://replays/%s_b.jsonl" % test_name
	var setup_world := Callable(self, "_setup_world_for_weaponized_deterministic_replay")
	var ticks: int = 90 # Keep runtime short.

	# Best-effort cleanup from previous runs.
	if FileAccess.file_exists(path_a):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_a))
	if FileAccess.file_exists(path_b):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_b))

	var res_a: Dictionary = _record_scripted_replay(path_a, ticks, setup_world)
	if not bool(res_a.get("ok", false)):
		_fail("%s (record A failed: %s)" % [test_name, str(res_a.get("error", "unknown"))])
		return
	var res_b: Dictionary = _record_scripted_replay(path_b, ticks, setup_world)
	if not bool(res_b.get("ok", false)):
		_fail("%s (record B failed: %s)" % [test_name, str(res_b.get("error", "unknown"))])
		return

	var hashes_a: Array = res_a.get("hashes", [])
	var hashes_b: Array = res_b.get("hashes", [])
	if hashes_a.size() != hashes_b.size():
		var summary := {
			"error": "hash_count_mismatch",
			"expected_count": hashes_a.size(),
			"actual_count": hashes_b.size(),
			"final_expected": int(res_a.get("final_hash", 0)),
			"final_actual": int(res_b.get("final_hash", 0)),
		}
		_save_ci_replay_pair_artifact(test_name, path_a, path_b, summary)
		_fail("%s (hash count mismatch)" % test_name)
		return

	for i in range(hashes_a.size()):
		if int(hashes_a[i]) != int(hashes_b[i]):
			var summary2 := {
				"error": "hash_mismatch",
				"tick": i,
				"expected": int(hashes_a[i]),
				"actual": int(hashes_b[i]),
				"final_expected": int(res_a.get("final_hash", 0)),
				"final_actual": int(res_b.get("final_hash", 0)),
			}
			_save_ci_replay_pair_artifact(test_name, path_a, path_b, summary2)
			_fail("%s (hash mismatch at t=%d)" % [test_name, i])
			return

	# Also assert that the recorded replays verify cleanly (best-effort artifacts on failure).
	var verifier := DriftReplayVerifier.new()
	var wplay_a := DriftWorld.new()
	var verify_a: Dictionary = verifier.verify(path_a, wplay_a, setup_world, Callable(), {
		"enable_artifacts": true,
		"artifact_root": "res://.ci_artifacts/weaponized_replay_verify",
		"artifact_name": test_name + "_verify_A",
	})
	if not bool(verify_a.get("ok", false)):
		_fail("%s (verify A failed: %s)" % [test_name, str(verify_a.get("error", "unknown"))])
		return

	var wplay_b := DriftWorld.new()
	var verify_b: Dictionary = verifier.verify(path_b, wplay_b, setup_world, Callable(), {
		"enable_artifacts": true,
		"artifact_root": "res://.ci_artifacts/weaponized_replay_verify",
		"artifact_name": test_name + "_verify_B",
	})
	if not bool(verify_b.get("ok", false)):
		_fail("%s (verify B failed: %s)" % [test_name, str(verify_b.get("error", "unknown"))])
		return

	# Cleanup.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path_a))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path_b))
	_pass("weaponized_deterministic_replay_scripted_inputs")


func _setup_world_for_weaponized_deterministic_replay(w: DriftWorld, _header: Dictionary) -> void:
	# Minimal deterministic world config.
	w.set_solid_tiles([])
	w.set_door_tiles([])
	w.add_boundary_tiles(64, 64)
	w.set_map_dimensions(64, 64)
	w.set_prize_rng_seed(111)
	w.set_spawn_rng_seed(222)

	# Make firing deterministic and likely.
	w.bullet_energy_cost = 0
	w.bullet_cooldown_ticks = 1
	w.bullet_speed = 900.0
	w.bullet_lifetime_ticks = 60
	w.bullet_damage = 1
	w.bullet_knock_impulse = 0.0

	# Two ships at deterministic positions.
	w.add_ship(1, Vector2(256, 256))
	w.add_ship(2, Vector2(320, 256))
	for sid in [1, 2]:
		if w.ships.has(sid):
			var s: DriftTypes.DriftShipState = w.ships[sid]
			s.energy_max = 100
			s.energy_current = 100
			s.energy_recharge_rate_per_sec = 0
			s.energy_recharge_delay_ticks = 0
			s.energy_recharge_wait_ticks = 0
			s.energy_recharge_fp_accum = 0
			s.energy_drain_fp_accum = 0
			s.energy = s.energy_current
			s.next_bullet_tick = 0


func _record_scripted_replay(path: String, ticks: int, setup_world: Callable) -> Dictionary:
	var w := DriftWorld.new()
	setup_world.call(w, {})

	var recorder := DriftReplayRecorder.new()
	var header: Dictionary = {
		"format": "driftline.replay",
		"schema_version": 1,
		"type": "header",
		"version": 1,
		"tick_rate": int(DriftConstants.TICK_RATE),
		"ruleset_hash": 0,
		"map_id": "smoke_weaponized",
		"map_hash": 0,
		"notes": "smoke: weaponized deterministic replay",
	}
	recorder.start(path, header)
	if not bool(recorder.enabled):
		return {"ok": false, "error": "failed to open recorder"}

	var hashes: Array = []
	for t in range(int(ticks)):
		var inputs_by_id: Dictionary = ScriptedReplayInputs.inputs_for_tick(int(t))
		var cmds: Dictionary = {}
		# Keep mapping aligned with DriftReplayVerifier._cmd_from_drift_input.
		for sid in inputs_by_id.keys():
			var di: DriftInput = inputs_by_id.get(int(sid))
			cmds[int(sid)] = DriftTypes.DriftInputCmd.new(
				float(di.thrust),
				float(di.turn),
				bool(di.fire),
				bool(di.bomb),
				bool(di.afterburner),
				bool(di.ability1),
				false,
				false,
				false
			)
		var t_before: int = int(w.tick)
		w.step_tick(cmds, false, 0)
		var h: int = int(w.compute_world_hash())
		hashes.append(h)
		recorder.record_tick(t_before, inputs_by_id, h)

	recorder.stop()
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "replay file missing"}
	return {"ok": true, "hashes": hashes, "final_hash": int(hashes[-1]) if hashes.size() > 0 else int(w.compute_world_hash())}


func _save_ci_replay_pair_artifact(context: String, replay_path_a: String, replay_path_b: String, summary: Dictionary) -> String:
	# Best-effort artifact bundle containing both replays + summary.
	var ts: String = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var safe: String = _sanitize_filename(context)
	var folder_res: String = "res://.ci_artifacts/" + safe + "/" + ts
	var folder_abs: String = ProjectSettings.globalize_path(folder_res)

	if DirAccess.make_dir_recursive_absolute(folder_abs) != OK:
		print("[SMOKE] WARN failed to create artifact dir: ", folder_abs)
		return ""

	_copy_file_best_effort(replay_path_a, folder_abs + "/replay_a.jsonl")
	_copy_file_best_effort(replay_path_b, folder_abs + "/replay_b.jsonl")

	var fs := FileAccess.open(folder_abs + "/summary.json", FileAccess.WRITE)
	if fs != null:
		fs.store_string(JSON.stringify(summary, "\t"))
	else:
		print("[SMOKE] WARN failed to write summary.json")

	print("[SMOKE] wrote artifact: ", folder_abs)
	return folder_abs


func _copy_file_best_effort(src: String, dst_abs: String) -> void:
	if not FileAccess.file_exists(src):
		print("[SMOKE] WARN missing file to copy: ", src)
		return
	var fin := FileAccess.open(src, FileAccess.READ)
	if fin == null:
		print("[SMOKE] WARN failed to open file to copy: ", src)
		return
	var fout := FileAccess.open(dst_abs, FileAccess.WRITE)
	if fout == null:
		print("[SMOKE] WARN failed to open destination: ", dst_abs)
		return
	fout.store_buffer(fin.get_buffer(int(fin.get_length())))


func _test_bugreport_writes_artifact() -> void:
	_ran += 1
	# Headless/dev validation: create a bugreport artifact and ensure the
	# file structure exists. Zip is best-effort and not required here.
	var world := DriftWorld.new()
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)
	world.add_ship(1, Vector2(64, 64))

	var records: Array = [
		{"t": 0, "inputs": [[1, {"thrust": 0, "turn": 0, "fire": false}]]},
		{"t": 1, "inputs": [[1, {"thrust": 1, "turn": 0, "fire": true}]]},
	]
	var meta: Dictionary = ReplayMeta.build_replay_meta(world, {"map_path": "res://maps/default.json", "ruleset_hash": 0})
	meta["bugreport_trigger"] = "smoke_test"
	var mismatch: Dictionary = {"reason": "smoke_bugreport", "detail": {"note": "test"}}

	var res: Dictionary = BugReportWriter.save_bug_report("smoke_bugreport", meta, records, mismatch, {
		"root": "res://.ci_artifacts/bugreports_smoke",
		"fallback_root": "user://.ci_artifacts/bugreports_smoke",
		"zip": false,
	})
	if not bool(res.get("ok", false)):
		_fail("bugreport_writes_artifact (save failed: %s)" % String(res.get("error", "unknown")))
		return
	var folder: String = String(res.get("folder", ""))
	if folder == "":
		_fail("bugreport_writes_artifact (missing folder)")
		return
	var abs: String = ProjectSettings.globalize_path(folder)
	var ok_meta: bool = FileAccess.file_exists(abs + "/meta.json")
	var ok_mismatch: bool = FileAccess.file_exists(abs + "/mismatch.json")
	var ok_replay: bool = FileAccess.file_exists(abs + "/replay.jsonl")
	if not ok_meta or not ok_mismatch or not ok_replay:
		_fail("bugreport_writes_artifact (missing files)")
		return
	_pass("bugreport_writes_artifact")


func _test_energy_spend_and_recharge() -> void:
	_ran += 1
	# Minimal energy semantics:
	# - firing spends energy (all-or-nothing)
	# - energy never goes negative
	# - recharge only starts after delay
	var world := DriftWorld.new()
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(32, 32)
	world.set_map_dimensions(32, 32)

	world.bullet_energy_cost = 20
	world.bullet_cooldown_ticks = 0

	world.add_ship(1, Vector2(128, 128))
	if not world.ships.has(1):
		_fail("energy_spend_and_recharge (ship missing)")
		return
	var s: DriftTypes.DriftShipState = world.ships[1]
	# Deterministic per-ship energy tuning.
	s.energy_max = 100
	s.energy_current = 40
	s.energy_recharge_rate_per_sec = 60 # 1 point/tick at 60hz
	s.energy_recharge_delay_ticks = 10
	# Avoid pre-fire recharge during this tick (energy stepping runs before firing).
	s.energy_recharge_wait_ticks = 1
	s.energy_recharge_fp_accum = 0
	s.energy_drain_fp_accum = 0
	s.energy = s.energy_current
	s.next_bullet_tick = 0

	var fire := DriftTypes.DriftInputCmd.new(0.0, 0.0, true, false, false)
	world.step_tick({1: fire}, false, 0)
	if int(s.energy_current) != 20:
		_fail("energy_spend_and_recharge (expected energy 20 after fire, got %d)" % [int(s.energy_current)])
		return
	if int(s.energy_recharge_wait_ticks) != 10:
		_fail("energy_spend_and_recharge (expected recharge_wait 10 after spend, got %d)" % [int(s.energy_recharge_wait_ticks)])
		return

	# No recharge before delay expires.
	var idle := DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false)
	for _i in range(9):
		world.step_tick({1: idle}, false, 0)
		if int(s.energy_current) != 20:
			_fail("energy_spend_and_recharge (recharged early)")
			return

	# Recharge begins after delay reaches 0.
	world.step_tick({1: idle}, false, 0)
	# Next tick should recharge at least 1 point at 60/sec.
	world.step_tick({1: idle}, false, 0)
	if int(s.energy_current) <= 20:
		_fail("energy_spend_and_recharge (expected recharge after delay, got %d)" % [int(s.energy_current)])
		return

	# All-or-nothing spend: cannot go negative.
	s.energy_current = 10
	s.energy = 10
	# Prevent incidental recharge during the insufficient-spend tick.
	s.energy_recharge_wait_ticks = 999
	world.step_tick({1: fire}, false, 0)
	if int(s.energy_current) != 10:
		_fail("energy_spend_and_recharge (energy changed on insufficient spend)")
		return
	if int(s.energy_current) < 0:
		_fail("energy_spend_and_recharge (energy went negative)")
		return

	_pass("energy_spend_and_recharge")


func _setup_world_for_replay_bullets_test(world: DriftWorld, _header: Dictionary) -> void:
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(64, 64)
	world.set_map_dimensions(64, 64)
	world.set_prize_rng_seed(111)
	world.set_spawn_rng_seed(222)
	# Make bullet interactions very likely.
	world.bullet_energy_cost = 0
	world.bullet_cooldown_ticks = 1
	world.bullet_speed = 2000.0
	world.bullet_lifetime_ticks = 60
	world.bullet_damage = 1
	world.bullet_knock_impulse = 0.0
	world.add_ship(1, Vector2(256, 256))
	world.add_ship(2, Vector2(320, 256))
	# Ensure deterministic energy config for both ships.
	for sid in [1, 2]:
		if world.ships.has(sid):
			var s: DriftTypes.DriftShipState = world.ships[sid]
			s.energy_max = 100
			s.energy_current = 100
			s.energy_recharge_rate_per_sec = 0
			s.energy_recharge_delay_ticks = 0
			s.energy_recharge_wait_ticks = 0
			s.energy = s.energy_current


func _test_deterministic_replay_bullets() -> void:
	_ran += 1
	# Record a short replay with firing and verify hashes match when replayed.
	var path := "user://replays/test_replay_bullets.jsonl"
	var setup_world := Callable(self, "_setup_world_for_replay_bullets_test")

	# Best-effort cleanup from previous runs.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var wrec := DriftWorld.new()
	setup_world.call(wrec, {})

	var recorder := DriftReplayRecorder.new()
	var header: Dictionary = {
		"format": "driftline.replay",
		"schema_version": 1,
		"type": "header",
		"version": 1,
		"tick_rate": int(DriftConstants.TICK_RATE),
		"ruleset_hash": 0,
		"map_id": "test",
		"map_hash": 0,
	}
	recorder.start(path, header)
	if not bool(recorder.enabled):
		_fail("deterministic_replay_bullets (failed to open recorder)")
		return

	var ticks: int = 120
	for t in range(ticks):
		# Ship 1 fires a burst; ship 2 stays idle.
		var fire_now: bool = t < 40
		var di1 := DriftInput.new(0, 0, fire_now, false, false, false, false)
		var di2 := DriftInput.new(0, 0, false, false, false, false, false)
		var cmd1 := DriftTypes.DriftInputCmd.new(float(di1.thrust), float(di1.turn), bool(di1.fire), bool(di1.bomb), bool(di1.afterburner), false, false, false, false, bool(di1.mine))
		var cmd2 := DriftTypes.DriftInputCmd.new(float(di2.thrust), float(di2.turn), bool(di2.fire), bool(di2.bomb), bool(di2.afterburner), false, false, false, false, bool(di2.mine))
		var t_before: int = int(wrec.tick)
		wrec.step_tick({1: cmd1, 2: cmd2}, false, 0)
		recorder.record_tick(t_before, {1: di1, 2: di2}, int(wrec.compute_world_hash()))

	recorder.stop()
	if not FileAccess.file_exists(path):
		_fail("deterministic_replay_bullets (file missing)")
		return

	# Replay + verify hashes.
	var wplay := DriftWorld.new()
	var verifier := DriftReplayVerifier.new()
	var res: Dictionary = verifier.verify(path, wplay, setup_world)
	if not bool(res.get("ok", false)):
		_fail("deterministic_replay_bullets (verify failed: %s)" % str(res.get("error", "unknown")))
		return

	# Cleanup.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_pass("deterministic_replay_bullets")


func _test_user_settings_roundtrip() -> void:
	_ran += 1
	# Client-only persistent settings must load/save robustly.
	# This test avoids touching shared sim and restores any prior file contents.
	var path: String = SettingsManager.SETTINGS_PATH
	var had_file: bool = FileAccess.file_exists(path)
	var backup_text: String = ""
	if had_file:
		var f0 := FileAccess.open(path, FileAccess.READ)
		if f0 != null:
			backup_text = f0.get_as_text()

	# Write settings.
	var mgr := SettingsManager.new()
	mgr.set_value("format", String(SettingsManager.SETTINGS_FORMAT))
	mgr.set_value("schema_version", int(SettingsManager.SETTINGS_SCHEMA_VERSION))
	mgr.set_value("audio.master_db", -6.0)
	mgr.set_value("audio.sfx_db", -3.0)
	mgr.set_value("audio.music_db", -12.0)
	mgr.set_value("audio.ui_db", -9.0)
	# Minimal keybind payload.
	mgr.set_value(
		"controls.bindings",
		{
			"drift_thrust_forward": [
				{
					"type": "key",
					"device": -1,
					"keycode": 0,
					"physical_keycode": 87,
					"shift": false,
					"ctrl": false,
					"alt": false,
					"meta": false,
				}
			]
		}
	)
	mgr.save_settings()
	# Not in the scene tree; free explicitly to avoid leak warnings on shutdown.
	mgr.free()

	# Read back.
	var mgr2 := SettingsManager.new()
	mgr2.load_settings()
	if absf(float(mgr2.get_value("audio.master_db", 0.0)) - (-6.0)) > 0.0001:
		_fail("user_settings_roundtrip (audio.master_db mismatch)")
		return
	if absf(float(mgr2.get_value("audio.sfx_db", 0.0)) - (-3.0)) > 0.0001:
		_fail("user_settings_roundtrip (audio.sfx_db mismatch)")
		return
	if absf(float(mgr2.get_value("audio.music_db", 0.0)) - (-12.0)) > 0.0001:
		_fail("user_settings_roundtrip (audio.music_db mismatch)")
		return
	if absf(float(mgr2.get_value("audio.ui_db", 0.0)) - (-9.0)) > 0.0001:
		_fail("user_settings_roundtrip (audio.ui_db mismatch)")
		return
	var bindings_any: Variant = mgr2.get_value("controls.bindings", {})
	if typeof(bindings_any) != TYPE_DICTIONARY or not Dictionary(bindings_any).has("drift_thrust_forward"):
		_fail("user_settings_roundtrip (missing controls.bindings)")
		return
	var evs_any: Variant = Dictionary(bindings_any).get("drift_thrust_forward", [])
	if typeof(evs_any) != TYPE_ARRAY:
		_fail("user_settings_roundtrip (keybinds not array)")
		return
	var evs: Array = evs_any
	if evs.size() != 1 or typeof(evs[0]) != TYPE_DICTIONARY:
		_fail("user_settings_roundtrip (keybind event missing)")
		return
	var ev0: Dictionary = evs[0]
	if String(ev0.get("type", "")) != "key" or int(ev0.get("physical_keycode", 0)) != 87:
		_fail("user_settings_roundtrip (keybind event mismatch)")
		mgr2.free()
		return
	# Not in the scene tree; free explicitly to avoid leak warnings on shutdown.
	mgr2.free()

	# Restore previous file.
	if had_file:
		var f1 := FileAccess.open(path, FileAccess.WRITE)
		if f1 != null:
			f1.store_string(backup_text)
	else:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	_pass("user_settings_roundtrip")


func _test_drift_input_roundtrip() -> void:
	_ran += 1
	# Deterministic input object must round-trip via primitives-only Dictionary.
	var a := DriftInput.new(
		1,  # thrust
		-1, # turn
		true,  # fire
		false, # bomb
		false, # mine
		true,  # afterburner
		false  # ability1
	)
	var d := a.to_dict()
	if typeof(d) != TYPE_DICTIONARY:
		_fail("drift_input_roundtrip (to_dict not a Dictionary)")
		return
	var b = DriftInput.from_dict(d)
	if b == null:
		_fail("drift_input_roundtrip (from_dict returned null)")
		return
	if not a.equals(b):
		_fail("drift_input_roundtrip (round-trip mismatch)")
		return
	var c = a.clone()
	if c == null or not a.equals(c):
		_fail("drift_input_roundtrip (clone mismatch)")
		return
	_pass("drift_input_roundtrip")


func _test_tick_increments_at_end() -> void:
	_ran += 1
	# Tick contract (Option A): DriftWorld.step_tick() simulates tick t and advances
	# world.tick to t+1 at the end of the call.
	var world = DriftWorld.new()
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)

	var start_tick: int = int(world.tick)
	const N: int = 10
	for _i in range(N):
		var snap: DriftTypes.DriftWorldSnapshot = world.step_tick({}, false, 0)
		if snap == null:
			_fail("tick_increments_at_end (snapshot null)")
			return
		if int(snap.tick) != int(world.tick):
			_fail("tick_increments_at_end (snapshot.tick != world.tick)")
			return

	if int(world.tick) != (start_tick + N):
		_fail("tick_increments_at_end (expected tick=%d got %d)" % [start_tick + N, int(world.tick)])
		return

	_pass("tick_increments_at_end")


func _test_ship_sprite_atlas_mapping() -> void:
	_ran += 1
	# Validate strict spritesheet mapping math.
	# - 4 rows per ship, 10 cols per row
	# - sheet_row = ship_index*4 + dir_row
	# - dir_row/col derived from global frame 0..39

	var ship_index := 3
	var heading_deg := 0.0
	var coords := DriftShipAtlas.ship_heading_to_sheet_coords(ship_index, heading_deg)
	# With the sheet-to-sim alignment offset, heading 0 maps to the next quadrant row.
	if coords != Vector2i(0, ship_index * 4 + 1):
		_fail("ship_atlas (expected heading 0 => col0,row%d got %s)" % [ship_index * 4 + 1, str(coords)])
		return

	# A half-turn should land in dir_row=2, col=0.
	var coords2 := DriftShipAtlas.ship_heading_to_sheet_coords(ship_index, 180.0)
	if coords2.x != 0 or coords2.y != (ship_index * 4 + 3):
		_fail("ship_atlas (expected heading 180 => col0,row%d got %s)" % [ship_index * 4 + 3, str(coords2)])
		return

	# Verify ship block separation.
	var ship_index_b := 4
	var coords3 := DriftShipAtlas.ship_heading_to_sheet_coords(ship_index_b, 0.0)
	if coords3.y != ship_index_b * 4 + 1:
		_fail("ship_atlas (expected ship %d row %d got %d)" % [ship_index_b, ship_index_b * 4 + 1, coords3.y])
		return

	_pass("ship_sprite_atlas_mapping")


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

	# Create an uneven-but-allowed distribution: team 1 has 2 ships, team 2 has 1 ship.
	world.add_ship(1, Vector2(64, 64))
	world.add_ship(2, Vector2(96, 64))
	world.add_ship(3, Vector2(128, 64))
	var s1: DriftTypes.DriftShipState = world.ships.get(1)
	var s2: DriftTypes.DriftShipState = world.ships.get(2)
	var s3: DriftTypes.DriftShipState = world.ships.get(3)
	if s1 == null or s2 == null or s3 == null:
		_fail("set_freq_force_even (ship missing)")
		return
	s1.freq = 1
	s2.freq = 2
	s3.freq = 1

	# Now moving ship 2 from team 2 -> team 1 would produce 3 vs 0 (variance 3), reject.
	var res: Dictionary = world.can_set_ship_freq(2, 1)
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
	# Re-baselined 2026-08-01: the classic weapon/damage rework and the move of
	# arena bounds off DriftConstants statics both change sim state legitimately.
	# Re-baselined again same day: the powerball is now gated on the map having goal
	# entities (DriftWorld.ball_enabled, off by default), so this fixture's ball no
	# longer moves or gets picked up. Intended behaviour change, not lost determinism.
	const EXPECTED := "9921ce881dd75ec9bb38f6d9bde39b77a04bb63381313fb8da11af0e61dce54b"
	if got != EXPECTED:
		_fail("determinism_checksum (got %s expected %s)" % [got, EXPECTED])
		return

	_pass("determinism_checksum_fixed_input")


func _test_world_hash_matches_across_worlds() -> void:
	_ran += 1
	# Per-tick world hash should match for identical simulations, and diverge if inputs differ.

	var a = DriftWorld.new()
	var b = DriftWorld.new()

	a.set_solid_tiles([])
	b.set_solid_tiles([])
	a.set_door_tiles([])
	b.set_door_tiles([])
	a.add_boundary_tiles(128, 128)
	b.add_boundary_tiles(128, 128)
	a.set_map_dimensions(128, 128)
	b.set_map_dimensions(128, 128)

	# Ensure RNG streams match (and are covered by the hash).
	a.set_prize_rng_seed(111)
	b.set_prize_rng_seed(111)
	a.set_spawn_rng_seed(222)
	b.set_spawn_rng_seed(222)

	a.add_ship(1, Vector2(1024, 1024))
	b.add_ship(1, Vector2(1024, 1024))

	var idle := DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false)
	var fwd := DriftTypes.DriftInputCmd.new(1.0, 0.0, false, false, false)
	var turn := DriftTypes.DriftInputCmd.new(0.0, 1.0, false, false, false)

	for t in range(60):
		var cmd = fwd if t < 30 else idle
		a.step_tick({1: cmd}, false, 0)
		b.step_tick({1: cmd}, false, 0)
		var ha: int = int(a.compute_world_hash())
		var hb: int = int(b.compute_world_hash())
		if ha != hb:
			_fail("world_hash_matches (mismatch at tick %d: %d vs %d)" % [int(a.tick), ha, hb])
			return

	# Perturb a single tick of input; hash should diverge immediately or shortly after.
	a.step_tick({1: idle}, false, 0)
	b.step_tick({1: turn}, false, 0)
	var ha2: int = int(a.compute_world_hash())
	var hb2: int = int(b.compute_world_hash())
	if ha2 == hb2:
		_fail("world_hash_matches (expected divergence after input perturbation)")
		return

	_pass("world_hash_matches_across_worlds")


func _test_deterministic_collision_order() -> void:
	_ran += 1
	# Determinism requirement:
	# - When multiple bullet hits occur in the same tick, resolution must be deterministic.
	# Priority rule: lowest bullet id first, then lowest ship id.
	# This test builds two worlds with different bullet insertion order and asserts:
	# - same ship energy/death outcome
	# - same world hash after stepping

	var world_a := DriftWorld.new()
	var world_b := DriftWorld.new()
	for w in [world_a, world_b]:
		w.set_solid_tiles([])
		w.set_door_tiles([])
		w.set_safe_zone_tiles([])
		w.add_boundary_tiles(32, 32)
		w.set_map_dimensions(32, 32)
		# Keep RNG streams aligned; hash includes RNG state.
		w.set_prize_rng_seed(111)
		w.prize_enabled = false
		w.set_spawn_rng_seed(222)
		w.bullet_damage = 50
		w.bullet_knock_impulse = 0.0
		w.bullet_radius = 2.0
		w.add_ship(1, Vector2(128, 128))
		w.add_ship(2, Vector2(160, 128))
		# Ensure bullets can damage (default friendly-fire is off; ships must be on different teams).
		var s1: DriftTypes.DriftShipState = w.ships.get(1)
		var s2: DriftTypes.DriftShipState = w.ships.get(2)
		if s1 == null or s2 == null:
			_fail("deterministic_collision_order (ship missing)")
			return
		s1.freq = 0
		s2.freq = 1
		# Make the target die from exactly one hit so order matters if non-deterministic.
		s2.energy_max = 50
		s2.energy_current = 50

	# Two bullets overlapping ship 2 in the same tick.
	var target_pos_a: Vector2 = (world_a.ships.get(2) as DriftTypes.DriftShipState).position
	var target_pos_b: Vector2 = (world_b.ships.get(2) as DriftTypes.DriftShipState).position
	var die_tick := 999999
	var b1a := DriftTypes.DriftBulletState.new(1, 1, 1, target_pos_a, Vector2.ZERO, 0, die_tick, 0)
	var b2a := DriftTypes.DriftBulletState.new(2, 1, 1, target_pos_a, Vector2.ZERO, 0, die_tick, 0)
	# Insert in ascending order for A.
	world_a.bullets[1] = b1a
	world_a.bullets[2] = b2a
	# Insert in reverse order for B.
	var b1b := DriftTypes.DriftBulletState.new(1, 1, 1, target_pos_b, Vector2.ZERO, 0, die_tick, 0)
	var b2b := DriftTypes.DriftBulletState.new(2, 1, 1, target_pos_b, Vector2.ZERO, 0, die_tick, 0)
	world_b.bullets[2] = b2b
	world_b.bullets[1] = b1b

	# Step one tick.
	world_a.step_tick({})
	world_b.step_tick({})

	var s2a: DriftTypes.DriftShipState = world_a.ships.get(2)
	var s2b: DriftTypes.DriftShipState = world_b.ships.get(2)
	if s2a == null or s2b == null:
		_fail("deterministic_collision_order (ship missing after step)")
		return
	# Both should be dead (damage-as-energy).
	if int(s2a.energy_current) != 0 or int(s2b.energy_current) != 0:
		_fail("deterministic_collision_order (expected energy 0)")
		return
	if int(s2a.dead_until_tick) <= 0 or int(s2b.dead_until_tick) <= 0:
		_fail("deterministic_collision_order (expected dead_until_tick set)")
		return
	# Deterministic ordering rule implies bullet 1 resolves first and is consumed.
	# Bullet 2 remains because collisions skip dead ships.
	if int(world_a.bullets.size()) != 1 or int(world_b.bullets.size()) != 1:
		_fail("deterministic_collision_order (expected exactly one bullet remaining)")
		return
	if world_a.bullets.has(1) or world_b.bullets.has(1):
		_fail("deterministic_collision_order (expected bullet 1 consumed)")
		return
	if not world_a.bullets.has(2) or not world_b.bullets.has(2):
		_fail("deterministic_collision_order (expected bullet 2 remaining)")
		return

	var ha: int = int(world_a.compute_world_hash())
	var hb: int = int(world_b.compute_world_hash())
	if ha != hb:
		print("[SMOKE_DIAG] deterministic_collision_order hash mismatch ha=", ha, " hb=", hb)
		var da: DriftTypes.DriftShipState = world_a.ships.get(2)
		var db: DriftTypes.DriftShipState = world_b.ships.get(2)
		if da != null and db != null:
			print("[SMOKE_DIAG] ship2 a: e_wait=", int(da.energy_recharge_wait_ticks), " lecr=", int(da.last_energy_change_reason), " lecs=", int(da.last_energy_change_source_id), " lect=", int(da.last_energy_change_tick), " racc=", int(da.energy_recharge_fp_accum), " dacc=", int(da.energy_drain_fp_accum))
			print("[SMOKE_DIAG] ship2 b: e_wait=", int(db.energy_recharge_wait_ticks), " lecr=", int(db.last_energy_change_reason), " lecs=", int(db.last_energy_change_source_id), " lect=", int(db.last_energy_change_tick), " racc=", int(db.energy_recharge_fp_accum), " dacc=", int(db.energy_drain_fp_accum))
		print("[SMOKE_DIAG] next_bullet_id a=", int(world_a.next_bullet_id), " b=", int(world_b.next_bullet_id))
		print("[SMOKE_DIAG] spawn_rng a(seed/state)=", int(world_a._spawn_rng.seed), "/", int(world_a._spawn_rng.state), " b=", int(world_b._spawn_rng.seed), "/", int(world_b._spawn_rng.state))
		print("[SMOKE_DIAG] prize_rng a(seed/state)=", int(world_a._prize_rng.seed), "/", int(world_a._prize_rng.state), " b=", int(world_b._prize_rng.seed), "/", int(world_b._prize_rng.state))
		DriftReplayVerifier._print_world_dump_small(world_a)
		DriftReplayVerifier._print_world_dump_small(world_b)
		_fail("deterministic_collision_order (world hash mismatch)")
		return

	_pass("deterministic_collision_order")


func _test_replay_recorder_writes_jsonl() -> void:
	_ran += 1
	var path := "user://replays/test_replay.jsonl"

	# Best-effort cleanup from previous runs.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var world = DriftWorld.new()
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(64, 64)
	world.set_map_dimensions(64, 64)
	world.set_prize_rng_seed(111)
	world.set_spawn_rng_seed(222)
	world.add_ship(1, Vector2(256, 256))

	var recorder = DriftReplayRecorder.new()
	var header: Dictionary = {
		"format": "driftline.replay",
		"schema_version": 1,
		"type": "header",
		"version": 1,
		"tick_rate": int(DriftConstants.TICK_RATE),
		"ruleset_hash": 0,
		"map_id": "test",
		"map_hash": 0,
	}
	recorder.start(path, header)
	if not bool(recorder.enabled):
		_fail("replay_recorder_jsonl (failed to open)")
		return

	var ticks: int = 120
	var idle_cmd := DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false)
	for t in range(ticks):
		# Deterministic input payload for recorder (DriftInput), but sim uses DriftInputCmd.
		var di := DriftInput.new(1 if (t % 10) < 5 else 0, 0, (t % 15) == 0, false, false, false, false)
		if t % 5 == 0:
			di = DriftInput.new(0, 0, false, false, false, false, false)
		var cmd := DriftTypes.DriftInputCmd.new(float(di.thrust), float(di.turn), bool(di.fire), bool(di.bomb), bool(di.afterburner), false, false, false, false, bool(di.mine))
		var t_before: int = int(world.tick)
		world.step_tick({1: cmd}, false, 0)
		recorder.record_tick(t_before, {1: di}, int(world.compute_world_hash()))

	recorder.stop()
	if not FileAccess.file_exists(path):
		_fail("replay_recorder_jsonl (file missing)")
		return

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("replay_recorder_jsonl (cannot read)")
		return

	var header_line: String = f.get_line()
	var header_obj = JSON.parse_string(header_line)
	if typeof(header_obj) != TYPE_DICTIONARY:
		_fail("replay_recorder_jsonl (header not JSON dict)")
		return
	if String((header_obj as Dictionary).get("format", "")) != "driftline.replay":
		_fail("replay_recorder_jsonl (missing/invalid format)")
		return
	if int((header_obj as Dictionary).get("schema_version", -1)) != 1:
		_fail("replay_recorder_jsonl (missing/invalid schema_version)")
		return
	if String((header_obj as Dictionary).get("type", "")) != "header":
		_fail("replay_recorder_jsonl (header type mismatch)")
		return

	var tick_lines: int = 0
	while not f.eof_reached():
		var line: String = f.get_line()
		if line == "":
			continue
		var obj = JSON.parse_string(line)
		if typeof(obj) != TYPE_DICTIONARY:
			_fail("replay_recorder_jsonl (tick line not JSON dict)")
			return
		if String((obj as Dictionary).get("type", "")) == "tick":
			tick_lines += 1
	if tick_lines != ticks:
		_fail("replay_recorder_jsonl (expected %d tick lines got %d)" % [ticks, tick_lines])
		return

	# Cleanup.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_pass("replay_recorder_writes_jsonl")


func _test_replay_verifier_replays_and_hashes() -> void:
	_ran += 1
	var path := "user://replays/test_replay_verify.jsonl"
	var setup_world := Callable(self, "_setup_world_for_replay_verify_test")

	# Best-effort cleanup from previous runs.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# Record a deterministic replay.
	var wrec := DriftWorld.new()
	setup_world.call(wrec, {})
	var recorder := DriftReplayRecorder.new()
	var header: Dictionary = {
		"format": "driftline.replay",
		"schema_version": 1,
		"type": "header",
		"version": 1,
		"tick_rate": int(DriftConstants.TICK_RATE),
		"ruleset_hash": 0,
		"map_id": "test",
		"map_hash": 0,
	}
	recorder.start(path, header)
	if not bool(recorder.enabled):
		_fail("replay_verify (failed to open recorder)")
		return

	var ticks: int = 120
	for t in range(ticks):
		var di := DriftInput.new(1 if (t % 10) < 5 else 0, 0, (t % 15) == 0, false, false, false, false)
		if t % 5 == 0:
			di = DriftInput.new(0, 0, false, false, false, false, false)
		var cmd := DriftTypes.DriftInputCmd.new(float(di.thrust), float(di.turn), bool(di.fire), bool(di.bomb), bool(di.afterburner), false, false, false, false, bool(di.mine))
		var t_before: int = int(wrec.tick)
		wrec.step_tick({1: cmd}, false, 0)
		recorder.record_tick(t_before, {1: di}, int(wrec.compute_world_hash()))

	recorder.stop()
	if not FileAccess.file_exists(path):
		_fail("replay_verify (file missing)")
		return

	# Replay + verify hashes.
	var wplay := DriftWorld.new()
	var verifier := DriftReplayVerifier.new()
	var res: Dictionary = verifier.verify(path, wplay, setup_world)
	if not bool(res.get("ok", false)):
		_fail("replay_verify (failed: %s)" % str(res.get("error", "unknown")))
		return

	# Cleanup.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_pass("replay_verifier_replays_and_hashes")


func _test_replay_verifier_detects_mismatch() -> void:
	_ran += 1
	var path := "user://replays/test_replay_verify_bad.jsonl"
	var path_bad := "user://replays/test_replay_verify_bad_corrupt.jsonl"
	var setup_world := Callable(self, "_setup_world_for_replay_verify_test")

	# Best-effort cleanup from previous runs.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if FileAccess.file_exists(path_bad):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_bad))

	# Record a deterministic replay.
	var wrec := DriftWorld.new()
	setup_world.call(wrec, {})
	var recorder := DriftReplayRecorder.new()
	var header: Dictionary = {
		"format": "driftline.replay",
		"schema_version": 1,
		"type": "header",
		"version": 1,
		"tick_rate": int(DriftConstants.TICK_RATE),
		"ruleset_hash": 0,
		"map_id": "test",
		"map_hash": 0,
	}
	recorder.start(path, header)
	if not bool(recorder.enabled):
		_fail("replay_verify_negative (failed to open recorder)")
		return

	var ticks: int = 30
	for t in range(ticks):
		var di := DriftInput.new(1 if (t % 10) < 5 else 0, 0, (t % 15) == 0, false, false, false, false)
		if t % 5 == 0:
			di = DriftInput.new(0, 0, false, false, false, false, false)
		var cmd := DriftTypes.DriftInputCmd.new(float(di.thrust), float(di.turn), bool(di.fire), bool(di.bomb), bool(di.afterburner), false, false, false, false, bool(di.mine))
		var t_before: int = int(wrec.tick)
		wrec.step_tick({1: cmd}, false, 0)
		recorder.record_tick(t_before, {1: di}, int(wrec.compute_world_hash()))

	recorder.stop()
	if not FileAccess.file_exists(path):
		_fail("replay_verify_negative (file missing)")
		return

	# Create a corrupted replay with a modified hash on the first tick line.
	var ok_write: bool = _write_replay_with_corrupted_first_tick_hash(path, path_bad)
	if not ok_write:
		_fail("replay_verify_negative (failed to write corrupted replay)")
		return

	var wplay := DriftWorld.new()
	var verifier := DriftReplayVerifier.new()
	var res: Dictionary = verifier.verify(path_bad, wplay, setup_world)
	if bool(res.get("ok", false)):
		_fail("replay_verify_negative (expected failure, got ok)")
		return
	if String(res.get("error", "")) == "":
		_fail("replay_verify_negative (missing error)")
		return

	# Cleanup.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path_bad))
	_pass("replay_verifier_detects_mismatch")


func _test_replay_deterministic_hash_stable() -> void:
	_ran += 1
	# Ensure replay verification is deterministic within a single process.
	# Default is short to keep headless CI under ~2-3 seconds.
	_run_replay_hash_stable_test(180, "replay_hash_stable")


func _test_replay_deterministic_hash_stable_soak() -> void:
	_ran += 1
	# Longer soak variant (opt-in only). Useful when chasing rare nondeterminism.
	_run_replay_hash_stable_test(600, "replay_hash_stable_soak")


func _run_replay_hash_stable_test(ticks: int, label: String) -> void:
	var path := "user://replays/test_%s.jsonl" % _sanitize_filename(label)
	var setup_world := Callable(self, "_setup_world_for_replay_hash_stable_test")

	# Best-effort cleanup from previous runs.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# Record a deterministic replay (2 ships).
	var wrec := DriftWorld.new()
	setup_world.call(wrec, {})
	var recorder := DriftReplayRecorder.new()
	var header: Dictionary = {
		"format": "driftline.replay",
		"schema_version": 1,
		"type": "header",
		"version": 1,
		"tick_rate": int(DriftConstants.TICK_RATE),
		"ruleset_hash": 0,
		"map_id": "test",
		"map_hash": 0,
		"notes": "smoke: %s" % label,
	}
	recorder.start(path, header)
	if not bool(recorder.enabled):
		_fail("%s (failed to open recorder)" % label)
		return

	for t in range(int(ticks)):
		# Scripted deterministic inputs (DriftInput) for 2 ships.
		var di1 := DriftInput.new(
			1 if (t % 60) < 30 else 0,
			-1 if (t % 40) < 20 else 1,
			(t % 15) == 0,
			(t % 90) == 10,
			false,
			(t % 20) < 5,
			(t % 120) == 7
		)
		var di2 := DriftInput.new(
			1 if (t % 50) < 25 else 0,
			1 if (t % 30) < 15 else -1,
			(t % 17) == 0,
			(t % 80) == 3,
			false,
			(t % 25) < 8,
			(t % 100) == 9
		)

		# Sim uses DriftInputCmd; keep mapping aligned with DriftReplayVerifier._cmd_from_drift_input.
		var cmd1 := DriftTypes.DriftInputCmd.new(
			float(di1.thrust),
			float(di1.turn),
			bool(di1.fire),
			bool(di1.bomb),
			bool(di1.afterburner),
			bool(di1.ability1),
			false,
			false,
			false,
			bool(di1.mine)
		)
		var cmd2 := DriftTypes.DriftInputCmd.new(
			float(di2.thrust),
			float(di2.turn),
			bool(di2.fire),
			bool(di2.bomb),
			bool(di2.afterburner),
			bool(di2.ability1),
			false,
			false,
			false,
			bool(di2.mine)
		)
		var t_before: int = int(wrec.tick)
		wrec.step_tick({1: cmd1, 2: cmd2}, false, 0)
		recorder.record_tick(t_before, {1: di1, 2: di2}, int(wrec.compute_world_hash()))

	recorder.stop()
	if not FileAccess.file_exists(path):
		_fail("%s (file missing)" % label)
		return

	# Verify twice in-process into fresh worlds.
	var verifier := DriftReplayVerifier.new()

	var wplay_a := DriftWorld.new()
	var res_a: Dictionary = verifier.verify(path, wplay_a, setup_world)
	if not bool(res_a.get("ok", false)):
		_print_replay_verify_failure("%s (verify A)" % label, res_a, path)
		var artifact_a: String = _save_ci_replay_artifact(label + "_verify_A", path, res_a)
		if artifact_a != "":
			print("[SMOKE] bugreport_replay_path=", artifact_a)
		_fail("%s (verify A failed: %s)" % [label, str(res_a.get("error", "unknown"))])
		return
	var hash_a: int = int(wplay_a.compute_world_hash())

	var wplay_b := DriftWorld.new()
	var res_b: Dictionary = verifier.verify(path, wplay_b, setup_world)
	if not bool(res_b.get("ok", false)):
		_print_replay_verify_failure("%s (verify B)" % label, res_b, path)
		var artifact_b: String = _save_ci_replay_artifact(label + "_verify_B", path, res_b)
		if artifact_b != "":
			print("[SMOKE] bugreport_replay_path=", artifact_b)
		_fail("%s (verify B failed: %s)" % [label, str(res_b.get("error", "unknown"))])
		return
	var hash_b: int = int(wplay_b.compute_world_hash())

	if hash_a != hash_b:
		print("[SMOKE] %s final_hash_mismatch expected=", label, " got=", hash_b, " tick=final")
		var res_final := {"ok": false, "error": "final hash mismatch", "mismatch": {"expected": hash_a, "actual": hash_b}}
		var artifact_f: String = _save_ci_replay_artifact(label + "_final_hash_mismatch", path, res_final)
		if artifact_f != "":
			print("[SMOKE] bugreport_replay_path=", artifact_f)
		_fail("%s (final hash mismatch: %d vs %d)" % [label, hash_a, hash_b])
		return

	# Cleanup.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_pass("replay_deterministic_hash_stable" if label == "replay_hash_stable" else label)


func _print_replay_verify_failure(context: String, res: Dictionary, replay_path: String) -> void:
	print("[SMOKE] REPLAY_VERIFY_FAIL ", context, " path=", replay_path)
	print("[SMOKE]   error=", str(res.get("error", "unknown")))
	var mismatch_any: Variant = res.get("mismatch", null)
	if typeof(mismatch_any) == TYPE_DICTIONARY:
		var m: Dictionary = mismatch_any
		var tick: Variant = "?"
		if m.has("t"):
			tick = m.get("t")
		elif m.has("at"):
			tick = m.get("at")
		if tick != "?":
			print("[SMOKE]   tick=", tick)
		if m.has("expected") or m.has("actual"):
			print("[SMOKE]   expected=", m.get("expected", "?"), " got=", m.get("actual", "?"))
		print("[SMOKE]   mismatch=", JSON.stringify(m))


func _save_ci_replay_artifact(context: String, replay_path: String, res: Dictionary) -> String:
	# Best-effort: write a replay+mismatch bundle into the CI workspace so the
	# logs can point at a stable path (res:// is the repo checkout in CI).
	# Never fails the test if artifact writing fails.
	var ts: String = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var safe: String = _sanitize_filename(context)
	var folder_res: String = "res://.ci_artifacts/replay_failures/%s_%s" % [ts, safe]
	var folder_abs: String = ProjectSettings.globalize_path(folder_res)

	var mk_ok: bool = DirAccess.make_dir_recursive_absolute(folder_abs) == OK
	if not mk_ok:
		print("[SMOKE] WARN failed to create artifact dir: ", folder_abs)
		return ""

	# Copy replay file.
	if FileAccess.file_exists(replay_path):
		var fin := FileAccess.open(replay_path, FileAccess.READ)
		if fin != null:
			var fout := FileAccess.open(folder_abs + "/replay.jsonl", FileAccess.WRITE)
			if fout != null:
				var n: int = int(fin.get_length())
				fout.store_buffer(fin.get_buffer(n))
			else:
				print("[SMOKE] WARN failed to write replay.jsonl")
		else:
			print("[SMOKE] WARN failed to open replay for artifact copy")
	else:
		print("[SMOKE] WARN replay file missing; no artifact replay copy")

	# Write mismatch.
	var mismatch_any: Variant = res.get("mismatch", {})
	var mismatch_out: Dictionary = {
		"error": str(res.get("error", "unknown")),
		"mismatch": mismatch_any if typeof(mismatch_any) == TYPE_DICTIONARY else {},
		"replay_path": replay_path,
	}
	var fm := FileAccess.open(folder_abs + "/mismatch.json", FileAccess.WRITE)
	if fm != null:
		fm.store_string(JSON.stringify(mismatch_out, "\t"))
	else:
		print("[SMOKE] WARN failed to write mismatch.json")

	return folder_abs


func _sanitize_filename(s: String) -> String:
	var out: String = ""
	for i in range(s.length()):
		var ch: String = s[i]
		var ok: bool = (
			(ch >= "a" and ch <= "z")
			or (ch >= "A" and ch <= "Z")
			or (ch >= "0" and ch <= "9")
			or ch == "_"
			or ch == "-"
			or ch == "."
		)
		out += ch if ok else "_"
	if out == "":
		return "artifact"
	return out


func _write_replay_with_corrupted_first_tick_hash(src_path: String, dst_path: String) -> bool:
	var fin := FileAccess.open(src_path, FileAccess.READ)
	if fin == null:
		return false
	var fout := FileAccess.open(dst_path, FileAccess.WRITE)
	if fout == null:
		return false

	# Copy header line.
	if fin.eof_reached():
		return false
	var header_line: String = fin.get_line()
	fout.store_line(header_line)

	var corrupted: bool = false
	while not fin.eof_reached():
		var line: String = fin.get_line()
		if line == "":
			continue
		var obj = JSON.parse_string(line)
		if typeof(obj) != TYPE_DICTIONARY:
			# Preserve as-is.
			fout.store_line(line)
			continue
		var d: Dictionary = obj
		if (not corrupted) and String(d.get("type", "")) == "tick":
			# Corrupt hash deterministically.
			d["hash"] = int(d.get("hash", 0)) + 1
			corrupted = true
			fout.store_line(JSON.stringify(d))
			continue
		fout.store_line(line)

	return corrupted


func _setup_world_for_replay_verify_test(w: DriftWorld, _header: Dictionary) -> void:
	w.set_solid_tiles([])
	w.set_door_tiles([])
	w.add_boundary_tiles(64, 64)
	w.set_map_dimensions(64, 64)
	w.set_prize_rng_seed(111)
	w.set_spawn_rng_seed(222)
	w.add_ship(1, Vector2(256, 256))


func _setup_world_for_replay_hash_stable_test(w: DriftWorld, _header: Dictionary) -> void:
	# Fixed ruleset + fixed map + fixed RNG seeds.
	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if bool(rules_res.get("ok", false)):
		w.apply_ruleset(rules_res.get("ruleset", {}))

	# Minimal fixed map contract for simulation.
	w.set_solid_tiles([])
	w.set_door_tiles([])
	w.add_boundary_tiles(64, 64)
	w.set_map_dimensions(64, 64)
	w.set_prize_rng_seed(111)
	w.set_spawn_rng_seed(222)

	# Two ships at deterministic positions.
	w.add_ship(1, Vector2(256, 256))
	w.add_ship(2, Vector2(320, 256))


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


func _test_safe_zone_blocks_actions() -> void:
	_ran += 1
	# Requirement:
	# - Ships inside safe zones cannot fire, lay mines, or use abilities.
	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("safe_zone_blocks_actions (failed to load base ruleset)")
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
	world.set_spawn_rng_seed(222)

	var ship_id := 1
	var safe_pos := Vector2(2 * 16 + 8, 2 * 16 + 8)
	world.add_ship(ship_id, safe_pos)
	var s: DriftTypes.DriftShipState = world.ships.get(ship_id)
	if s == null:
		_fail("safe_zone_blocks_actions (ship missing)")
		return

	# Prime derived in_safe_zone.
	world.step_tick({})
	if not bool(s.in_safe_zone):
		_fail("safe_zone_blocks_actions (expected in safe zone)")
		return

	var energy_before: int = int(s.energy_current)
	# Attempt: fire primary + fire secondary + ability buttons.
	var cmd := DriftTypes.DriftInputCmd.new(0.0, 0.0, true, true, true, true, true, true, true)
	world.step_tick({ship_id: cmd})

	# Fire must not spawn bullets.
	if not world.bullets.is_empty():
		_fail("safe_zone_blocks_actions (bullets spawned in safe zone)")
		return
	# Abilities must not become active.
	if bool(s.afterburner_on) or bool(s.stealth_on) or bool(s.cloak_on) or bool(s.xradar_on) or bool(s.antiwarp_on):
		_fail("safe_zone_blocks_actions (ability activated in safe zone)")
		return
	# Firing must not spend energy in safe zone.
	if int(s.energy_current) != energy_before:
		_fail("safe_zone_blocks_actions (energy changed in safe zone)")
		return

	_pass("safe_zone_blocks_actions")


func _test_safe_zone_blocks_damage() -> void:
	_ran += 1
	# Requirement:
	# - Ships inside safe zones take zero damage from all sources.
	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("safe_zone_blocks_damage (failed to load base ruleset)")
		return
	var canonical_ruleset: Dictionary = rules_res.get("ruleset", {})
	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.set_safe_zone_tiles([[2, 2, 0, 0]])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)
	world.set_spawn_rng_seed(222)

	var safe_id := 1
	var outside_id := 2
	var safe_pos := Vector2(2 * 16 + 8, 2 * 16 + 8)
	var outside_pos := Vector2(5 * 16 + 8, 5 * 16 + 8)
	world.add_ship(safe_id, safe_pos)
	world.add_ship(outside_id, outside_pos)
	var s_safe: DriftTypes.DriftShipState = world.ships.get(safe_id)
	var s_out: DriftTypes.DriftShipState = world.ships.get(outside_id)
	if s_safe == null or s_out == null:
		_fail("safe_zone_blocks_damage (ship missing)")
		return

	# Prime derived in_safe_zone.
	world.step_tick({})
	if not bool(s_safe.in_safe_zone) or bool(s_out.in_safe_zone):
		_fail("safe_zone_blocks_damage (unexpected safe zone flags)")
		return

	var e0: int = int(s_safe.energy_current)
	var ok1: bool = world.apply_damage(outside_id, safe_id, 50, "bullet")
	if ok1:
		_fail("safe_zone_blocks_damage (damage applied to ship in safe zone)")
		return
	if int(s_safe.energy_current) != e0:
		_fail("safe_zone_blocks_damage (energy changed for safe-zone target)")
		return

	# Also block damage originating from inside safe zone.
	s_safe.position = safe_pos
	s_out.position = outside_pos
	world.step_tick({})
	var e1: int = int(s_out.energy_current)
	var ok2: bool = world.apply_damage(safe_id, outside_id, 50, "bullet")
	if ok2:
		_fail("safe_zone_blocks_damage (damage applied from safe-zone attacker)")
		return
	if int(s_out.energy_current) != e1:
		_fail("safe_zone_blocks_damage (energy changed for target from safe-zone attacker)")
		return

	_pass("safe_zone_blocks_damage")


func _test_safe_zone_fire_cancels_velocity() -> void:
	_ran += 1
	# Requirement:
	# - If a ship is drifting inside a safe zone and presses fire, velocity/inertia forced to zero deterministically.
	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("safe_zone_fire_cancels_velocity (failed to load base ruleset)")
		return
	var canonical_ruleset: Dictionary = rules_res.get("ruleset", {})
	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.set_safe_zone_tiles([[2, 2, 0, 0]])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)
	world.set_spawn_rng_seed(222)

	var ship_id := 1
	var safe_pos := Vector2(2 * 16 + 8, 2 * 16 + 8)
	world.add_ship(ship_id, safe_pos)
	var s: DriftTypes.DriftShipState = world.ships.get(ship_id)
	if s == null:
		_fail("safe_zone_fire_cancels_velocity (ship missing)")
		return
	# Force drift.
	s.velocity = Vector2(120.0, 0.0)
	# Prime derived in_safe_zone.
	world.step_tick({})
	if not bool(s.in_safe_zone):
		_fail("safe_zone_fire_cancels_velocity (expected in safe zone)")
		return
	# Press fire while drifting.
	world.step_tick({ship_id: DriftTypes.DriftInputCmd.new(0.0, 0.0, true, false, false)})
	if s.velocity.length() > 0.01:
		_fail("safe_zone_fire_cancels_velocity (velocity not cancelled)")
		return
	_pass("safe_zone_fire_cancels_velocity")


func _test_spawn_prefers_safe_zone() -> void:
	_ran += 1
	# Requirement:
	# - Spawn/respawn prefer safe zones if any exist; otherwise fall back to deterministic random spawn.
	var world := DriftWorld.new()
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(32, 32)
	world.set_map_dimensions(32, 32)
	world.set_spawn_rng_seed(222)
	# Single safe tile to make the choice unambiguous.
	var safe_tile := Vector2i(10, 10)
	world.set_safe_zone_tiles([[safe_tile.x, safe_tile.y, 0, 0]])
	var p: Vector2 = world.get_spawn_point()
	var tx: int = int(floor(p.x / 16.0))
	var ty: int = int(floor(p.y / 16.0))
	if tx != safe_tile.x or ty != safe_tile.y:
		_fail("spawn_prefers_safe_zone (spawn not in safe zone tile)")
		return
	_pass("spawn_prefers_safe_zone")


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
	# Player freqs are 1..max_freq; 0 is the neutral team that flags/goals never match.
	if f1 != 1 or f2 != 2 or f3 != 1 or f4 != 2:
		_fail("team_auto_balance (expected freqs 1,2,1,2 got %d,%d,%d,%d)" % [f1, f2, f3, f4])
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


func _make_world_for_classic_ship_spec(spec: Dictionary) -> DriftWorld:
	var world := DriftWorld.new()
	# Classic ship specs are intended to drive bullet cost/cooldown/speed in this test.
	world.set_ship_spec_overrides_weapons(true)
	world.set_ship_spec(spec)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.set_safe_zone_tiles([])
	# Use a large map so high bullet speeds don't hit the boundary during this test.
	world.add_boundary_tiles(256, 256)
	world.set_map_dimensions(256, 256)
	world.set_spawn_rng_seed(222)
	# Avoid recharge confounding spend assertions.
	world.energy_recharge_rate_per_sec = 0
	world.energy_recharge_delay_ticks = 999999
	# Keep bullets around so this test can count spawns deterministically.
	world.bullet_lifetime_ticks = 0
	# Off arena center (2048,2048): the powerball sits there and fire = kick, which
	# would eat the first shot and shift every spawn tick by one.
	world.add_ship(1, Vector2(1600, 1600))
	return world


func _simulate_hold_fire_for_ticks(world: DriftWorld, ship_id: int, ticks_to_sim: int) -> Array[int]:
	var fire_cmd := DriftTypes.DriftInputCmd.new(0.0, 0.0, true, false, false)
	var spawn_ticks: Array[int] = []
	for _i in range(ticks_to_sim):
		var t := int(world.tick)
		var before := int(world.bullets.size())
		world.step_tick({ ship_id: fire_cmd })
		var after := int(world.bullets.size())
		if after > before:
			spawn_ticks.append(t)
	return spawn_ticks


func _test_classic_warbird_vs_terrier_bullet_cooldown_and_energy_spend() -> void:
	_ran += 1
	# Classic ship specs must drive authoritative bullet firing:
	# - Warbird fires every 25 ticks; Terrier every 30 ticks
	# - Total energy spent over a fixed window differs due to cooldown
	# - next_bullet_tick is set deterministically

	var classic := DriftClassicRuleset.new()
	if not classic.load():
		_fail("classic_wb_vs_tr (failed to load classic ship specs)")
		return
	var wb: Dictionary = classic.get_ship_spec("Warbird")
	var tr: Dictionary = classic.get_ship_spec("Terrier")
	if wb.is_empty() or tr.is_empty():
		_fail("classic_wb_vs_tr (missing Warbird/Terrier spec)")
		return

	var wb_e: Dictionary = wb.get("energy", {})
	var tr_e: Dictionary = tr.get("energy", {})
	var wb_w: Dictionary = wb.get("weapons", {})
	var tr_w: Dictionary = tr.get("weapons", {})
	var wb_cost: int = maxi(0, int(wb_e.get("BulletFireEnergy", -1)))
	var tr_cost: int = maxi(0, int(tr_e.get("BulletFireEnergy", -1)))
	var wb_delay: int = maxi(0, int(wb_w.get("BulletFireDelay", -1)))
	var tr_delay: int = maxi(0, int(tr_w.get("BulletFireDelay", -1)))
	var wb_init: int = maxi(0, int(wb_e.get("InitialEnergy", -1)))
	var tr_init: int = maxi(0, int(tr_e.get("InitialEnergy", -1)))
	if wb_cost < 0 or tr_cost < 0 or wb_delay < 0 or tr_delay < 0 or wb_init < 0 or tr_init < 0:
		_fail("classic_wb_vs_tr (spec missing required energy/weapons fields)")
		return

	# Expected classic values (guards against exporter regressions).
	if wb_delay != 25 or tr_delay != 30:
		_fail("classic_wb_vs_tr (expected delays wb=25 tr=30, got wb=%d tr=%d)" % [wb_delay, tr_delay])
		return
	if wb_cost != 20 or tr_cost != 20:
		_fail("classic_wb_vs_tr (expected costs wb=20 tr=20, got wb=%d tr=%d)" % [wb_cost, tr_cost])
		return

	var wb_world := _make_world_for_classic_ship_spec(wb)
	var tr_world := _make_world_for_classic_ship_spec(tr)
	var wb_ship: DriftTypes.DriftShipState = wb_world.ships.get(1)
	var tr_ship: DriftTypes.DriftShipState = tr_world.ships.get(1)
	if wb_ship == null or tr_ship == null:
		_fail("classic_wb_vs_tr (ship missing)")
		return

	if int(wb_ship.energy_current) != wb_init or int(tr_ship.energy_current) != tr_init:
		_fail("classic_wb_vs_tr (expected InitialEnergy applied on spawn)")
		return

	const SIM_TICKS: int = 30 # simulate ticks 0..29
	var wb_spawn_ticks := _simulate_hold_fire_for_ticks(wb_world, 1, SIM_TICKS)
	var tr_spawn_ticks := _simulate_hold_fire_for_ticks(tr_world, 1, SIM_TICKS)

	# Classic delays are centiseconds: 25 cs -> 15 ticks, 30 cs -> 18 ticks @60Hz.
	if wb_spawn_ticks != [0, 15]:
		_fail("classic_wb_vs_tr (expected Warbird spawn ticks [0,15], got %s)" % [str(wb_spawn_ticks)])
		return
	if tr_spawn_ticks != [0, 18]:
		_fail("classic_wb_vs_tr (expected Terrier spawn ticks [0,18], got %s)" % [str(tr_spawn_ticks)])
		return

	# Terrier is DoubleBarrel, so each fire event spawns two bullets; Warbird spawns one.
	if int(wb_world.bullets.size()) != wb_spawn_ticks.size():
		_fail("classic_wb_vs_tr (Warbird %d bullets for %d fires)" % [int(wb_world.bullets.size()), wb_spawn_ticks.size()])
		return
	if int(tr_world.bullets.size()) != tr_spawn_ticks.size() * 2:
		_fail("classic_wb_vs_tr (Terrier %d bullets for %d double-barrel fires)" % [int(tr_world.bullets.size()), tr_spawn_ticks.size()])
		return

	# next_bullet_tick should reflect the last fire.
	if int(wb_ship.next_bullet_tick) != 30:
		_fail("classic_wb_vs_tr (expected Warbird next_bullet_tick=30, got %d)" % [int(wb_ship.next_bullet_tick)])
		return
	if int(tr_ship.next_bullet_tick) != 36:
		_fail("classic_wb_vs_tr (expected Terrier next_bullet_tick=36, got %d)" % [int(tr_ship.next_bullet_tick)])
		return

	# Cost scales with gun level (Terrier starts at L2: InitialGuns=2).
	var wb_spent := wb_init - int(wb_ship.energy_current)
	var tr_spent := tr_init - int(tr_ship.energy_current)
	if wb_spent != wb_cost * wb_spawn_ticks.size():
		_fail("classic_wb_vs_tr (Warbird spent %d, expected %d)" % [wb_spent, wb_cost * wb_spawn_ticks.size()])
		return
	if tr_spent != tr_cost * 2 * tr_spawn_ticks.size():
		_fail("classic_wb_vs_tr (Terrier spent %d, expected %d)" % [tr_spent, tr_cost * 2 * tr_spawn_ticks.size()])
		return

	_pass("classic_warbird_vs_terrier_bullet_cooldown_and_energy_spend")


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
	var allowlist := {
		# Fixed, deliberately non-rebindable keys that mirror the original client:
		# F2 stat box, F11 spectate, F12 ship cycle, Tab spectate-target, Ctrl+M music.
		"res://client/client_main.gd": true,
		# The Esc menu's key list is fixed by the original's menu design (Q/F1-F8/1-8/S).
		"res://client/scenes/EscMenu.gd": true,
		"res://client/input/actions.gd": true,  # the rebinding table itself: DEFAULT_BINDINGS names keycodes
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


func _test_hud_name_and_bounty_present() -> void:
	_ran += 1
	# Regression guard: HUD must keep player name + bounty display.
	var packed := load("res://client/HUD.tscn")
	if packed == null or not (packed is PackedScene):
		_fail("hud_name_bounty (failed to load HUD.tscn)")
		return
	var hud = (packed as PackedScene).instantiate()
	if hud == null:
		_fail("hud_name_bounty (failed to instantiate HUD)")
		return
	# Ensure expected nodes exist.
	if not hud.has_node("Root/SpriteFontLabel"):
		_fail("hud_name_bounty (missing Root/SpriteFontLabel)")
		return
	if not hud.has_node("Root/RestLabel"):
		_fail("hud_name_bounty (missing Root/RestLabel)")
		return
	# Ensure API for updating values exists (we avoid calling _process here because HUD
	# expects a fully running scene tree).
	if not hud.has_method("set_values"):
		_fail("hud_name_bounty (HUD missing set_values API)")
		return
	hud.call("set_values", "Alice", 42, 0, 1)
	# Avoid leaking instantiated UI resources in headless mode.
	if hud is Node:
		(hud as Node).free()
	_pass("hud_name_and_bounty_present")


func _test_reverse_thrust_does_not_hard_stop_outside_safe_zone() -> void:
	_ran += 1
	# Regression guard: reverse thrust is acceleration-only; no hard stop outside safe zones.
	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("reverse_thrust (failed to load base ruleset)")
		return
	var canonical_ruleset: Dictionary = rules_res.get("ruleset", {})
	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.set_safe_zone_tiles([])
	world.add_boundary_tiles(32, 32)
	world.set_map_dimensions(32, 32)

	var ship_id := 1
	var start_pos := Vector2(16 * 16 + 8, 16 * 16 + 8)
	world.add_ship(ship_id, start_pos)
	var s: DriftTypes.DriftShipState = world.ships.get(ship_id)
	if s == null:
		_fail("reverse_thrust (ship missing)")
		return
	# Give the ship some drift so a hard-stop would be obvious.
	s.velocity = Vector2(220.0, 40.0)
	# Apply one tick of reverse thrust.
	world.step_tick({ ship_id: DriftTypes.DriftInputCmd.new(-1.0, 0.0, false, false, false) })
	if bool(s.in_safe_zone):
		_fail("reverse_thrust (unexpectedly in safe zone)")
		return
	if s.velocity == Vector2.ZERO:
		_fail("reverse_thrust (velocity hard-stopped; expected inertia to remain)")
		return
	if s.position == start_pos:
		_fail("reverse_thrust (expected movement to continue; got no displacement)")
		return
	_pass("reverse_thrust_does_not_hard_stop_outside_safe_zone")


func _test_bullet_bounce_restitution_is_level_based_per_projectile() -> void:
	_ran += 1
	# Regression guard: bounce behavior is per projectile and depends on weapon level/type.
	# Two ships fire bullets with different gun levels; the first bounce should reflect
	# different x-velocity magnitudes due to different bounce restitution.
	var ruleset := {
		"format": "driftline.ruleset",
		"schema_version": 2,
		"physics": {"wall_restitution": 0.85},
		"weapons": {
			"ball_friction": 0.98,
			"bullet": {
				"speed": 950.0,
				"lifetime_s": 2.0,
				"bounces": 1,
				"bounce_restitution": 1.0,
				"levels": {
					"1": {"bounce_restitution": 0.5},
					"3": {"bounce_restitution": 1.5},
				},
			}
		},
		"abilities": {
			"afterburner": {"drain_per_sec": 0, "speed_mult_pct": 100, "thrust_mult_pct": 160},
			"stealth": {"drain_per_sec": 0},
			"cloak": {"drain_per_sec": 0},
			"xradar": {"drain_per_sec": 0},
			"antiwarp": {"drain_per_sec": 0, "radius_px": 0},
		},
		"energy": {"max": 2000, "recharge_rate_per_sec": 0, "recharge_delay_ms": 0, "bullet_energy_cost": 0, "multifire_energy_cost": 0, "bomb_energy_cost": 0},
	}
	var valid := DriftValidate.validate_ruleset_dict(ruleset)
	if not bool(valid.get("ok", false)):
		_fail("bullet_bounce_level (ruleset validation failed)")
		return
	var canonical_ruleset: Dictionary = valid.get("ruleset", ruleset)

	var world = DriftWorld.new()
	world.apply_ruleset(canonical_ruleset)
	# Add an explicit wall tile so collision normal is stable.
	world.set_solid_tiles([
		[2, 4, 0, 0],
		[2, 6, 0, 0],
	])
	world.set_door_tiles([])
	world.set_safe_zone_tiles([])
	world.add_boundary_tiles(16, 16)
	world.set_map_dimensions(16, 16)

	# Seed two bullets directly (avoids relying on fire edge triggers/timing).
	# Place each bullet just to the right of the wall tile and moving left so next_pos is blocked.
	var y1 := float(4 * 16 + 8)
	var y2 := float(6 * 16 + 8)
	# Note: bullet_radius=2, wall tile x=2 spans [32..48). Start far enough right to not overlap,
	# and move just far enough left that next_pos overlaps without the center entering the tile.
	# This avoids the degenerate "center inside tile" normal fallback.
	world.bullets[1] = DriftTypes.DriftBulletState.new(1, 1, 1, Vector2(51.0, y1), Vector2(-72.0, 0.0), int(world.tick), int(world.tick) + 600, 1)
	world.bullets[2] = DriftTypes.DriftBulletState.new(2, 2, 3, Vector2(51.0, y2), Vector2(-72.0, 0.0), int(world.tick), int(world.tick) + 600, 1)

	world.step_tick({})
	if not world.bullets.has(1) or not world.bullets.has(2):
		_fail("bullet_bounce_level (bullet despawned unexpectedly)")
		return
	var b1: DriftTypes.DriftBulletState = world.bullets.get(1)
	var b2: DriftTypes.DriftBulletState = world.bullets.get(2)
	if b1 == null or b2 == null:
		_fail("bullet_bounce_level (bullet missing after step)")
		return
	if int(b1.bounces_left) != 0 or int(b2.bounces_left) != 0:
		_fail("bullet_bounce_level (expected first bounce to consume bounces_left)")
		return
	if float(b1.velocity.x) <= 0.0 or float(b2.velocity.x) <= 0.0:
		_fail("bullet_bounce_level (expected both bullets to bounce to +X)")
		return
	var vx1: float = absf(float(b1.velocity.x))
	var vx2: float = absf(float(b2.velocity.x))
	# Level 3 should have significantly higher post-bounce x speed than level 1.
	if vx2 <= vx1 + 1.0:
		_fail("bullet_bounce_level (expected level3 bounce vx > level1; got %0.3f vs %0.3f)" % [vx2, vx1])
		return
	_pass("bullet_bounce_restitution_is_level_based_per_projectile")


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


func _test_all_eight_ship_specs_load() -> void:
	_ran += 1
	var registry := DriftShipRegistry.new()
	if not registry.load_all_specs():
		_fail("all_eight_ship_specs_load (load_all_specs returned false)")
		return
	if registry.specs.size() != 8:
		_fail("all_eight_ship_specs_load (expected 8 specs, got %d)" % registry.specs.size())
		return
	for i in range(8):
		var spec: Dictionary = registry.get_spec(i)
		if spec.is_empty():
			_fail("all_eight_ship_specs_load (spec %d (%s) is empty)" % [i, DriftShipRegistry.ship_name(i)])
			return
		# Each spec must have at minimum an energy and weapons section.
		if not spec.has("energy"):
			_fail("all_eight_ship_specs_load (spec %d missing 'energy')" % i)
			return
		if not spec.has("weapons"):
			_fail("all_eight_ship_specs_load (spec %d missing 'weapons')" % i)
			return
	# Verify name lookup roundtrip.
	for i in range(8):
		var name: String = DriftShipRegistry.ship_name(i)
		var idx: int = DriftShipRegistry.ship_type_from_name(name)
		if idx != i:
			_fail("all_eight_ship_specs_load (name roundtrip failed for %d/%s -> %d)" % [i, name, idx])
			return
	_pass("all_eight_ship_specs_load")


func _test_ship_type_change_respawns_with_correct_spec() -> void:
	_ran += 1
	var rules_res: Dictionary = DriftRuleset.load_ruleset("res://rulesets/base.json")
	if not bool(rules_res.get("ok", false)):
		_fail("ship_type_change (failed to load base ruleset)")
		return
	var rs: Dictionary = rules_res.get("ruleset", {})
	rs["team"] = {"max_freq": 2, "force_even": false}
	var valid := DriftValidate.validate_ruleset_dict(rs)
	if not bool(valid.get("ok", false)):
		_fail("ship_type_change (validate failed)")
		return
	var canonical: Dictionary = valid.get("ruleset", rs)

	var registry := DriftShipRegistry.new()
	if not registry.load_all_specs():
		_fail("ship_type_change (registry load failed)")
		return

	var world := DriftWorld.new()
	world.apply_ruleset(canonical)
	world.set_solid_tiles([])
	world.set_door_tiles([])
	world.add_boundary_tiles(64, 64)
	world.set_map_dimensions(64, 64)
	world.set_all_ship_specs(registry.specs)

	world.add_ship(1, Vector2(512, 512))
	var s: DriftTypes.DriftShipState = world.ships.get(1)
	if s == null:
		_fail("ship_type_change (ship null after add)")
		return
	# Default ship type should be 0 (Warbird).
	if int(s.ship_type) != 0:
		_fail("ship_type_change (default ship_type should be 0, got %d)" % int(s.ship_type))
		return

	# Change to Javelin (type 1).
	var ok := world.change_ship_type(1, 1)
	if not ok:
		_fail("ship_type_change (change_ship_type returned false)")
		return
	s = world.ships.get(1)
	if int(s.ship_type) != 1:
		_fail("ship_type_change (expected ship_type 1 after change, got %d)" % int(s.ship_type))
		return
	# Weapons/upgrades reset to the NEW ship's spec defaults, which are per-ship:
	# Javelin is InitialGuns=1, InitialBombs=0 in the original server.cfg.
	var want_gun: int = world._ship_spec_initial_gun_level(s)
	var want_bomb: int = world._ship_spec_initial_bomb_level(s)
	if int(s.gun_level) != want_gun or int(s.bomb_level) != want_bomb:
		_fail("ship_type_change (levels not reset to spec: gun %d want %d, bomb %d want %d)" % [int(s.gun_level), want_gun, int(s.bomb_level), want_bomb])
		return
	if bool(s.multi_fire_enabled):
		_fail("ship_type_change (multi_fire should be off after change)")
		return

	# Invalid type should fail.
	if world.change_ship_type(1, -1):
		_fail("ship_type_change (should reject type -1)")
		return
	if world.change_ship_type(1, 8):
		_fail("ship_type_change (should reject type 8)")
		return
	if world.change_ship_type(999, 0):
		_fail("ship_type_change (should reject nonexistent ship)")
		return

	_pass("ship_type_change_respawns_with_correct_spec")


func _test_ship_type_persists_across_snapshot_roundtrip() -> void:
	_ran += 1
	# Create ships with different ship types, pack a snapshot, unpack, verify types survive.
	var s0 := DriftTypes.DriftShipState.new(1, Vector2(100, 200))
	s0.ship_type = 0

	var s1 := DriftTypes.DriftShipState.new(2, Vector2(300, 400))
	s1.rotation = 1.5
	s1.ship_type = 5  # Weasel

	var s2 := DriftTypes.DriftShipState.new(3, Vector2(500, 600))
	s2.rotation = 3.0
	s2.ship_type = 7  # Shark

	var ships_arr: Array = [s0, s1, s2]
	var packed: PackedByteArray = DriftNet.pack_snapshot_packet(42, ships_arr)
	if packed.size() == 0:
		_fail("ship_type_snapshot_roundtrip (pack returned empty)")
		return

	var unpacked: Dictionary = DriftNet.unpack_snapshot_packet(packed)
	if unpacked.is_empty():
		_fail("ship_type_snapshot_roundtrip (unpack returned empty)")
		return
	var out_ships: Array = unpacked.get("ships", [])
	if out_ships.size() != 3:
		_fail("ship_type_snapshot_roundtrip (expected 3 ships, got %d)" % out_ships.size())
		return

	# Build id -> ship_type map from unpacked.
	var type_by_id: Dictionary = {}
	for ss in out_ships:
		type_by_id[int(ss.id)] = int(ss.ship_type)

	if type_by_id.get(1, -1) != 0:
		_fail("ship_type_snapshot_roundtrip (ship 1 expected type 0, got %d)" % type_by_id.get(1, -1))
		return
	if type_by_id.get(2, -1) != 5:
		_fail("ship_type_snapshot_roundtrip (ship 2 expected type 5, got %d)" % type_by_id.get(2, -1))
		return
	if type_by_id.get(3, -1) != 7:
		_fail("ship_type_snapshot_roundtrip (ship 3 expected type 7, got %d)" % type_by_id.get(3, -1))
		return

	_pass("ship_type_persists_across_snapshot_roundtrip")


func _test_repel_pushes_nearby_ships() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	world.add_ship(2, Vector2(600, 500))  # 100px away (within 512 radius)
	world.add_ship(3, Vector2(2000, 2000))  # Far away (outside radius)
	var s1 = world.ships.get(1)
	var s2 = world.ships.get(2)
	var s3 = world.ships.get(3)
	s1.repel_count = 2
	var old_s3_vel: Vector2 = s3.velocity
	world._use_repel(s1)
	if int(s1.repel_count) != 1:
		_fail("repel_pushes (count should be 1 after use, got %d)" % int(s1.repel_count))
		return
	if s2.velocity.length() < 100.0:
		_fail("repel_pushes (nearby ship should be pushed, vel=%s)" % str(s2.velocity))
		return
	if s3.velocity.length() > 1.0:
		_fail("repel_pushes (far ship should not be pushed, vel=%s)" % str(s3.velocity))
		return
	_pass("repel_pushes_nearby_ships")


func _test_burst_fires_shrapnel_ring() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	var s1 = world.ships.get(1)
	s1.burst_count = 1
	var bullets_before: int = world.bullets.size()
	world._use_burst(s1)
	var bullets_after: int = world.bullets.size()
	if int(s1.burst_count) != 0:
		_fail("burst_fires (count should be 0 after use, got %d)" % int(s1.burst_count))
		return
	var spawned: int = bullets_after - bullets_before
	if spawned < 8:
		_fail("burst_fires (expected >=8 shrapnel bullets, got %d)" % spawned)
		return
	_pass("burst_fires_shrapnel_ring")


func _test_shields_absorb_damage() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	var s1 = world.ships.get(1)
	# Give shields (active for 240 ticks = 4 seconds at 60Hz)
	s1.shields_until_tick = int(world.tick) + 240
	s1.super_shields = false
	var energy_before: int = int(s1.energy_current)
	# Apply damage — should be absorbed by shield
	world.adjust_energy(1, -100, DriftWorld.EnergyReason.DAMAGE_BULLET, 2)
	if int(s1.energy_current) != energy_before:
		_fail("shields_absorb (energy should be unchanged, was %d now %d)" % [energy_before, int(s1.energy_current)])
		return
	# Regular shield should expire after one hit
	if int(s1.shields_until_tick) != 0:
		_fail("shields_absorb (regular shield should expire after hit, until_tick=%d)" % int(s1.shields_until_tick))
		return
	# Now test super shields: absorb but don't expire
	s1.shields_until_tick = int(world.tick) + 240
	s1.super_shields = true
	world.adjust_energy(1, -100, DriftWorld.EnergyReason.DAMAGE_BOMB, 2)
	if int(s1.energy_current) != energy_before:
		_fail("shields_absorb (super: energy changed)")
		return
	if int(s1.shields_until_tick) <= int(world.tick):
		_fail("shields_absorb (super shield should persist)")
		return
	_pass("shields_absorb_damage")


func _test_warp_teleports_ship() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	var s1 = world.ships.get(1)
	s1.warp_count = 1
	var old_pos: Vector2 = s1.position
	world._use_warp(s1)
	if int(s1.warp_count) != 0:
		_fail("warp_teleports (count should be 0, got %d)" % int(s1.warp_count))
		return
	# Position should have changed (extremely unlikely to land on exact same spot)
	if s1.position.distance_to(old_pos) < 1.0:
		_fail("warp_teleports (position didn't change)")
		return
	_pass("warp_teleports_ship")


func _test_antiwarp_blocks_warp() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	world.add_ship(2, Vector2(600, 500))  # 100px away
	var s1 = world.ships.get(1)
	var s2 = world.ships.get(2)
	s1.warp_count = 1
	s2.antiwarp_on = true
	var old_pos: Vector2 = s1.position
	world._use_warp(s1)
	# Warp should be blocked — count should remain 1 and position unchanged
	if int(s1.warp_count) != 1:
		_fail("antiwarp_blocks (warp count should remain 1, got %d)" % int(s1.warp_count))
		return
	if s1.position.distance_to(old_pos) > 1.0:
		_fail("antiwarp_blocks (position should not change)")
		return
	_pass("antiwarp_blocks_warp")


func _test_items_persist_across_snapshot_roundtrip() -> void:
	_ran += 1
	var s0 := DriftTypes.DriftShipState.new(1, Vector2(100, 200))
	s0.repel_count = 2
	s0.burst_count = 3
	s0.warp_count = 1
	s0.thor_count = 2
	s0.brick_count = 1
	s0.portal_count = 3
	s0.shields_until_tick = 500
	s0.super_shields = true
	var ships_arr: Array = [s0]
	var packed: PackedByteArray = DriftNet.pack_snapshot_packet(100, ships_arr)
	var unpacked: Dictionary = DriftNet.unpack_snapshot_packet(packed)
	if unpacked.is_empty():
		_fail("items_snapshot_roundtrip (unpack failed)")
		return
	var out_ships: Array = unpacked.get("ships", [])
	if out_ships.size() != 1:
		_fail("items_snapshot_roundtrip (expected 1 ship)")
		return
	var out: DriftTypes.DriftShipState = out_ships[0]
	if int(out.repel_count) != 2 or int(out.burst_count) != 3 or int(out.warp_count) != 1:
		_fail("items_snapshot_roundtrip (counts: repel=%d burst=%d warp=%d)" % [int(out.repel_count), int(out.burst_count), int(out.warp_count)])
		return
	if int(out.thor_count) != 2 or int(out.brick_count) != 1 or int(out.portal_count) != 3:
		_fail("items_snapshot_roundtrip (counts: thor=%d brick=%d portal=%d)" % [int(out.thor_count), int(out.brick_count), int(out.portal_count)])
		return
	if int(out.shields_until_tick) != 500 or not bool(out.super_shields):
		_fail("items_snapshot_roundtrip (shields: until=%d super=%s)" % [int(out.shields_until_tick), str(out.super_shields)])
		return
	_pass("items_persist_across_snapshot_roundtrip")


func _test_kill_event_packet_roundtrip() -> void:
	_ran += 1
	var packed: PackedByteArray = DriftNet.pack_kill_event(5, 3, 1, "Alice", "Bob")
	var unpacked: Dictionary = DriftNet.unpack_kill_event(packed)
	if unpacked.is_empty():
		_fail("kill_event_roundtrip (unpack failed)")
		return
	if int(unpacked.get("attacker_id", -1)) != 5 or int(unpacked.get("victim_id", -1)) != 3:
		_fail("kill_event_roundtrip (ids wrong)")
		return
	if int(unpacked.get("weapon_type", -1)) != 1:
		_fail("kill_event_roundtrip (weapon_type wrong)")
		return
	if String(unpacked.get("attacker_name", "")) != "Alice" or String(unpacked.get("victim_name", "")) != "Bob":
		_fail("kill_event_roundtrip (names wrong)")
		return
	_pass("kill_event_packet_roundtrip")


func _test_chat_message_packet_roundtrip() -> void:
	_ran += 1
	var packed: PackedByteArray = DriftNet.pack_chat_message(7, DriftNet.CHAT_TYPE_TEAM, "hello world", "target_player")
	var unpacked: Dictionary = DriftNet.unpack_chat_message(packed)
	if unpacked.is_empty():
		_fail("chat_message_roundtrip (unpack failed)")
		return
	if int(unpacked.get("ship_id", -1)) != 7:
		_fail("chat_message_roundtrip (ship_id wrong)")
		return
	if int(unpacked.get("chat_type", -1)) != DriftNet.CHAT_TYPE_TEAM:
		_fail("chat_message_roundtrip (chat_type wrong)")
		return
	if String(unpacked.get("text", "")) != "hello world":
		_fail("chat_message_roundtrip (text wrong: '%s')" % String(unpacked.get("text", "")))
		return
	if String(unpacked.get("target_name", "")) != "target_player":
		_fail("chat_message_roundtrip (target_name wrong)")
		return
	_pass("chat_message_packet_roundtrip")


func _test_chat_broadcast_packet_roundtrip() -> void:
	_ran += 1
	var packed: PackedByteArray = DriftNet.pack_chat_broadcast("SenderName", DriftNet.CHAT_TYPE_PRIVATE, "secret msg", 3)
	var unpacked: Dictionary = DriftNet.unpack_chat_broadcast(packed)
	if unpacked.is_empty():
		_fail("chat_broadcast_roundtrip (unpack failed)")
		return
	if String(unpacked.get("sender_name", "")) != "SenderName":
		_fail("chat_broadcast_roundtrip (sender_name wrong)")
		return
	if int(unpacked.get("chat_type", -1)) != DriftNet.CHAT_TYPE_PRIVATE:
		_fail("chat_broadcast_roundtrip (chat_type wrong)")
		return
	if String(unpacked.get("text", "")) != "secret msg":
		_fail("chat_broadcast_roundtrip (text wrong)")
		return
	if int(unpacked.get("sender_freq", -1)) != 3:
		_fail("chat_broadcast_roundtrip (sender_freq wrong)")
		return
	_pass("chat_broadcast_packet_roundtrip")


func _test_kill_death_stats_in_snapshot() -> void:
	_ran += 1
	var s0 := DriftTypes.DriftShipState.new(1, Vector2(100, 200))
	s0.kills = 5
	s0.deaths = 2
	var ships_arr: Array = [s0]
	var packed: PackedByteArray = DriftNet.pack_snapshot_packet(200, ships_arr)
	var unpacked: Dictionary = DriftNet.unpack_snapshot_packet(packed)
	if unpacked.is_empty():
		_fail("kill_death_stats_snapshot (unpack failed)")
		return
	var out_ships: Array = unpacked.get("ships", [])
	if out_ships.size() != 1:
		_fail("kill_death_stats_snapshot (expected 1 ship)")
		return
	var out: DriftTypes.DriftShipState = out_ships[0]
	if int(out.kills) != 5 or int(out.deaths) != 2:
		_fail("kill_death_stats_snapshot (kills=%d deaths=%d)" % [int(out.kills), int(out.deaths)])
		return
	_pass("kill_death_stats_in_snapshot")


func _test_kill_scoring_awards_points() -> void:
	_ran += 1
	# Kill reward = victim bounty; killer bounty += kill_bounty_increase; victim bounty resets.
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(100, 100))
	world.add_ship(2, Vector2(300, 100))
	var attacker: DriftTypes.DriftShipState = world.ships[1]
	var victim: DriftTypes.DriftShipState = world.ships[2]
	attacker.freq = 1
	victim.freq = 2
	victim.bounty = 12
	var ok := world.apply_damage(1, 2, 999999, "bullet")
	if not ok:
		_fail("kill_scoring (damage rejected)")
		return
	if int(victim.deaths) != 1:
		_fail("kill_scoring (victim deaths=%d)" % int(victim.deaths))
		return
	if int(attacker.points) != 12:
		_fail("kill_scoring (attacker points=%d, expected 12)" % int(attacker.points))
		return
	if int(attacker.bounty) != int(world.kill_bounty_increase):
		_fail("kill_scoring (attacker bounty=%d, expected %d)" % [int(attacker.bounty), int(world.kill_bounty_increase)])
		return
	if int(victim.bounty) != 0:
		_fail("kill_scoring (victim bounty=%d, expected reset to 0)" % int(victim.bounty))
		return
	# Points survive a snapshot roundtrip.
	var packed: PackedByteArray = DriftNet.pack_snapshot_packet(1, [attacker])
	var unpacked: Dictionary = DriftNet.unpack_snapshot_packet(packed)
	var out_ships: Array = unpacked.get("ships", [])
	if out_ships.size() != 1 or int(out_ships[0].points) != 12:
		_fail("kill_scoring (points snapshot roundtrip)")
		return
	_pass("kill_scoring_awards_points")


func _test_wormhole_pull_and_teleport() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(200, 200)
	var wh_a := Vector2(800.0, 800.0)
	var wh_b := Vector2(2400.0, 800.0)
	world.set_wormholes([wh_a, wh_b])
	# Ship inside pull radius drifts toward the wormhole.
	world.add_ship(1, wh_a + Vector2(300.0, 0.0))
	var s: DriftTypes.DriftShipState = world.ships[1]
	world.step_tick({})
	if s.velocity.x >= 0.0:
		_fail("wormhole (no pull: vel.x=%f)" % s.velocity.x)
		return
	# Ship at the core teleports away.
	s.position = wh_a
	s.velocity = Vector2.ZERO
	world.step_tick({})
	if s.position.distance_to(wh_a) < world.WORMHOLE_PULL_RADIUS_PX:
		_fail("wormhole (no teleport: dist=%f)" % s.position.distance_to(wh_a))
		return
	_pass("wormhole_pull_and_teleport")


func _test_classic_ship_stats() -> void:
	_ran += 1
	# Per-ship classic stats: Javelin (type 1) is faster than Warbird (type 0);
	# energy starts at InitialEnergy and recharges at InitialRecharge/10 per sec;
	# Spider (type 2) spawns with its decoy.
	var registry := DriftShipRegistry.new()
	if not registry.load_all_specs():
		_fail("classic_ship_stats (registry load failed)")
		return
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.set_all_ship_specs(registry.specs)
	world.add_ship(1, Vector2(100, 100), 0) # Warbird
	world.add_ship(2, Vector2(300, 100), 1) # Javelin
	world.add_ship(3, Vector2(500, 100), 2) # Spider
	var wb: DriftTypes.DriftShipState = world.ships[1]
	var jav: DriftTypes.DriftShipState = world.ships[2]
	var spi: DriftTypes.DriftShipState = world.ships[3]
	var wb_speed: float = world._ship_effective_max_speed(wb)
	var jav_speed: float = world._ship_effective_max_speed(jav)
	# cfg: Warbird InitialSpeed=2010 -> 201 px/s; Javelin 2200 -> 220 px/s.
	if absf(wb_speed - 201.0) > 0.5 or absf(jav_speed - 220.0) > 0.5:
		_fail("classic_ship_stats (speeds wb=%f jav=%f)" % [wb_speed, jav_speed])
		return
	# InitialEnergy=1000 is both spawn energy and starting max.
	if int(wb.energy_max) != 1000 or int(wb.energy_current) != 1000:
		_fail("classic_ship_stats (energy %d/%d, expected 1000/1000)" % [int(wb.energy_current), int(wb.energy_max)])
		return
	# InitialRecharge=400 -> 40 e/s.
	if int(wb.energy_recharge_rate_per_sec) != 40:
		_fail("classic_ship_stats (recharge %d, expected 40)" % int(wb.energy_recharge_rate_per_sec))
		return
	if int(spi.decoy_count) != 1:
		_fail("classic_ship_stats (spider decoy_count=%d, expected 1)" % int(spi.decoy_count))
		return
	# TopSpeed prize raises speed by UpgradeSpeed (250 -> +25 px/s).
	wb.top_speed_bonus = 1
	if absf(world._ship_effective_max_speed(wb) - 226.0) > 0.5:
		_fail("classic_ship_stats (upgraded speed %f, expected 226)" % world._ship_effective_max_speed(wb))
		return
	# Classic damage economy: bullets 200/300/400 by level, burst pellets 515, bombs 750.
	var d1: int = int(world._resolve_bullet_combat_cfg_for_level(1).get("damage", 0))
	var d3: int = int(world._resolve_bullet_combat_cfg_for_level(3).get("damage", 0))
	var d4: int = int(world._resolve_bullet_combat_cfg_for_level(4).get("damage", 0))
	if d1 != 200 or d3 != 400 or d4 != 515 or int(world.bomb_damage_level) != 750:
		_fail("classic_ship_stats (damage L1=%d L3=%d burst=%d bomb=%d)" % [d1, d3, d4, int(world.bomb_damage_level)])
		return
	_pass("classic_ship_stats")


func _test_thor_and_burst_classic() -> void:
	_ran += 1
	# Thor: single L4 bomb that travels through walls.
	var world = DriftWorld.new()
	world.set_map_dimensions(100, 100)
	var solids: Array = []
	for ty in range(0, 100):
		solids.append([20, ty, 0, 0])
	world.set_solid_tiles(solids)
	world.add_ship(1, Vector2(160, 160))
	var s: DriftTypes.DriftShipState = world.ships[1]
	s.rotation = 0.0
	s.thor_count = 1
	world._use_thor(s)
	if world.bombs.size() != 1:
		_fail("thor_burst (expected 1 thor bomb, got %d)" % world.bombs.size())
		return
	var thor: DriftTypes.DriftBombState = world.bombs.values()[0]
	if int(thor.level) != 4:
		_fail("thor_burst (thor level=%d, expected 4)" % int(thor.level))
		return
	for _i in range(400):
		world.step_tick({})
	if not world.bombs.has(int(thor.id)) or thor.position.x <= 20.0 * 16.0 + 16.0:
		_fail("thor_burst (thor blocked by wall: alive=%s x=%f)" % [str(world.bombs.has(int(thor.id))), thor.position.x])
		return
	# Burst: pellets are level 4, unarmed until they bounce.
	var w2 = DriftWorld.new()
	w2.set_map_dimensions(80, 60)
	w2.add_ship(1, Vector2(300, 300))
	w2.add_ship(2, Vector2(340, 300))
	w2.ships[1].freq = 1
	w2.ships[2].freq = 2
	w2.ships[1].burst_count = 1
	w2._use_burst(w2.ships[1])
	if w2.bullets.is_empty():
		_fail("thor_burst (no burst pellets)")
		return
	var e0: int = int(w2.ships[2].energy_current)
	w2.step_tick({})
	if int(w2.ships[2].energy_current) < e0:
		_fail("thor_burst (unarmed pellet damaged ship)")
		return
	# Arm one pellet (simulate a wall bounce) and aim it at the enemy.
	var pellet: DriftTypes.DriftBulletState = w2.bullets.values()[0]
	pellet.bounces_left = 99
	pellet.position = Vector2(335, 300)
	pellet.velocity = Vector2(60, 0)
	w2.step_tick({})
	if int(w2.ships[2].energy_current) >= e0:
		_fail("thor_burst (armed pellet did no damage)")
		return
	_pass("thor_and_burst_classic")


func _test_portal_beacon_roundtrip() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(300, 300))
	var s: DriftTypes.DriftShipState = world.ships[1]
	s.portal_count = 1
	# First use: drops beacon at current position, consumes charge, no teleport.
	world._use_portal(s)
	if int(s.portal_count) != 0 or int(s.portal_until_tick) <= 0 or s.portal_pos != Vector2(300, 300):
		_fail("portal (beacon not dropped: count=%d until=%d)" % [int(s.portal_count), int(s.portal_until_tick)])
		return
	if s.position != Vector2(300, 300):
		_fail("portal (drop should not teleport)")
		return
	# Move away, use again: returns to beacon, clears it.
	s.position = Vector2(700, 700)
	world._use_portal(s)
	if s.position != Vector2(300, 300) or int(s.portal_until_tick) != 0:
		_fail("portal (return failed: pos=%s until=%d)" % [str(s.position), int(s.portal_until_tick)])
		return
	_pass("portal_beacon_roundtrip")


func _test_thor_fires_ring() -> void:
	_ran += 1
	# Classic Thor: consumes one charge and fires a single L4 bomb.
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	var s1 = world.ships.get(1)
	s1.thor_count = 1
	var before: int = world.bombs.size()
	world._use_thor(s1)
	if int(s1.thor_count) != 0:
		_fail("thor_fires_ring (count should be 0)")
		return
	if world.bombs.size() - before != 1:
		_fail("thor_fires_ring (expected 1 thor bomb, got %d)" % (world.bombs.size() - before))
		return
	_pass("thor_single_l4_bomb")


func _test_rocket_boosts_speed() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	var s1 = world.ships.get(1)
	s1.rocket_count = 1
	# Rocket is a timed thrust boost (rocket_boost_until_tick), not a permanent
	# top_speed_bonus — that is what the TopSpeed prize grants.
	var boost_before: int = int(s1.rocket_boost_until_tick)
	world._use_rocket(s1)
	if int(s1.rocket_count) != 0:
		_fail("rocket_boosts_speed (count should be 0)")
		return
	if int(s1.rocket_boost_until_tick) <= boost_before:
		_fail("rocket_boosts_speed (boost should extend past tick %d, got %d)" % [boost_before, int(s1.rocket_boost_until_tick)])
		return
	if int(s1.rocket_boost_until_tick) <= int(world.tick):
		_fail("rocket_boosts_speed (boost should end in the future, got %d at tick %d)" % [int(s1.rocket_boost_until_tick), int(world.tick)])
		return
	_pass("rocket_boosts_speed")


func _test_decoy_spawns_and_expires() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	var s1 = world.ships.get(1)
	s1.decoy_count = 1
	world._use_decoy(s1)
	if int(s1.decoy_count) != 0:
		_fail("decoy_spawns (count should be 0)")
		return
	if world.decoys.size() != 1:
		_fail("decoy_spawns (expected 1 decoy, got %d)" % world.decoys.size())
		return
	# Step past die_tick — decoy should be reaped.
	var d = world.decoys.values()[0]
	var ticks_left: int = int(d.die_tick) - int(world.tick) + 1
	for _i in range(ticks_left):
		world._step_decoys()
		world.tick += 1
	if world.decoys.size() != 0:
		_fail("decoy_spawns (decoy should expire, still %d present)" % world.decoys.size())
		return
	_pass("decoy_spawns_and_expires")


func _test_shrapnel_prize_adds_bonus() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	var s1 = world.ships.get(1)
	var before: int = int(s1.shrapnel_bonus)
	world._apply_prize_effect(s1, DriftTypes.PrizeKind.Shrapnel, false, 0)
	if int(s1.shrapnel_bonus) != before + 1:
		_fail("shrapnel_prize (bonus should be %d, got %d)" % [before + 1, int(s1.shrapnel_bonus)])
		return
	world._apply_prize_effect(s1, DriftTypes.PrizeKind.Shrapnel, true, 0)
	if int(s1.shrapnel_bonus) != before:
		_fail("shrapnel_prize (negative should restore to %d, got %d)" % [before, int(s1.shrapnel_bonus)])
		return
	_pass("shrapnel_prize_adds_bonus")


func _test_rotation_prize_adds_bonus() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	var s1 = world.ships.get(1)
	world._apply_prize_effect(s1, DriftTypes.PrizeKind.Rotation, false, 0)
	if int(s1.rotation_bonus) != 1:
		_fail("rotation_prize (bonus should be 1, got %d)" % int(s1.rotation_bonus))
		return
	world._apply_prize_effect(s1, DriftTypes.PrizeKind.Rotation, true, 0)
	if int(s1.rotation_bonus) != 0:
		_fail("rotation_prize (negative should restore to 0, got %d)" % int(s1.rotation_bonus))
		return
	_pass("rotation_prize_adds_bonus")


func _test_all_weapons_prize() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	var s1 = world.ships.get(1)
	world._apply_prize_effect(s1, DriftTypes.PrizeKind.AllWeapons, false, 0)
	if int(s1.gun_level) < 2:
		_fail("all_weapons_prize (gun_level should be >=2, got %d)" % int(s1.gun_level))
		return
	if int(s1.bomb_level) < 2:
		_fail("all_weapons_prize (bomb_level should be >=2, got %d)" % int(s1.bomb_level))
		return
	if not bool(s1.multi_fire_enabled):
		_fail("all_weapons_prize (multi_fire should be enabled)")
		return
	_pass("all_weapons_prize")


func _test_decoy_snapshot_roundtrip() -> void:
	_ran += 1
	var d := DriftTypes.DriftDecoyState.new(42, 1, 0, 2, Vector2(100, 200), Vector2(50, -30), 1.5, 999)
	var s0 := DriftTypes.DriftShipState.new(1, Vector2(0, 0))
	var packed: PackedByteArray = DriftNet.pack_snapshot_packet(10, [s0], Vector2.ZERO, Vector2.ZERO, -1, [], [], [], [], [], {}, [d])
	var unpacked: Dictionary = DriftNet.unpack_snapshot_packet(packed)
	var out_decoys: Array = unpacked.get("decoys", [])
	if out_decoys.size() != 1:
		_fail("decoy_snapshot_roundtrip (expected 1 decoy, got %d)" % out_decoys.size())
		return
	var od: DriftTypes.DriftDecoyState = out_decoys[0]
	if int(od.id) != 42 or int(od.ship_type) != 2:
		_fail("decoy_snapshot_roundtrip (id=%d type=%d)" % [int(od.id), int(od.ship_type)])
		return
	if abs(od.position.x - 100.0) > 0.1 or abs(od.position.y - 200.0) > 0.1:
		_fail("decoy_snapshot_roundtrip (position mismatch)")
		return
	_pass("decoy_snapshot_roundtrip")


func _test_brick_places_and_expires() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	var s1 = world.ships.get(1)
	s1.brick_count = 1
	s1.velocity = Vector2(100, 0)
	var solid_before: int = world.solid_tiles.size()
	world._use_brick(s1)
	if int(s1.brick_count) != 0:
		_fail("brick_places (count should be 0 after use)")
		return
	if world.solid_tiles.size() <= solid_before:
		_fail("brick_places (no new solid tiles added)")
		return
	if world.bricks.size() != 1:
		_fail("brick_places (bricks array should have 1 entry)")
		return
	# Advance past die_tick.
	var die_tick: int = int(world.bricks[0].die_tick)
	world.tick = die_tick + 1
	world._step_bricks()
	if world.solid_tiles.size() != solid_before:
		_fail("brick_expires (tiles should be removed after expiry, remaining=%d extra)" % (world.solid_tiles.size() - solid_before))
		return
	_pass("brick_places_and_expires")


func _test_quickcharge_prize_fills_energy() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	var s1 = world.ships.get(1)
	s1.energy_current = 10
	s1.energy_max = 1000
	world._apply_prize_effect(s1, DriftTypes.PrizeKind.QuickCharge, false, 0)
	if int(s1.energy_current) != 1000:
		_fail("quickcharge_prize (energy should be 1000, got %d)" % int(s1.energy_current))
		return
	_pass("quickcharge_prize_fills_energy")


func _test_stealth_prize_toggles_ability() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	var s1 = world.ships.get(1)
	world._apply_prize_effect(s1, DriftTypes.PrizeKind.Stealth, false, 0)
	if not bool(s1.stealth_on):
		_fail("stealth_prize (should be on after positive prize)")
		return
	world._apply_prize_effect(s1, DriftTypes.PrizeKind.Stealth, true, 0)
	if bool(s1.stealth_on):
		_fail("stealth_prize (should be off after negative prize)")
		return
	_pass("stealth_prize_toggles_ability")


func _test_portal_prize_and_use() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	var s1 = world.ships.get(1)
	if int(s1.portal_count) != 0:
		_fail("portal_prize (initial count should be 0, got %d)" % int(s1.portal_count))
		return
	world._apply_prize_effect(s1, DriftTypes.PrizeKind.Portal, false, 0)
	if int(s1.portal_count) != 1:
		_fail("portal_prize (count should be 1 after pickup, got %d)" % int(s1.portal_count))
		return
	var start_pos: Vector2 = s1.position
	world._use_portal(s1)
	if int(s1.portal_count) != 0:
		_fail("portal_prize (count should be 0 after use, got %d)" % int(s1.portal_count))
		return
	# Classic portal: first use drops a return beacon instead of teleporting.
	if s1.position != start_pos or int(s1.portal_until_tick) <= 0:
		_fail("portal_prize (expected beacon drop without teleport)")
		return
	_pass("portal_prize_and_use")


func _test_king_ship_id_snapshot_roundtrip() -> void:
	# king_ship_id should survive pack → unpack.
	var world := DriftWorld.new()
	world.add_ship(1, Vector2(100, 100))
	var snap := world.step_tick({}, false, 1)
	snap.king_ship_id = 1
	var ships_arr := DriftNet.snapshot_ships_from_dict(snap.ships)
	var packed := DriftNet.pack_snapshot_packet(snap.tick, ships_arr, Vector2.ZERO, Vector2.ZERO, -1,
		[], [], [], [], [], {"king_ship_id": 1})
	var unpacked := DriftNet.unpack_snapshot_packet(packed)
	if int(unpacked.get("king_ship_id", -999)) != 1:
		_fail("king_ship_id_snapshot_roundtrip: expected 1 got %d" % int(unpacked.get("king_ship_id", -999)))
		return
	# king_ship_id = -1 (no king) should also roundtrip.
	var packed2 := DriftNet.pack_snapshot_packet(snap.tick, ships_arr, Vector2.ZERO, Vector2.ZERO, -1,
		[], [], [], [], [], {"king_ship_id": -1})
	var unpacked2 := DriftNet.unpack_snapshot_packet(packed2)
	if int(unpacked2.get("king_ship_id", -999)) != -1:
		_fail("king_ship_id_snapshot_roundtrip (no king): expected -1 got %d" % int(unpacked2.get("king_ship_id", -999)))
		return
	_pass("king_ship_id_snapshot_roundtrip")


func _test_server_hello_sets_username() -> void:
	# pack_hello / unpack_hello roundtrip.
	var name_in := "TestBot_42"
	var pkt := DriftNet.pack_hello(name_in)
	var name_out := DriftNet.unpack_hello(pkt)
	if name_out != name_in:
		_fail("server_hello_sets_username: expected '%s' got '%s'" % [name_in, name_out])
		return
	_pass("server_hello_sets_username")


func _test_two_worlds_do_not_share_arena() -> void:
	_ran += 1
	# Regression: arena bounds used to live in DriftConstants static vars, so the
	# last world constructed silently redefined the arena for every other world in
	# the process — construction order changed simulation results.
	var small := DriftWorld.new()
	small.set_map_dimensions(64, 64)
	var large := DriftWorld.new()
	large.set_map_dimensions(256, 256)

	if small.arena_max != Vector2(1024, 1024):
		_fail("two_worlds_arena (small world bounds clobbered: %s)" % str(small.arena_max))
		return
	if large.arena_max != Vector2(4096, 4096):
		_fail("two_worlds_arena (large world bounds wrong: %s)" % str(large.arena_max))
		return
	if small.arena_center != Vector2(512, 512) or large.arena_center != Vector2(2048, 2048):
		_fail("two_worlds_arena (centers wrong: %s / %s)" % [str(small.arena_center), str(large.arena_center)])
		return

	# Order must not decide who can shoot. Both worlds get identical setup; both
	# must spawn a bullet. (Off arena center so neither ship starts on the ball.)
	var fire := DriftTypes.DriftInputCmd.new(0.0, 0.0, true, false, false)
	for w in [small, large]:
		w.set_solid_tiles([])
		w.set_door_tiles([])
		w.add_ship(1, w.arena_center + Vector2(200.0, 200.0))
		w.step_tick({1: fire}, false, 0)
		if w.bullets.size() != 1:
			_fail("two_worlds_arena (expected 1 bullet, got %d)" % w.bullets.size())
			return
	_pass("two_worlds_do_not_share_arena")


func _multifire_cmd(pressed: bool) -> DriftTypes.DriftInputCmd:
	var c := DriftTypes.DriftInputCmd.new()
	c.multifire_btn = pressed
	return c


func _test_multifire_toggle_requires_capability() -> void:
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	var s1 = world.ships.get(1)

	# Without the MultiFire prize the key must not conjure the upgrade.
	world.step_tick({1: _multifire_cmd(true)}, false, 0)
	if bool(s1.multi_fire_enabled):
		_fail("multifire_toggle (enabled without the MultiFire upgrade)")
		return

	# Prize grants the capability and switches it on.
	world._apply_prize_effect(s1, DriftTypes.PrizeKind.MultiFire, false, 0)
	if not (bool(s1.multi_fire_capable) and bool(s1.multi_fire_enabled)):
		_fail("multifire_toggle (prize should grant capability and enable)")
		return

	# Press → off, release → no change, press again → on. Edge-detected, not level-triggered.
	world.step_tick({1: _multifire_cmd(false)}, false, 0)
	world.step_tick({1: _multifire_cmd(true)}, false, 0)
	if bool(s1.multi_fire_enabled):
		_fail("multifire_toggle (press should switch off)")
		return
	world.step_tick({1: _multifire_cmd(true)}, false, 0)
	if bool(s1.multi_fire_enabled):
		_fail("multifire_toggle (held key must not re-toggle)")
		return
	world.step_tick({1: _multifire_cmd(false)}, false, 0)
	world.step_tick({1: _multifire_cmd(true)}, false, 0)
	if not bool(s1.multi_fire_enabled):
		_fail("multifire_toggle (second press should switch back on)")
		return

	# Negative prize revokes the capability entirely.
	world._apply_prize_effect(s1, DriftTypes.PrizeKind.MultiFire, true, 0)
	if bool(s1.multi_fire_capable) or bool(s1.multi_fire_enabled):
		_fail("multifire_toggle (negative prize should revoke capability)")
		return
	_pass("multifire_toggle_requires_capability")


func _test_multifire_input_roundtrip() -> void:
	# The toggle bit must survive pack → unpack, and multi_fire_capable must survive a snapshot.
	_ran += 1
	var cmd := DriftTypes.DriftInputCmd.new()
	cmd.multifire_btn = true
	var d: Dictionary = DriftNet.unpack_input_packet(DriftNet.pack_input_packet(7, 3, cmd))
	if not bool(d.get("multifire_btn", false)):
		_fail("multifire_input_roundtrip (bit lost in input packet)")
		return

	var s := DriftTypes.DriftShipState.new(1, Vector2(10, 20))
	s.multi_fire_capable = true
	s.multi_fire_enabled = false
	var snap: Dictionary = DriftNet.unpack_snapshot_packet(DriftNet.pack_snapshot_packet(1, [s]))
	if snap.is_empty():
		_fail("multifire_input_roundtrip (snapshot did not unpack)")
		return
	var out_ships: Array = snap.get("ships", [])
	if out_ships.size() != 1:
		_fail("multifire_input_roundtrip (expected 1 ship)")
		return
	var back: DriftTypes.DriftShipState = out_ships[0]
	if not bool(back.multi_fire_capable) or bool(back.multi_fire_enabled):
		_fail("multifire_input_roundtrip (capability/enabled flags lost in snapshot)")
		return
	_pass("multifire_input_roundtrip")


func _test_truncated_packets_rejected() -> void:
	# The server parses input packets straight off the wire from untrusted clients, so a
	# short packet has to be rejected rather than read back as a wall of zeros (which
	# unpacks as a valid-looking input for tick 0, ship 0).
	_ran += 1
	var cmd := DriftTypes.DriftInputCmd.new(1.0, 0.5, true)
	var good: PackedByteArray = DriftNet.pack_input_packet(9, 4, cmd)
	if DriftNet.unpack_input_packet(good).is_empty():
		_fail("truncated_packets_rejected (well-formed input packet was rejected)")
		return
	for cut in [1, 5, 10, 15]:
		if not DriftNet.unpack_input_packet(good.slice(0, cut)).is_empty():
			_fail("truncated_packets_rejected (input packet of %d bytes accepted)" % cut)
			return

	var s := DriftTypes.DriftShipState.new(1, Vector2(10, 20))
	var snap: PackedByteArray = DriftNet.pack_snapshot_packet(1, [s])
	if DriftNet.unpack_snapshot_packet(snap).is_empty():
		_fail("truncated_packets_rejected (well-formed snapshot was rejected)")
		return
	# 1 type + 4 tick + 2 count = 7 header bytes, then 24 ship + 20 ball must be present.
	for cut2 in [7, 20, 40, 50]:
		if not DriftNet.unpack_snapshot_packet(snap.slice(0, cut2)).is_empty():
			_fail("truncated_packets_rejected (snapshot of %d bytes accepted)" % cut2)
			return

	var hello: PackedByteArray = DriftNet.pack_hello("driftpilot")
	if DriftNet.unpack_hello(hello) != "driftpilot":
		_fail("truncated_packets_rejected (hello did not round-trip)")
		return
	if DriftNet.unpack_hello(hello.slice(0, 7)) != "":
		_fail("truncated_packets_rejected (truncated hello returned a name)")
		return
	_pass("truncated_packets_rejected")


func _test_chat_commands() -> void:
	_ran += 1
	var ctx: Dictionary = {
		"ping_ms": 42,
		"loss_pct": 1.25,
		"status": {"recharge": 50, "thruster": 25, "speed": 0, "rotation": 75, "shrapnel": 3},
		"flag_holders": [],
		"team": ["Bob (1)", "Eve (0)"],
	}

	# =NNNN is a frequency request, not chat.
	var freq: Dictionary = DriftChatCommands.parse("=555", ctx)
	if String(freq.get("kind")) != DriftChatCommands.KIND_FREQ or int(freq.get("freq")) != 555:
		_fail("chat_commands (=555 should request freq 555)")
		return
	if String(DriftChatCommands.parse("=abc", ctx).get("kind")) != DriftChatCommands.KIND_LOCAL:
		_fail("chat_commands (=abc should report usage locally)")
		return

	# Local commands never reach the network.
	var ping: Dictionary = DriftChatCommands.parse("?ping", ctx)
	if String(ping.get("kind")) != DriftChatCommands.KIND_LOCAL or not String(ping["lines"][0]).contains("42"):
		_fail("chat_commands (?ping should report 42 ms locally)")
		return
	if not String(DriftChatCommands.parse("?status", ctx)["lines"][0]).contains("Rotation:75%"):
		_fail("chat_commands (?status should report rotation 75%)")
		return
	if not String(DriftChatCommands.parse("?flags", ctx)["lines"][0]).contains("No flags"):
		_fail("chat_commands (?flags should report the empty case)")
		return
	if not String(DriftChatCommands.parse("?team", ctx)["lines"][0]).contains("Bob (1)"):
		_fail("chat_commands (?team should list teammates)")
		return

	# Effects are described, not applied, by the parser.
	if String(DriftChatCommands.parse("?kill", ctx).get("effect")) != DriftChatCommands.EFFECT_KILL_FEED:
		_fail("chat_commands (?kill should request the kill-feed effect)")
		return
	var lines_cmd: Dictionary = DriftChatCommands.parse("?lines=99", ctx)
	if String(lines_cmd.get("effect")) != DriftChatCommands.EFFECT_CHAT_LINES or int(lines_cmd.get("value")) != DriftChatCommands.CHAT_LINES_MAX:
		_fail("chat_commands (?lines=99 should clamp to the maximum)")
		return
	var ign: Dictionary = DriftChatCommands.parse("?ignore Bob", ctx)
	if String(ign.get("effect")) != DriftChatCommands.EFFECT_IGNORE or String(ign.get("value")) != "Bob":
		_fail("chat_commands (?ignore Bob should target Bob)")
		return

	# Unknown ? commands fall through to public chat, as in SubSpace.
	var unknown: Dictionary = DriftChatCommands.parse("?wat is this", ctx)
	if String(unknown.get("kind")) != DriftChatCommands.KIND_SEND or String(unknown.get("text")) != "?wat is this":
		_fail("chat_commands (unknown ? command should be sent as chat)")
		return
	_pass("chat_commands")


func _test_chat_macros() -> void:
	_ran += 1
	var ctx: Dictionary = {
		"name": "Rodvik", "coord": "H11", "area": "upper left", "freq": 7,
		"bounty": 15, "energy": 900, "flags": 2, "shield_s": 3.0, "super_s": 0.0,
		"killer": "Marx", "killed": "Luxor",
		"red_name": "Zed", "red_flags": 3, "red_bounty": 88,
	}
	var out: String = DriftChatCommands.expand_macros("I am %selfname at %coord (%area) on freq %freq", ctx)
	if out != "I am Rodvik at H11 (upper left) on freq 7":
		_fail("chat_macros (basic expansion got '%s')" % out)
		return

	# %redname must not be eaten by the shorter %red token.
	if DriftChatCommands.expand_macros("%redname/%redflags/%redbounty", ctx) != "Zed/3/88":
		_fail("chat_macros (longer red tokens must win over %red)")
		return
	if not DriftChatCommands.expand_macros("%red", ctx).contains("Zed (3 flags, 88 bty)"):
		_fail("chat_macros (%red should summarise the carrier)")
		return

	# %% is the literal-percent escape and must not expand what follows it.
	if DriftChatCommands.expand_macros("100%%coord done", ctx) != "100%coord done":
		_fail("chat_macros (%% should escape, got '%s')" % DriftChatCommands.expand_macros("100%%coord done", ctx))
		return
	if DriftChatCommands.expand_macros("%killer beat %killed", ctx) != "Marx beat Luxor":
		_fail("chat_macros (killer/killed expansion)")
		return

	# Nine-region %area labels.
	if DriftChatCommands.area_label(Vector2(0.5, 0.5)) != "center":
		_fail("chat_macros (area centre)")
		return
	if DriftChatCommands.area_label(Vector2(0.9, 0.1)) != "upper right":
		_fail("chat_macros (area upper right)")
		return
	if DriftChatCommands.area_label(Vector2(0.5, 0.9)) != "lower":
		_fail("chat_macros (area lower, got '%s')" % DriftChatCommands.area_label(Vector2(0.5, 0.9)))
		return
	_pass("chat_macros")


func _test_special_negative_prizes() -> void:
	# Screen Items.pdf's three special negatives: Engine Shutdown, Engine Shutdown
	# Severe and Energy Depleted. Glue is the cfg name for the Engine Shutdown prize.
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(500, 500))
	var s1 = world.ships.get(1)
	world.engine_shutdown_time_ticks = 420  # EngineShutdownTime=700 cs -> 7 s

	world._apply_prize_effect(s1, DriftTypes.PrizeKind.Glue, false, 0)
	if int(s1.engine_shutdown_until_tick) != 420:
		_fail("negative_prizes (Glue should shut the engine down for 420 ticks, got %d)" % int(s1.engine_shutdown_until_tick))
		return

	world._apply_prize_effect(s1, DriftTypes.PrizeKind.Glue, true, 0)
	if int(s1.engine_shutdown_until_tick) != DriftWorld.ENGINE_SHUTDOWN_SEVERE_TICKS:
		_fail("negative_prizes (severe Glue should last %d ticks, got %d)" % [
			DriftWorld.ENGINE_SHUTDOWN_SEVERE_TICKS, int(s1.engine_shutdown_until_tick)])
		return

	# Energy Depleted takes all of it, not half.
	s1.energy_current = int(s1.energy_max)
	world._apply_prize_effect(s1, DriftTypes.PrizeKind.QuickCharge, true, 0)
	if int(s1.energy_current) != 0:
		_fail("negative_prizes (Energy Depleted should empty the bar, got %d)" % int(s1.energy_current))
		return
	world._apply_prize_effect(s1, DriftTypes.PrizeKind.QuickCharge, false, 0)
	if int(s1.energy_current) != int(s1.energy_max):
		_fail("negative_prizes (Full Charge should refill, got %d/%d)" % [int(s1.energy_current), int(s1.energy_max)])
		return
	_pass("special_negative_prizes")


func _test_insert_spawn_warp() -> void:
	## Insert with no Warp charge and no portal beacon jumps you back to a spawn point,
	## but only at full energy, and it costs the whole bar.
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, Vector2(900.0, 900.0))
	var s1 = world.ships.get(1)
	s1.warp_count = 0
	s1.energy_max = 1000
	s1.energy_current = 1000

	# Not at full energy: refused.
	s1.energy_current = 700
	var away: Vector2 = s1.position
	if world._use_spawn_warp(s1):
		_fail("spawn_warp (should refuse below full energy)")
		return
	if s1.position != away:
		_fail("spawn_warp (moved the ship despite refusing)")
		return

	# Full energy: warps and drains.
	s1.energy_current = 1000
	if not world._use_spawn_warp(s1):
		_fail("spawn_warp (should warp at full energy)")
		return
	if s1.position == away:
		_fail("spawn_warp (did not move the ship)")
		return
	if int(s1.energy_current) != 0:
		_fail("spawn_warp (should cost the full bar, left %d)" % int(s1.energy_current))
		return

	# A live portal beacon means Shift+Insert owns the key; Insert must not jump home.
	s1.energy_current = 1000
	s1.portal_until_tick = world.tick + 600
	var here: Vector2 = s1.position
	if world._use_spawn_warp(s1):
		_fail("spawn_warp (should defer to an active portal beacon)")
		return
	if s1.position != here:
		_fail("spawn_warp (moved while a beacon was down)")
		return
	_pass("insert_spawn_warp")


func _test_default_keybindings_match_original_layout() -> void:
	## Pins the shipped defaults to the SubSpace 1.34 layout documented in the README
	## and original_content/controls.txt. Every entry is (action, physical key, shift).
	_ran += 1
	var Actions = load("res://client/input/actions.gd")
	var expected: Array = [
		["drift_thrust_forward", KEY_UP, false],
		["drift_thrust_reverse", KEY_DOWN, false],
		["drift_rotate_left", KEY_LEFT, false],
		["drift_rotate_right", KEY_RIGHT, false],
		["drift_fire_primary", KEY_CTRL, false],
		["drift_item_repel", KEY_CTRL, true],
		["drift_fire_secondary", KEY_TAB, false],
		["drift_lay_mine", KEY_TAB, true],
		["drift_ability_stealth", KEY_HOME, false],
		["drift_ability_cloak", KEY_HOME, true],
		["drift_ability_xradar", KEY_END, false],
		["drift_ability_antiwarp", KEY_END, true],
		["drift_toggle_multifire", KEY_DELETE, false],
		["drift_item_burst", KEY_DELETE, true],
		["drift_item_warp", KEY_INSERT, false],
		["drift_item_portal", KEY_INSERT, true],
		["drift_item_rocket", KEY_F3, false],
		["drift_item_brick", KEY_F4, false],
		["drift_item_decoy", KEY_F5, false],
		["drift_item_thor", KEY_F6, false],
	]
	for row in expected:
		var action: String = String(row[0])
		var want_key: int = int(row[1])
		var want_shift: bool = bool(row[2])
		if not Actions.REBINDABLE_ACTIONS.has(action):
			_fail("keybindings (%s missing from REBINDABLE_ACTIONS, so it can never be rebound)" % action)
			return
		var evs_any: Variant = Actions.DEFAULT_BINDINGS.get(action, [])
		if typeof(evs_any) != TYPE_ARRAY or (evs_any as Array).is_empty():
			_fail("keybindings (%s has no default binding)" % action)
			return
		var ev: InputEventKey = (evs_any as Array)[0]
		var got_key: int = int(ev.physical_keycode) if int(ev.physical_keycode) != 0 else int(ev.keycode)
		if got_key != want_key or bool(ev.shift_pressed) != want_shift:
			_fail("keybindings (%s bound to key %d shift=%s, expected key %d shift=%s)" % [
				action, got_key, str(ev.shift_pressed), want_key, str(want_shift)])
			return
	# Every rebindable action needs a label, or the Options menu shows a raw id.
	for a in Actions.REBINDABLE_ACTIONS:
		if not Actions.ACTION_LABELS.has(a):
			_fail("keybindings (%s has no ACTION_LABELS entry)" % String(a))
			return
	_pass("default_keybindings_match_original_layout")


func _bounce_world_with_wall(wall_x: int) -> DriftWorld:
	## Uses the *shipped* rulesets/base.json rather than the code defaults, so this
	## pins what a player actually feels, not just the fallback constants.
	var world := DriftWorld.new()
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://rulesets/base.json"))
	if typeof(raw) == TYPE_DICTIONARY:
		var valid: Dictionary = DriftValidate.validate_ruleset(raw)
		if bool(valid.get("ok", false)):
			world.apply_ruleset(valid.get("ruleset", raw))
	world.set_map_dimensions(80, 60)
	var solids: Array = []
	for y in range(0, 60):
		solids.append([wall_x, y, 0, 0])
	world.set_solid_tiles(solids)
	return world


func _test_ship_wall_bounce_feel() -> void:
	## Wall contact used to feel sticky for two reasons, both pinned here:
	## a 160 px/s dead zone that deleted the normal component instead of bouncing
	## (so anything but a fast head-on hit was a dead stop), and tangential damping
	## applied per contact tick (so you could not slide along a wall).
	_ran += 1
	var wall_x: int = 20
	var tile: int = int(DriftWorld.TILE_SIZE)
	var wall_px: float = float(wall_x * tile)
	var idle: Dictionary = {}

	# --- Glancing hit: mostly parallel, slight push into the wall. The along-wall
	# component must survive, otherwise the ship glues to the surface.
	var w1 := _bounce_world_with_wall(wall_x)
	w1.add_ship(1, Vector2(wall_px - 40.0, 300.0))
	var s1 = w1.ships[1]
	s1.velocity = Vector2(60.0, 200.0)  # 200 px/s along the wall, 60 into it
	var along_before: float = s1.velocity.y
	for _i in range(40):
		w1.step_tick(idle, false, 0)
	# Drag is the only thing that should have eaten the slide; allow for it generously.
	if s1.velocity.y < along_before * 0.5:
		_fail("wall_bounce (glancing hit killed the slide: %.1f -> %.1f)" % [along_before, s1.velocity.y])
		return
	if absf(s1.velocity.y) < 1.0:
		_fail("wall_bounce (ship stuck to the wall, along-wall speed %.2f)" % s1.velocity.y)
		return

	# --- Head-on hit at a speed that used to fall inside the dead zone. It must
	# actually reverse, not stop.
	var w2 := _bounce_world_with_wall(wall_x)
	w2.add_ship(1, Vector2(wall_px - 40.0, 300.0))
	var s2 = w2.ships[1]
	s2.velocity = Vector2(100.0, 0.0)  # well under the old 160 threshold
	var hit: bool = false
	for _j in range(60):
		w2.step_tick(idle, false, 0)
		if s2.velocity.x < 0.0:
			hit = true
			break
	if not hit:
		_fail("wall_bounce (a 100 px/s head-on hit did not reverse; dead zone is back)")
		return

	# --- Restitution mirrors the original Misc:BounceFactor (16 = no speed loss),
	# so a bounce should not bleed speed off the normal.
	if w2.wall_restitution < 1.0:
		_fail("wall_bounce (wall_restitution %.3f loses speed; original ships 22/16)" % w2.wall_restitution)
		return

	# --- A ship overlapping geometry keeps its velocity so it can thrust free.
	var w3 := _bounce_world_with_wall(wall_x)
	w3.add_ship(1, Vector2(wall_px + float(tile) * 0.5, 300.0))  # inside the wall
	var s3 = w3.ships[1]
	s3.velocity = Vector2(-150.0, 0.0)
	w3.step_tick(idle, false, 0)
	if is_equal_approx(s3.velocity.x, 0.0):
		_fail("wall_bounce (overlapping ship had its velocity zeroed and is stranded)")
		return
	_pass("ship_wall_bounce_feel")


func _test_music_library_loads() -> void:
	## Every file in the music folder must actually load as an AudioStream with real
	## audio in it. A missing .import or a corrupt ogg fails silently at runtime -- the
	## game just goes quiet -- so it gets pinned here instead.
	_ran += 1
	var Jukebox = load("res://client/audio/music_jukebox.gd")
	var paths: PackedStringArray = Jukebox.scan_music_paths()
	if paths.is_empty():
		_fail("music_library (no tracks found in res://client/audio/music/)")
		return

	# The scan must agree with what is on disk, so a newly dropped-in track cannot be
	# silently skipped because nobody ran --import.
	var on_disk: Array[String] = []
	var dir := DirAccess.open("res://client/audio/music/")
	if dir != null:
		dir.list_dir_begin()
		var fn: String = dir.get_next()
		while fn != "":
			if not dir.current_is_dir() and (fn.ends_with(".ogg") or fn.ends_with(".wav") or fn.ends_with(".mp3")):
				on_disk.append(fn)
			fn = dir.get_next()
		dir.list_dir_end()
	if on_disk.size() > 0 and paths.size() != on_disk.size():
		_fail("music_library (scan found %d tracks but %d audio files are on disk -- run --import)" % [paths.size(), on_disk.size()])
		return

	var bad: Array[String] = []
	var silent: Array[String] = []
	for p in paths:
		var stream = load(p)
		if not (stream is AudioStream):
			bad.append(p.get_file())
			continue
		if float((stream as AudioStream).get_length()) <= 0.0:
			silent.append(p.get_file())
	if not bad.is_empty():
		_fail("music_library (%d unplayable: %s)" % [bad.size(), ", ".join(bad)])
		return
	if not silent.is_empty():
		_fail("music_library (%d zero-length: %s)" % [silent.size(), ", ".join(silent)])
		return
	# The jukebox must queue up every track it scanned. Playback itself needs a live
	# scene tree, so this stops at playlist construction rather than calling play().
	var jb: Node = Jukebox.new()
	jb._build_playlist()
	if jb._playlist.size() != paths.size():
		_fail("music_library (jukebox queued %d of %d tracks)" % [jb._playlist.size(), paths.size()])
		jb.free(); return
	jb.free()

	print("[SMOKE]   music: %d tracks playable" % paths.size())
	_pass("music_library_loads")


func _test_map_editor_undo_and_tools() -> void:
	## Drives the editor's edit primitives directly. Covers the undo/redo stack and the
	## line/flood-fill/eyedropper tools, which are the parts most likely to break silently.
	_ran += 1
	var packed = load("res://client/scenes/editor/MapEditor.tscn")
	if packed == null:
		_fail("map_editor (MapEditor.tscn failed to load)")
		return
	var ed = (packed as PackedScene).instantiate()
	root.add_child(ed)
	# _initialize() runs before the tree starts processing, so _ready() has not fired yet.
	# Drive it once by hand; the null tileset meta is the reliable signal it is pending.
	if ed._tileset_meta == null:
		ed._ready()

	var layer: String = String(ed._selected_dest_layer())
	var a := Vector2i(10, 10)
	var b := Vector2i(14, 10)

	# A single place is one undo step and is exactly reversible.
	var before: Vector2i = ed._cell_atlas(layer, a)
	ed._place_tile_at(a)
	if ed._cell_atlas(layer, a) != ed.selected_atlas_coords:
		_fail("map_editor (place did not write the selected tile)")
		ed.queue_free(); return
	if ed._undo_stack.size() != 1:
		_fail("map_editor (place should push exactly one undo op, got %d)" % ed._undo_stack.size())
		ed.queue_free(); return
	ed._undo()
	if ed._cell_atlas(layer, a) != before:
		_fail("map_editor (undo did not restore the previous tile)")
		ed.queue_free(); return
	ed._redo()
	if ed._cell_atlas(layer, a) != ed.selected_atlas_coords:
		_fail("map_editor (redo did not reapply the tile)")
		ed.queue_free(); return

	# A rect fill is also one undo step, however many cells it touched.
	var ops_before: int = ed._undo_stack.size()
	ed._fill_rect(Vector2i(20, 20), Vector2i(24, 24), false)
	if ed._undo_stack.size() != ops_before + 1:
		_fail("map_editor (rect fill should be a single undo op)")
		ed.queue_free(); return
	if ed._cell_atlas(layer, Vector2i(22, 22)) != ed.selected_atlas_coords:
		_fail("map_editor (rect fill did not paint its interior)")
		ed.queue_free(); return
	ed._undo()
	if ed._cell_atlas(layer, Vector2i(22, 22)) == ed.selected_atlas_coords:
		_fail("map_editor (undo did not clear the rect fill)")
		ed.queue_free(); return

	# Line tool paints both endpoints and the cells between them.
	ed._draw_line_cells(a, b)
	for x in range(a.x, b.x + 1):
		if ed._cell_atlas(layer, Vector2i(x, a.y)) != ed.selected_atlas_coords:
			_fail("map_editor (line missed cell %d,%d)" % [x, a.y])
			ed.queue_free(); return
	ed._undo()

	# A new edit must drop the redo stack (no branching history).
	ed._place_tile_at(Vector2i(30, 30))
	if not ed._redo_stack.is_empty():
		_fail("map_editor (a fresh edit should clear the redo stack)")
		ed.queue_free(); return

	# Eyedropper adopts the tile under the cursor.
	ed.selected_atlas_coords = Vector2i(0, 0)
	ed.cursor_cell = Vector2i(30, 30)
	ed._pick_tile_under_cursor()
	if ed._cell_atlas(ed._selected_dest_layer(), Vector2i(30, 30)) == ed.NO_TILE:
		_fail("map_editor (eyedropper test cell is empty)")
		ed.queue_free(); return

	# Loading/creating a document clears history rather than leaving stale diffs.
	ed._create_new_map(ed.map_width_tiles, ed.map_height_tiles)
	if not ed._undo_stack.is_empty() or not ed._redo_stack.is_empty():
		_fail("map_editor (new map should clear undo history)")
		ed.queue_free(); return

	ed.queue_free()
	_pass("map_editor_undo_and_tools")


func _classic_world_with_all_ships() -> DriftWorld:
	var registry := DriftShipRegistry.new()
	if not registry.load_all_specs():
		return null
	var world = DriftWorld.new()
	world.set_map_dimensions(200, 200)
	world.set_all_ship_specs(registry.specs)
	for t in range(8):
		world.add_ship(t + 1, Vector2(200.0 + float(t) * 200.0, 200.0), t)
	return world


func _test_ship_starting_loadouts() -> void:
	## Pins each ship's spawn loadout to the original server.cfg. Ship order:
	## 0 Warbird 1 Javelin 2 Spider 3 Leviathan 4 Terrier 5 Weasel 6 Lancaster 7 Shark.
	_ran += 1
	var world = _classic_world_with_all_ships()
	if world == null:
		_fail("ship_loadouts (registry load failed)")
		return

	# InitialGuns / InitialBombs: only the Terrier starts above gun level 1, only the
	# Leviathan and Weasel start with a bomb.
	var expect_gun: Array[int] = [1, 1, 1, 1, 2, 1, 1, 1]
	var expect_bomb: Array[int] = [0, 0, 0, 1, 0, 1, 0, 0]
	for t in range(8):
		var s: DriftTypes.DriftShipState = world.ships[t + 1]
		if int(s.gun_level) != expect_gun[t]:
			_fail("ship_loadouts (ship %d gun_level %d, expected %d)" % [t, int(s.gun_level), expect_gun[t]])
			return
		# bomb_level is clamped to >=1 in state; 0 in cfg means "no bombs yet".
		if expect_bomb[t] == 1 and int(s.bomb_level) < 1:
			_fail("ship_loadouts (ship %d should start with a bomb)" % t)
			return

	# InitialDecoy: the Spider is the only ship that spawns with an item.
	for t in range(8):
		var s2: DriftTypes.DriftShipState = world.ships[t + 1]
		var expect_decoy: int = 1 if t == 2 else 0
		if int(s2.decoy_count) != expect_decoy:
			_fail("ship_loadouts (ship %d decoy_count %d, expected %d)" % [t, int(s2.decoy_count), expect_decoy])
			return
		for field in [s2.repel_count, s2.burst_count, s2.thor_count, s2.brick_count, s2.rocket_count, s2.portal_count]:
			if int(field) != 0:
				_fail("ship_loadouts (ship %d should spawn with no items but decoy)" % t)
				return

	# CloakStatus: only the Spider (2) and Shark (7) may ever cloak, and neither owns it
	# at spawn -- Status=1 means it has to be prized. StealthStatus=2 on the Spider is
	# the one ability anyone starts with.
	for t in range(8):
		var s3: DriftTypes.DriftShipState = world.ships[t + 1]
		if bool(s3.has_cloak):
			_fail("ship_loadouts (ship %d must not own cloak at spawn)" % t)
			return
		var expect_stealth: bool = (t == 2)
		if bool(s3.has_stealth) != expect_stealth:
			_fail("ship_loadouts (ship %d has_stealth=%s, expected %s)" % [t, str(s3.has_stealth), str(expect_stealth)])
			return
		if bool(s3.has_xradar) or bool(s3.has_antiwarp):
			_fail("ship_loadouts (ship %d must prize xradar/antiwarp)" % t)
			return

	# MaxBombs: the Leviathan is the only ship that reaches level 3 bombs.
	for t in range(8):
		var s4: DriftTypes.DriftShipState = world.ships[t + 1]
		for _i in range(6):
			world._apply_prize_effect(s4, DriftTypes.PrizeKind.Bomb, false, 0)
		var expect_max_bomb: int = 3 if t == 3 else 2
		if int(s4.bomb_level) != expect_max_bomb:
			_fail("ship_loadouts (ship %d maxed bomb_level %d, expected %d)" % [t, int(s4.bomb_level), expect_max_bomb])
			return
	_pass("ship_starting_loadouts")


func _test_ability_ownership_and_item_caps() -> void:
	_ran += 1
	var world = _classic_world_with_all_ships()
	if world == null:
		_fail("ability_ownership (registry load failed)")
		return
	var warbird: DriftTypes.DriftShipState = world.ships[1]
	var spider: DriftTypes.DriftShipState = world.ships[3]

	# CloakStatus=0 on the Warbird: the prize must not grant it.
	world._apply_prize_effect(warbird, DriftTypes.PrizeKind.Cloak, false, 0)
	if bool(warbird.has_cloak) or bool(warbird.cloak_on):
		_fail("ability_ownership (Warbird has CloakStatus=0 and must never cloak)")
		return
	# CloakStatus=1 on the Spider: the prize grants and switches it on.
	world._apply_prize_effect(spider, DriftTypes.PrizeKind.Cloak, false, 0)
	if not (bool(spider.has_cloak) and bool(spider.cloak_on)):
		_fail("ability_ownership (Cloak prize should grant the Spider its cloak)")
		return
	# A negative roll takes a Status=1 ability away again...
	world._apply_prize_effect(spider, DriftTypes.PrizeKind.Cloak, true, 0)
	if bool(spider.has_cloak):
		_fail("ability_ownership (negative Cloak should revoke a prized ability)")
		return
	# ...but never a Status=2 one. The Spider's stealth is start-with.
	world._apply_prize_effect(spider, DriftTypes.PrizeKind.Stealth, true, 0)
	if not bool(spider.has_stealth):
		_fail("ability_ownership (StealthStatus=2 must survive a negative prize)")
		return

	# Item counts cap at the per-ship *Max (3 for every ship in the original cfg),
	# not the old hardcoded 10.
	for kind in [DriftTypes.PrizeKind.Decoy, DriftTypes.PrizeKind.Thor,
			DriftTypes.PrizeKind.Brick, DriftTypes.PrizeKind.Rocket,
			DriftTypes.PrizeKind.Repel, DriftTypes.PrizeKind.Burst,
			DriftTypes.PrizeKind.Portal]:
		for _i in range(12):
			world._apply_prize_effect(warbird, kind, false, 0)
	for pair in [[warbird.decoy_count, "decoy"], [warbird.thor_count, "thor"],
			[warbird.brick_count, "brick"], [warbird.rocket_count, "rocket"],
			[warbird.repel_count, "repel"], [warbird.burst_count, "burst"],
			[warbird.portal_count, "portal"]]:
		if int(pair[0]) != 3:
			_fail("ability_ownership (%s capped at %d, expected 3)" % [String(pair[1]), int(pair[0])])
			return

	# ShrapnelMax=0 on the Weasel: EMP bombs never throw shrapnel, however many prizes.
	var weasel: DriftTypes.DriftShipState = world.ships[6]
	for _j in range(10):
		world._apply_prize_effect(weasel, DriftTypes.PrizeKind.Shrapnel, false, 0)
	if int(weasel.shrapnel_bonus) != 0:
		_fail("ability_ownership (Weasel ShrapnelMax=0 but got %d)" % int(weasel.shrapnel_bonus))
		return
	# Everyone else gains ShrapnelRate=2 per prize up to ShrapnelMax=8.
	for _k in range(10):
		world._apply_prize_effect(warbird, DriftTypes.PrizeKind.Shrapnel, false, 0)
	if int(warbird.shrapnel_bonus) != 8:
		_fail("ability_ownership (Warbird shrapnel capped at %d, expected 8)" % int(warbird.shrapnel_bonus))
		return
	_pass("ability_ownership_and_item_caps")


func _test_king_of_the_hill() -> void:
	# [King] semantics per SSOS_Help.txt L1556-1572.
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.configure_king({
		"enabled": true,
		"expire_ticks": 100,
		"death_count": 0,
		"noncrown_adjust_ticks": 60,
		"noncrown_min_bounty": 10,
		"crown_recover_kills": 2,
	})
	world.add_ship(1, Vector2(400, 400))
	world.add_ship(2, Vector2(900, 900))
	world.add_ship(3, Vector2(1400, 1400))
	world.start_king_round()
	var a = world.ships.get(1)
	var b = world.ships.get(2)
	var c = world.ships.get(3)
	if world.king_crown_holders().size() != 3:
		_fail("king (everyone should start a round crowned)")
		return

	# The crown clock ticks down while alive.
	var idle: Dictionary = {}
	for _i in range(10):
		world.step_tick(idle, false, 0)
	if int(a.crown_ticks_left) != 90:
		_fail("king (crown clock should be 90 after 10 ticks, got %d)" % int(a.crown_ticks_left))
		return

	# Killing an uncrowned player with enough bounty buys crown time.
	b.crown_on = false
	b.bounty = 50
	var before: int = int(a.crown_ticks_left)
	world._king_on_kill(a, b, int(b.bounty))
	if int(a.crown_ticks_left) != before + 60:
		_fail("king (NonCrownAdjustTime should add 60 ticks, got %d)" % (int(a.crown_ticks_left) - before))
		return
	# ...but not when they were worth less than NonCrownMinimumBounty.
	before = int(a.crown_ticks_left)
	world._king_on_kill(a, b, 5)
	if int(a.crown_ticks_left) != before:
		_fail("king (a cheap kill must not add crown time)")
		return

	# DeathCount=0 means one death loses the crown.
	world._king_on_kill(a, c, int(c.bounty))
	if bool(c.crown_on):
		_fail("king (DeathCount=0 should strip the crown on first death)")
		return

	# Two crown kills win an uncrowned player their crown back.
	b.crown_kills = 0
	world._king_on_kill(b, a, int(a.bounty))
	if bool(b.crown_on):
		_fail("king (one crown kill is not enough with CrownRecoverKills=2)")
		return
	a.crown_on = true
	world._king_on_kill(b, a, int(a.bounty))
	if not bool(b.crown_on) or int(b.crown_ticks_left) != 100:
		_fail("king (second crown kill should restore a full crown)")
		return

	# The clock expiring removes the crown.
	c.crown_on = true
	c.crown_ticks_left = 2
	for _j in range(3):
		world.step_tick(idle, false, 0)
	if bool(c.crown_on) or int(c.crown_ticks_left) != 0:
		_fail("king (crown should expire at zero)")
		return
	_pass("king_of_the_hill")


func _test_ball_gated_on_goal_entities() -> void:
	# The powerball only exists on soccer maps; otherwise it was an invisible
	# gun-disabling trap parked at map centre.
	_ran += 1
	var world = DriftWorld.new()
	world.set_map_dimensions(80, 60)
	world.add_ship(1, world.arena_center)
	var idle: Dictionary = {}
	world.step_tick(idle, false, 0)
	if int(world.ball.owner_id) == 1:
		_fail("ball_gated (a ship on a non-soccer map must not pick up a ball)")
		return

	world.set_ball_enabled(true)
	world.ball.position = world.ships[1].position
	world.step_tick(idle, false, 0)
	if int(world.ball.owner_id) != 1:
		_fail("ball_gated (with goals present the ball should be pickable, owner=%d)" % int(world.ball.owner_id))
		return
	_pass("ball_gated_on_goal_entities")


func _pass(name: String) -> void:
	print("[SMOKE] PASS ", name)


func _fail(msg: String) -> void:
	_failures += 1
	print("[SMOKE] FAIL ", msg)
