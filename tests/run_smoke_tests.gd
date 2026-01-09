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
	print("[SMOKE] Done: ", _ran, " checks, ", _failures, " failures")
	quit(0 if _failures == 0 else 1)


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
		var di1 := DriftInput.new(0, 0, fire_now, false, false, false)
		var di2 := DriftInput.new(0, 0, false, false, false, false)
		var cmd1 := DriftTypes.DriftInputCmd.new(float(di1.thrust), float(di1.turn), bool(di1.fire), bool(di1.bomb), bool(di1.afterburner))
		var cmd2 := DriftTypes.DriftInputCmd.new(float(di2.thrust), float(di2.turn), bool(di2.fire), bool(di2.bomb), bool(di2.afterburner))
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
		var di := DriftInput.new(1 if (t % 10) < 5 else 0, 0, (t % 15) == 0, false, false, false)
		if t % 5 == 0:
			di = DriftInput.new(0, 0, false, false, false, false)
		var cmd := DriftTypes.DriftInputCmd.new(float(di.thrust), float(di.turn), bool(di.fire), bool(di.bomb), bool(di.afterburner))
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
		var di := DriftInput.new(1 if (t % 10) < 5 else 0, 0, (t % 15) == 0, false, false, false)
		if t % 5 == 0:
			di = DriftInput.new(0, 0, false, false, false, false)
		var cmd := DriftTypes.DriftInputCmd.new(float(di.thrust), float(di.turn), bool(di.fire), bool(di.bomb), bool(di.afterburner))
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
		var di := DriftInput.new(1 if (t % 10) < 5 else 0, 0, (t % 15) == 0, false, false, false)
		if t % 5 == 0:
			di = DriftInput.new(0, 0, false, false, false, false)
		var cmd := DriftTypes.DriftInputCmd.new(float(di.thrust), float(di.turn), bool(di.fire), bool(di.bomb), bool(di.afterburner))
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
			(t % 20) < 5,
			(t % 120) == 7
		)
		var di2 := DriftInput.new(
			1 if (t % 50) < 25 else 0,
			1 if (t % 30) < 15 else -1,
			(t % 17) == 0,
			(t % 80) == 3,
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
			false
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
			false
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


func _make_world_for_classic_ship_spec(spec: Dictionary) -> DriftWorld:
	var world := DriftWorld.new()
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
	world.add_ship(1, Vector2(2048, 2048))
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

	if wb_spawn_ticks != [0, 25]:
		_fail("classic_wb_vs_tr (expected Warbird spawn ticks [0,25], got %s)" % [str(wb_spawn_ticks)])
		return
	if tr_spawn_ticks != [0]:
		_fail("classic_wb_vs_tr (expected Terrier spawn ticks [0], got %s)" % [str(tr_spawn_ticks)])
		return

	if int(wb_world.bullets.size()) != wb_spawn_ticks.size() or int(tr_world.bullets.size()) != tr_spawn_ticks.size():
		_fail("classic_wb_vs_tr (bullet count mismatch with spawn ticks)")
		return

	# next_bullet_tick should reflect the last fire.
	if int(wb_ship.next_bullet_tick) != 50:
		_fail("classic_wb_vs_tr (expected Warbird next_bullet_tick=50, got %d)" % [int(wb_ship.next_bullet_tick)])
		return
	if int(tr_ship.next_bullet_tick) != 30:
		_fail("classic_wb_vs_tr (expected Terrier next_bullet_tick=30, got %d)" % [int(tr_ship.next_bullet_tick)])
		return

	# Total energy spent differs due to cooldown (recharge disabled above).
	var wb_spent := wb_init - int(wb_ship.energy_current)
	var tr_spent := tr_init - int(tr_ship.energy_current)
	if wb_spent != wb_cost * wb_spawn_ticks.size():
		_fail("classic_wb_vs_tr (Warbird spent %d, expected %d)" % [wb_spent, wb_cost * wb_spawn_ticks.size()])
		return
	if tr_spent != tr_cost * tr_spawn_ticks.size():
		_fail("classic_wb_vs_tr (Terrier spent %d, expected %d)" % [tr_spent, tr_cost * tr_spawn_ticks.size()])
		return
	if wb_spent <= tr_spent:
		_fail("classic_wb_vs_tr (expected Warbird to spend more energy over %d ticks)" % [SIM_TICKS])
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


func _pass(name: String) -> void:
	print("[SMOKE] PASS ", name)


func _fail(msg: String) -> void:
	_failures += 1
	print("[SMOKE] FAIL ", msg)
