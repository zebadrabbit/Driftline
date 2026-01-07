## Client-only replay dump writer.
##
## Writes a bugreport bundle under:
##   user://replays/bugreports/<timestamp>_<reason>/
##
## Files:
## - meta.json (pretty)
## - replay.jsonl (one JSON object per line)
## - mismatch.json (pretty)
##
## Never throws; returns "" on failure.

class_name ReplayDumpWriter
extends RefCounted


static func write_bugreport(folder: String, meta: Dictionary, records: Array, mismatch: Dictionary) -> String:
	var reason: String = _sanitize_component(folder)
	if reason == "":
		reason = "unknown"

	var stamp: String = _timestamp_for_path()
	var base_dir: String = "user://replays/bugreports/%s_%s" % [stamp, reason]

	var abs_dir: String = ProjectSettings.globalize_path(base_dir)
	var mk_err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if mk_err != OK:
		push_error("[ReplayDumpWriter] Failed to create dir %s (err=%d)" % [abs_dir, int(mk_err)])
		return ""

	# meta.json (pretty + canonical ordering)
	var meta_path: String = "%s/meta.json" % base_dir
	var meta_text: String = JSON.stringify(_canonicalize(meta), "\t") + "\n"
	if not _write_text_atomic(meta_path, meta_text):
		push_error("[ReplayDumpWriter] Failed to write meta.json")
		return ""

	# mismatch.json (pretty + canonical ordering)
	var mismatch_path: String = "%s/mismatch.json" % base_dir
	var mismatch_text: String = JSON.stringify(_canonicalize(mismatch), "\t") + "\n"
	if not _write_text_atomic(mismatch_path, mismatch_text):
		push_error("[ReplayDumpWriter] Failed to write mismatch.json")
		return ""

	# replay.jsonl (stable per-line object keys)
	var replay_path: String = "%s/replay.jsonl" % base_dir
	if not _write_replay_jsonl_atomic(replay_path, records):
		push_error("[ReplayDumpWriter] Failed to write replay.jsonl")
		return ""

	return base_dir


static func _write_replay_jsonl_atomic(path: String, records: Array) -> bool:
	# Write to temp, then rename.
	var tmp_path: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("[ReplayDumpWriter] Failed to open %s for writing" % tmp_path)
		return false

	for rec_any in records:
		# Expect minimal schema: {"t": int, "inputs": Array}
		if typeof(rec_any) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_any
		var t: int = int(rec.get("t", 0))
		var inputs: Variant = rec.get("inputs", [])
		# Stable JSON object key order: t then inputs.
		var inputs_json: String = JSON.stringify(inputs)
		f.store_string("{\"t\":%d,\"inputs\":%s}\n" % [t, inputs_json])

	f.flush()
	f.close()

	return _rename_overwrite_tmp(tmp_path, path)


static func _write_text_atomic(path: String, text: String) -> bool:
	var tmp_path: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("[ReplayDumpWriter] Failed to open %s for writing" % tmp_path)
		return false
	f.store_string(text)
	f.flush()
	f.close()

	return _rename_overwrite_tmp(tmp_path, path)


static func _rename_overwrite_tmp(tmp_path: String, final_path: String) -> bool:
	# Best-effort atomic replace: remove final if present, rename tmp over it.
	var abs_tmp: String = ProjectSettings.globalize_path(tmp_path)
	var abs_final: String = ProjectSettings.globalize_path(final_path)

	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(abs_final)

	var err: Error = DirAccess.rename_absolute(abs_tmp, abs_final)
	if err == OK:
		return true

	# Fallback: attempt direct write if rename fails.
	push_warning("[ReplayDumpWriter] rename failed (err=%d), falling back to direct write: %s" % [int(err), final_path])
	var rf: FileAccess = FileAccess.open(final_path, FileAccess.WRITE)
	if rf == null:
		push_error("[ReplayDumpWriter] Failed to open %s for direct write" % final_path)
		return false
	var tf: FileAccess = FileAccess.open(tmp_path, FileAccess.READ)
	if tf == null:
		push_error("[ReplayDumpWriter] Failed to open %s for fallback read" % tmp_path)
		rf.close()
		return false
	rf.store_string(tf.get_as_text())
	rf.flush()
	rf.close()
	tf.close()
	return true


static func _timestamp_for_path() -> String:
	# Windows-safe timestamp: YYYYMMDD_HHMMSS_mmm
	var d: Dictionary = Time.get_datetime_dict_from_system()
	var ms: int = int(Time.get_ticks_msec() % 1000)
	return "%04d%02d%02d_%02d%02d%02d_%03d" % [
		int(d.get("year", 0)),
		int(d.get("month", 0)),
		int(d.get("day", 0)),
		int(d.get("hour", 0)),
		int(d.get("minute", 0)),
		int(d.get("second", 0)),
		ms,
	]


static func _sanitize_component(s: String) -> String:
	var out := String(s).strip_edges()
	if out == "":
		return ""
	# Keep only safe filename characters.
	var clean: String = ""
	for i in range(out.length()):
		var ch := out[i]
		var ok := false
		# a-z A-Z 0-9 _ - .
		var code := ch.unicode_at(0)
		if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
			ok = true
		elif ch == "_" or ch == "-" or ch == ".":
			ok = true
		if ok:
			clean += ch
		elif ch == " " or ch == "/" or ch == "\\" or ch == ":":
			clean += "_"
	# Limit length to keep paths reasonable.
	if clean.length() > 64:
		clean = clean.substr(0, 64)
	return clean


static func _canonicalize(v: Variant) -> Variant:
	# Recursively sort dictionary keys for stable serialization.
	var t := typeof(v)
	if t == TYPE_DICTIONARY:
		var d: Dictionary = Dictionary(v)
		var keys: Array = d.keys()
		keys.sort()
		var out: Dictionary = {}
		for k_any in keys:
			var k: String = str(k_any)
			out[k] = _canonicalize(d[k_any])
		return out
	if t == TYPE_ARRAY:
		var arr: Array = Array(v)
		var out_arr: Array = []
		out_arr.resize(arr.size())
		for i in range(arr.size()):
			out_arr[i] = _canonicalize(arr[i])
		return out_arr
	return v
