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

var _failures: int = 0
var _ran: int = 0


func _initialize() -> void:
	_test_welcome_includes_ruleset_payload()
	print("[SMOKE] Done: ", _ran, " checks, ", _failures, " failures")
	quit(0 if _failures == 0 else 1)


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


func _pass(name: String) -> void:
	print("[SMOKE] PASS ", name)


func _fail(msg: String) -> void:
	_failures += 1
	print("[SMOKE] FAIL ", msg)
