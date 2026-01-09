## Driftline replay verifier
##
## Replays a JSONL recording into a provided DriftWorld and asserts per-tick
## world hashes match.

class_name DriftReplayVerifier
extends RefCounted

const DriftTypes = preload("res://shared/drift_types.gd")
const DriftInput = preload("res://shared/drift_input.gd")
const DriftReplayReader = preload("res://shared/replay/drift_replay_reader.gd")


func verify(path: String, world, initial_setup: Callable, on_desync: Callable = Callable(), opts: Dictionary = {}) -> Dictionary:
	var reader := DriftReplayReader.new()
	var res: Dictionary = reader.load_jsonl(path)
	if not bool(res.get("ok", false)):
		var out := {
			"ok": false,
			"error": "load failed: %s (line=%s)" % [str(res.get("error", "unknown")), str(res.get("line", "?"))],
		}
		_maybe_write_artifact(out, path, opts)
		if on_desync != null and on_desync.is_valid():
			on_desync.call("replay_verifier_load_failed", {"path": String(path), "error": String(out.get("error", ""))})
		return out

	var header: Dictionary = res.get("header", {})
	var ticks: Array = res.get("ticks", [])
	if world == null:
		return {"ok": false, "error": "world is null"}
	if initial_setup == null or not initial_setup.is_valid():
		return {"ok": false, "error": "initial_setup is invalid"}

	initial_setup.call(world, header)

	for rec_any in ticks:
		if typeof(rec_any) != TYPE_DICTIONARY:
			var out := {"ok": false, "error": "tick record not dict"}
			_maybe_write_artifact(out, path, opts)
			if on_desync != null and on_desync.is_valid():
				on_desync.call("replay_verifier_mismatch", {"error": String(out.get("error", "")), "mismatch": {}, "path": String(path)})
			return out
		var rec: Dictionary = rec_any
		var t: int = int(rec.get("t", -1))
		var expected_hash: int = int(rec.get("hash", 0))
		var inputs_d_any: Variant = rec.get("inputs", {})
		if typeof(inputs_d_any) != TYPE_DICTIONARY:
			var out := {"ok": false, "error": "tick inputs not dict", "mismatch": {"t": t}}
			_maybe_write_artifact(out, path, opts)
			if on_desync != null and on_desync.is_valid():
				on_desync.call("replay_verifier_mismatch", {"error": String(out.get("error", "")), "mismatch": out.get("mismatch", {}), "path": String(path)})
			return out
		var inputs_d: Dictionary = inputs_d_any

		# Replay contract: record tick BEFORE step; hash is computed AFTER step.
		if int(world.tick) != t:
			var out := {
				"ok": false,
				"error": "tick mismatch",
				"mismatch": {"at": t, "world_tick": int(world.tick)},
			}
			_maybe_write_artifact(out, path, opts)
			if on_desync != null and on_desync.is_valid():
				on_desync.call("replay_verifier_mismatch", {"error": String(out.get("error", "")), "mismatch": out.get("mismatch", {}), "path": String(path)})
			return out

		# Build deterministic input payload (DriftInput) keyed by int ship_id.
		var inputs_by_id: Dictionary = {}
		var ids: Array = _sorted_ship_ids_from_json_keys(inputs_d)
		for sid in ids:
			var key_s: String = str(int(sid))
			var v: Variant = inputs_d.get(key_s)
			var norm_res: Dictionary = _normalize_drift_input_variant(v, key_s)
			if not bool(norm_res.get("ok", false)):
				var out := {
					"ok": false,
					"error": "invalid input payload",
					"mismatch": {"t": t, "ship_id": int(sid), "field": key_s, "reason": str(norm_res.get("error", ""))},
				}
				_maybe_write_artifact(out, path, opts)
				if on_desync != null and on_desync.is_valid():
					on_desync.call("replay_verifier_mismatch", {"error": String(out.get("error", "")), "mismatch": out.get("mismatch", {}), "path": String(path)})
				return out
			var d_norm: Dictionary = norm_res.get("dict", {})
			var di = DriftInput.from_dict(d_norm)
			if di == null:
				var out := {
					"ok": false,
					"error": "invalid input payload",
					"mismatch": {"t": t, "ship_id": int(sid), "reason": "from_dict returned null"},
				}
				_maybe_write_artifact(out, path, opts)
				if on_desync != null and on_desync.is_valid():
					on_desync.call("replay_verifier_mismatch", {"error": String(out.get("error", "")), "mismatch": out.get("mismatch", {}), "path": String(path)})
				return out
			inputs_by_id[int(sid)] = di

		# Convert to sim command type for stepping.
		var cmds: Dictionary = {}
		for sid2 in ids:
			var di2: DriftInput = inputs_by_id.get(int(sid2))
			cmds[int(sid2)] = _cmd_from_drift_input(di2)

		# Step exactly once.
		world.step_tick(cmds, false, 0)

		var actual_hash: int = int(world.compute_world_hash())
		if actual_hash != expected_hash:
			print("[REPLAY_VERIFY] hash mismatch t=", t, " expected=", expected_hash, " actual=", actual_hash)
			_print_world_dump_small(world)
			var out := {
				"ok": false,
				"error": "hash mismatch",
				"mismatch": {"t": t, "expected": expected_hash, "actual": actual_hash},
			}
			_maybe_write_artifact(out, path, opts)
			if on_desync != null and on_desync.is_valid():
				on_desync.call("replay_verifier_mismatch", {"error": String(out.get("error", "")), "mismatch": out.get("mismatch", {}), "path": String(path)})
			return out

		# Optional contract alignment check: Option A should advance tick at end.
		if int(world.tick) != (t + 1):
			var out := {
				"ok": false,
				"error": "post-step tick mismatch",
				"mismatch": {"t": t, "expected_world_tick": t + 1, "world_tick": int(world.tick)},
			}
			_maybe_write_artifact(out, path, opts)
			if on_desync != null and on_desync.is_valid():
				on_desync.call("replay_verifier_mismatch", {"error": String(out.get("error", "")), "mismatch": out.get("mismatch", {}), "path": String(path)})
			return out

	return {"ok": true}


