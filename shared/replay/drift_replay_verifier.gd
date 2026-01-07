## Driftline replay verifier
##
## Replays a JSONL recording into a provided DriftWorld and asserts per-tick
## world hashes match.

class_name DriftReplayVerifier
extends RefCounted

const DriftTypes = preload("res://shared/drift_types.gd")
const DriftInput = preload("res://shared/drift_input.gd")
const DriftReplayReader = preload("res://shared/replay/drift_replay_reader.gd")


func verify(path: String, world, initial_setup: Callable, on_desync: Callable = Callable()) -> Dictionary:
	var reader := DriftReplayReader.new()
	var res: Dictionary = reader.load_jsonl(path)
	if not bool(res.get("ok", false)):
		var out := {
			"ok": false,
			"error": "load failed: %s (line=%s)" % [str(res.get("error", "unknown")), str(res.get("line", "?"))],
		}
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
			if on_desync != null and on_desync.is_valid():
				on_desync.call("replay_verifier_mismatch", {"error": String(out.get("error", "")), "mismatch": {}, "path": String(path)})
			return out
		var rec: Dictionary = rec_any
		var t: int = int(rec.get("t", -1))
		var expected_hash: int = int(rec.get("hash", 0))
		var inputs_d_any: Variant = rec.get("inputs", {})
		if typeof(inputs_d_any) != TYPE_DICTIONARY:
			var out := {"ok": false, "error": "tick inputs not dict", "mismatch": {"t": t}}
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
			_print_tiny_ship_dump(world)
			var out := {
				"ok": false,
				"error": "hash mismatch",
				"mismatch": {"t": t, "expected": expected_hash, "actual": actual_hash},
			}
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
			if on_desync != null and on_desync.is_valid():
				on_desync.call("replay_verifier_mismatch", {"error": String(out.get("error", "")), "mismatch": out.get("mismatch", {}), "path": String(path)})
			return out

	return {"ok": true}


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


static func _print_tiny_ship_dump(world) -> void:
	# Deterministic and small: sorted IDs, at most first 2.
	if world == null:
		return
	if not (world.ships is Dictionary):
		return
	var ids: Array = world.ships.keys()
	ids.sort()
	var limit: int = mini(2, ids.size())
	for i in range(limit):
		var sid: int = int(ids[i])
		var s: DriftTypes.DriftShipState = world.ships.get(sid)
		if s == null:
			continue
		print("[REPLAY_VERIFY] ship id=", sid, " pos=", s.position, " vel=", s.velocity, " rot=", s.rotation)


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
