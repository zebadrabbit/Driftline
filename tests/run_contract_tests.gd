## Headless contract tests for Driftline JSON schemas.
##
## Run:
##   godot --headless --quit --script res://tests/run_contract_tests.gd

# This runner enforces the Testing Policy in docs/testing.md
# valid_* MUST pass, invalid_* MUST fail. No exceptions.


extends SceneTree

const DriftValidate = preload("res://shared/drift_validate.gd")

const ROOT_DIR := "res://tests/contracts"

var _failures: int = 0
var _ran: int = 0


func _initialize() -> void:
	var files := _discover_json_files(ROOT_DIR)
	files.sort()

	if files.is_empty():
		print("[TEST] No contract vectors found under ", ROOT_DIR)
		_finish(1)
		return

	for path in files:
		_run_one(path)

	print("[TEST] Done: ", _ran, " checks, ", _failures, " failures")
	_finish(0 if _failures == 0 else 1)


func _discover_json_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		print("[TEST] FAIL could not open dir: ", dir_path)
		_failures += 1
		return out

	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if name.begins_with("."):
			continue
		var child := dir_path.path_join(name)
		if dir.current_is_dir():
			var nested := _discover_json_files(child)
			for p in nested:
				out.append(p)
		else:
			if name.to_lower().ends_with(".json"):
				out.append(child)

	dir.list_dir_end()
	return out


func _run_one(path: String) -> void:
	var filename := path.get_file()
	var expect_ok := false
	var expect_fail := false
	if filename.begins_with("valid_"):
		expect_ok = true
	elif filename.begins_with("invalid_"):
		expect_fail = true
	else:
		# Not a test vector by naming convention.
		return

	_ran += 1

	var json_str := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(json_str)
	if parsed == null:
		if expect_ok:
			_fail("%s (parse error)" % filename)
		else:
			_pass(filename)
		return

	if typeof(parsed) != TYPE_DICTIONARY:
		if expect_ok:
			_fail("%s (expected object)" % filename)
		else:
			_pass(filename)
		return

	var root: Dictionary = parsed

	# Dispatch based on the immediate contract folder.
	var rel := path.replace("res://tests/contracts/", "")
	var contract := rel.split("/", false, 1)[0]
	if contract == "server_config":
		var res := DriftValidate.validate_server_config_dict(root)
		_assert_expectation(filename, bool(res.get("ok", false)), String(res.get("error", "")), expect_ok)
		return
	if contract == "map":
		var res := DriftValidate.validate_map_dict(root)
		_assert_expectation(filename, bool(res.get("ok", false)), String(res.get("error", "")), expect_ok)
		return
	if contract == "tiles_def":
		var res := DriftValidate.validate_tiles_def_dict(root)
		_assert_expectation(filename, bool(res.get("ok", false)), String(res.get("error", "")), expect_ok)
		return
	if contract == "ruleset":
		var res := DriftValidate.validate_ruleset_dict(root)
		_assert_expectation(filename, bool(res.get("ok", false)), String(res.get("error", "")), expect_ok)
		return

	_fail("%s (unknown contract folder '%s' for %s)" % [filename, contract, rel])


func _assert_expectation(filename: String, got_ok: bool, error_text: String, expect_ok: bool) -> void:
	if expect_ok and got_ok:
		_pass(filename)
		return
	if (not expect_ok) and (not got_ok):
		_pass(filename)
		return

	if expect_ok and not got_ok:
		_fail("%s (expected ok, got error: %s)" % [filename, error_text.replace("\n", " ")])
	else:
		_fail("%s (expected fail, got ok)" % filename)


func _pass(filename: String) -> void:
	print("[TEST] PASS ", filename)


func _fail(msg: String) -> void:
	_failures += 1
	print("[TEST] FAIL ", msg)


func _finish(exit_code: int) -> void:
	# Some Godot builds expose process-exit helpers under different names.
	# Use dynamic calls to avoid parse-time errors on older builds.
	var code := int(exit_code)
	if OS.has_method("set_exit_code"):
		OS.call("set_exit_code", code)
	elif OS.has_method("set_process_exit_code"):
		OS.call("set_process_exit_code", code)
	quit(code)