static func _maybe_write_artifact(res: Dictionary, replay_path: String, opts: Dictionary) -> void:
	# Best-effort debug artifact emission for CI.
	# opts:
	#   - enable_artifacts: bool (default false)
	#   - artifact_root: String (default res://.ci_artifacts/replay_verify)
	#   - artifact_name: String (default replay_verify)
	if typeof(opts) != TYPE_DICTIONARY or opts.is_empty():
		return
	if not bool(opts.get("enable_artifacts", false)):
		return
	var root_res: String = String(opts.get("artifact_root", "res://.ci_artifacts/replay_verify"))
	var name: String = String(opts.get("artifact_name", "replay_verify"))
	_write_artifact_bundle(root_res, name, replay_path, res)


static func _write_artifact_bundle(root_res: String, name: String, replay_path: String, res: Dictionary) -> void:
	var ts: String = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var safe: String = _sanitize_filename(name)
	var folder_res: String = root_res.rstrip("/") + "/" + ts + "_" + safe
	var folder_abs: String = ProjectSettings.globalize_path(folder_res)

	if DirAccess.make_dir_recursive_absolute(folder_abs) != OK:
		print("[REPLAY_VERIFY] WARN failed to create artifact dir: ", folder_abs)
		return

	# Copy replay (if present).
	if FileAccess.file_exists(replay_path):
		var fin := FileAccess.open(replay_path, FileAccess.READ)
		if fin != null:
			var fout := FileAccess.open(folder_abs + "/replay.jsonl", FileAccess.WRITE)
			if fout != null:
				fout.store_buffer(fin.get_buffer(int(fin.get_length())))
			else:
				print("[REPLAY_VERIFY] WARN failed to write replay.jsonl")
		else:
			print("[REPLAY_VERIFY] WARN failed to open replay for artifact copy")
	else:
		print("[REPLAY_VERIFY] WARN replay file missing; no artifact replay copy")

	# Write summary.
	var summary: Dictionary = {
		"error": str(res.get("error", "unknown")),
		"mismatch": res.get("mismatch", {}) if typeof(res.get("mismatch", {})) == TYPE_DICTIONARY else {},
		"replay_path": replay_path,
	}
	var fs := FileAccess.open(folder_abs + "/summary.json", FileAccess.WRITE)
	if fs != null:
		fs.store_string(JSON.stringify(summary, "\t"))
	else:
		print("[REPLAY_VERIFY] WARN failed to write summary.json")

	print("[REPLAY_VERIFY] wrote artifact: ", folder_abs)


static func _sanitize_filename(s: String) -> String:
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


static func _sorted_ship_ids_from_json_keys(inputs_d: Dictionary) -> Array:
	# Deterministic: sort ship IDs ascending.
	var ids: Array = []
	for k in inputs_d.keys():
		# Keys are strings in JSON.
		ids.append(int(String(k)))
	ids.sort()
	return ids


func _cmd_from_drift_input(di: DriftInput) -> DriftTypes.DriftInputCmd:
	# Map deterministic DriftInput to sim command type.
	return DriftTypes.DriftInputCmd.new(
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


static func _normalize_drift_input_variant(v: Variant, context: String) -> Dictionary:
	# Normalize JSON-ish values into a Dictionary that DriftInput.from_dict accepts.
	# This avoids asserts from numeric JSON types (int vs float) while remaining strict.
	if typeof(v) != TYPE_DICTIONARY:
		return {"ok": false, "error": "input for %s must be object" % context}
	var d: Dictionary = v
	var out: Dictionary = {}

	if d.has("thrust"):
		var n: Variant = d.get("thrust")
		if not _is_intlike(n):
			return {"ok": false, "error": "thrust must be int"}
		out["thrust"] = _to_intlike(n)
	if d.has("turn"):
		var n2: Variant = d.get("turn")
		if not _is_intlike(n2):
			return {"ok": false, "error": "turn must be int"}
		out["turn"] = _to_intlike(n2)
	if d.has("fire"):
		if typeof(d.get("fire")) != TYPE_BOOL:
			return {"ok": false, "error": "fire must be bool"}
		out["fire"] = bool(d.get("fire"))
	if d.has("bomb"):
		if typeof(d.get("bomb")) != TYPE_BOOL:
			return {"ok": false, "error": "bomb must be bool"}
		out["bomb"] = bool(d.get("bomb"))
	if d.has("afterburner"):
		if typeof(d.get("afterburner")) != TYPE_BOOL:
			return {"ok": false, "error": "afterburner must be bool"}
		out["afterburner"] = bool(d.get("afterburner"))
	if d.has("ability1"):
		if typeof(d.get("ability1")) != TYPE_BOOL:
			return {"ok": false, "error": "ability1 must be bool"}
		out["ability1"] = bool(d.get("ability1"))

	return {"ok": true, "dict": out}


static func _qf(v: float, step: float = 0.001) -> float:
	# Quantize floats to reduce noise while staying deterministic.
	# (This is for diagnostics only; does not affect simulation.)
	return snappedf(float(v), step)


static func _qv2(v: Vector2, step: float = 0.001) -> String:
	return "(" + str(_qf(v.x, step)) + ", " + str(_qf(v.y, step)) + ")"


static func _print_world_dump_small(world) -> void:
	# Deterministic and compact dump for mismatch diagnostics.
	# Sorted IDs, stable formatting.
	if world == null:
		return
	var t: int = 0
	if "tick" in world:
		t = int(world.tick)
	print("[REPLAY_VERIFY] dump tick=", t)

	# Ships
	if world.ships is Dictionary:
		var ship_ids: Array[int] = []
		for k in (world.ships as Dictionary).keys():
			ship_ids.append(int(k))
		ship_ids.sort()
		var max_ships: int = 8
		var ship_limit: int = mini(max_ships, ship_ids.size())
		for i in range(ship_limit):
			var sid: int = int(ship_ids[i])
			var s: DriftTypes.DriftShipState = (world.ships as Dictionary).get(sid)
			if s == null:
				continue
			print(
				"[REPLAY_VERIFY] ship id=", sid,
				" pos=", _qv2(s.position),
				" vel=", _qv2(s.velocity),
				" rot=", _qf(float(s.rotation), 0.0001),
				" e=", int(s.energy_current), "/", int(s.energy_max),
				" dead_until=", int(s.dead_until_tick),
				" in_safe=", bool(s.in_safe_zone)
			)
		if ship_ids.size() > ship_limit:
			print("[REPLAY_VERIFY] ships... +", ship_ids.size() - ship_limit)

	# Bullets
	if "bullets" in world and world.bullets is Dictionary:
		var bullet_ids: Array[int] = []
		for k2 in (world.bullets as Dictionary).keys():
			bullet_ids.append(int(k2))
		bullet_ids.sort()
		var max_bullets: int = 10
		var bullet_limit: int = mini(max_bullets, bullet_ids.size())
		for j in range(bullet_limit):
			var bid: int = int(bullet_ids[j])
			var b: DriftTypes.DriftBulletState = (world.bullets as Dictionary).get(bid)
			if b == null:
				continue
			print(
				"[REPLAY_VERIFY] bullet id=", bid,
				" owner=", int(b.owner_id),
				" lvl=", int(b.level),
				" pos=", _qv2(b.position),
				" vel=", _qv2(b.velocity),
				" die=", int(b.die_tick),
				" bounces=", int(b.bounces_left)
			)
		if bullet_ids.size() > bullet_limit:
			print("[REPLAY_VERIFY] bullets... +", bullet_ids.size() - bullet_limit)


static func _is_intlike(v: Variant) -> bool:
	var t := typeof(v)
	if t == TYPE_INT:
		return true
	if t == TYPE_FLOAT:
		var f: float = float(v)
		return is_finite(f) and absf(f - round(f)) < 0.0000001
	return false


static func _to_intlike(v: Variant) -> int:
	if typeof(v) == TYPE_INT:
		return int(v)
	return int(round(float(v)))
