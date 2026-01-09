## Client-only bug report writer.
##
## Goal:
## - Save last ~30s replay ring buffer (records) + metadata into a shareable artifact.
## - Prefer writing under res://.ci_artifacts (CI/workspace), but fall back to user:// if res:// is not writable.
## - Optionally zip the folder into a single .zip file.
##
## Determinism: must never touch shared sim/network state.

class_name BugReportWriter
extends RefCounted


static func save_bug_report(reason: String, meta: Dictionary, records: Array, mismatch: Dictionary, opts: Dictionary = {}) -> Dictionary:
	# Returns { ok: bool, folder: String, zip: String, error: String }
	var out := {"ok": false, "folder": "", "zip": "", "error": ""}
	var safe_reason: String = _sanitize_component(reason)
	if safe_reason == "":
		safe_reason = "unknown"

	var stamp: String = _timestamp_for_path()
	var folder_name: String = "%s_%s" % [stamp, safe_reason]

	var prefer_root: String = String(opts.get("root", "res://.ci_artifacts/bugreports"))
	var fallback_root: String = String(opts.get("fallback_root", "user://.ci_artifacts/bugreports"))

	var root: String = _pick_writable_root(prefer_root, fallback_root)
	if root == "":
		out.error = "no writable root"
		return out

	var folder_res: String = root.rstrip("/") + "/" + folder_name
	var folder_abs: String = ProjectSettings.globalize_path(folder_res)
	var mk_err := DirAccess.make_dir_recursive_absolute(folder_abs)
	if mk_err != OK:
		out.error = "failed to create folder (err=%d)" % int(mk_err)
		return out

	# Write files.
	var meta_path := folder_res + "/meta.json"
	var mismatch_path := folder_res + "/mismatch.json"
	var replay_path := folder_res + "/replay.jsonl"

	if not _write_text_atomic(meta_path, JSON.stringify(_canonicalize(meta), "\t") + "\n"):
		out.error = "failed to write meta.json"
		return out
	if not _write_text_atomic(mismatch_path, JSON.stringify(_canonicalize(mismatch), "\t") + "\n"):
		out.error = "failed to write mismatch.json"
		return out
	if not _write_replay_jsonl_atomic(replay_path, records):
		out.error = "failed to write replay.jsonl"
		return out

	out.folder = folder_res

	# Zip (best-effort).
	var zip_enabled: bool = bool(opts.get("zip", true))
	var force_no_zip: bool = bool(opts.get("no_zip", false))
	if force_no_zip:
		zip_enabled = false
	var cleanup_after_zip: bool = bool(opts.get("bugreport_cleanup_after_zip", false))
	var zip_force_fail: bool = bool(opts.get("zip_force_fail", false))

	if zip_enabled:
		var zip_path: String = folder_res + ".zip"
		var zip_ok: bool = false
		if zip_force_fail:
			zip_ok = false
		else:
			zip_ok = _zip_folder_best_effort(folder_abs, ProjectSettings.globalize_path(zip_path))
		if zip_ok:
			out.zip = zip_path
			if cleanup_after_zip:
				var del_ok: bool = _delete_dir_recursive_absolute(folder_abs)
				if not del_ok:
					# Consistent cross-platform behavior: failure to delete is non-fatal.
					push_warning("[BugReportWriter] cleanup_after_zip enabled but delete failed; keeping folder: %s" % folder_abs)
				else:
					out["folder_deleted"] = true
		else:
			# Leave folder as the artifact.
			out.zip = ""

	out.ok = true
	return out


static func _delete_dir_recursive_absolute(dir_abs: String) -> bool:
	# Best-effort recursive delete. Returns true only if the directory is fully removed.
	# If any file/dir fails, return false and leave remaining content.
	var d := DirAccess.open(dir_abs)
	if d == null:
		# If it doesn't exist, consider it deleted.
		return true

	# Delete children first.
	for fn in d.get_files():
		var file_abs: String = String(dir_abs).path_join(String(fn))
		var err_f: Error = DirAccess.remove_absolute(file_abs)
		if err_f != OK:
			push_warning("[BugReportWriter] failed to delete file err=%d path=%s" % [int(err_f), file_abs])
			return false

	for dn in d.get_directories():
		var child_abs: String = String(dir_abs).path_join(String(dn))
		if not _delete_dir_recursive_absolute(child_abs):
			return false

	# Delete this directory.
	var err_d: Error = DirAccess.remove_absolute(dir_abs)
	if err_d != OK:
		push_warning("[BugReportWriter] failed to delete dir err=%d path=%s" % [int(err_d), dir_abs])
		return false
	return true


static func _pick_writable_root(prefer: String, fallback: String) -> String:
	# Prefer res://.ci_artifacts when writable (CI/workspace). If unavailable (export), use user://.
	if _can_create_dir(prefer):
		return prefer
	if _can_create_dir(fallback):
		return fallback
	return ""


static func _can_create_dir(path_res: String) -> bool:
	if path_res == "":
		return false
	var abs: String = ProjectSettings.globalize_path(path_res)
	var err := DirAccess.make_dir_recursive_absolute(abs)
	return err == OK


static func _zip_folder_best_effort(folder_abs: String, zip_abs: String) -> bool:
	# Best-effort zip implementation.
	# If zip fails for any reason, return false (caller keeps folder).
	#
	# NOTE: ZipPacker is available in Godot 4.x. On some export templates it may fail.
	var zp := ZIPPacker.new()
	var err := zp.open(zip_abs)
	if err != OK:
		push_warning("[BugReportWriter] zip open failed err=%d path=%s" % [int(err), zip_abs])
		return false

	var ok: bool = _zip_add_dir_recursive(zp, folder_abs, folder_abs)
	zp.close()
	return ok


static func _zip_add_dir_recursive(zp: ZIPPacker, root_abs: String, cur_abs: String) -> bool:
	var d := DirAccess.open(cur_abs)
	if d == null:
		push_warning("[BugReportWriter] zip dir open failed: " + cur_abs)
		return false
	var files: PackedStringArray = d.get_files()
	for fn in files:
		var file_abs: String = cur_abs.rstrip("/") + "/" + String(fn)
		var rel: String = file_abs.substr(root_abs.length())
		if rel.begins_with("/") or rel.begins_with("\\"):
			rel = rel.substr(1)
		# Zip format wants forward slashes.
		rel = rel.replace("\\", "/")
		var f := FileAccess.open(file_abs, FileAccess.READ)
		if f == null:
			push_warning("[BugReportWriter] zip file open failed: " + file_abs)
			return false
		var n: int = int(f.get_length())
		var buf: PackedByteArray = f.get_buffer(n)
		f.close()
		var err_sf := zp.start_file(rel)
		if err_sf != OK:
			push_warning("[BugReportWriter] zip start_file failed err=%d file=%s" % [int(err_sf), rel])
			return false
		zp.write_file(buf)
		zp.close_file()

	var dirs: PackedStringArray = d.get_directories()
	for dn in dirs:
		var next_abs: String = cur_abs.rstrip("/") + "/" + String(dn)
		if not _zip_add_dir_recursive(zp, root_abs, next_abs):
			return false

	return true


static func _write_replay_jsonl_atomic(path: String, records: Array) -> bool:
	var tmp_path: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("[BugReportWriter] Failed to open %s for writing" % tmp_path)
		return false

	for rec_any in records:
		if typeof(rec_any) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_any
		var t: int = int(rec.get("t", 0))
		var inputs: Variant = rec.get("inputs", [])
		var inputs_json: String = JSON.stringify(inputs)
		f.store_string("{\"t\":%d,\"inputs\":%s}\n" % [t, inputs_json])

	f.flush()
	f.close()
	return _rename_overwrite_tmp(tmp_path, path)


static func _write_text_atomic(path: String, text: String) -> bool:
	var tmp_path: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("[BugReportWriter] Failed to open %s for writing" % tmp_path)
		return false
	f.store_string(text)
	f.flush()
	f.close()
	return _rename_overwrite_tmp(tmp_path, path)


static func _rename_overwrite_tmp(tmp_path: String, final_path: String) -> bool:
	var abs_tmp: String = ProjectSettings.globalize_path(tmp_path)
	var abs_final: String = ProjectSettings.globalize_path(final_path)

	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(abs_final)

	var err: Error = DirAccess.rename_absolute(abs_tmp, abs_final)
	if err == OK:
		return true

	# Fallback: attempt direct write if rename fails.
	push_warning("[BugReportWriter] rename failed (err=%d), falling back to direct write: %s" % [int(err), final_path])
	var rf: FileAccess = FileAccess.open(final_path, FileAccess.WRITE)
	if rf == null:
		push_error("[BugReportWriter] Failed to open %s for direct write" % final_path)
		return false
	var tf: FileAccess = FileAccess.open(tmp_path, FileAccess.READ)
	if tf == null:
		push_error("[BugReportWriter] Failed to open %s for fallback read" % tmp_path)
		rf.close()
		return false
	rf.store_string(tf.get_as_text())
	rf.flush()
	rf.close()
	tf.close()
	return true


static func _timestamp_for_path() -> String:
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
	var clean: String = ""
	for i in range(out.length()):
		var ch := out[i]
		var ok := false
		var code := ch.unicode_at(0)
		if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
			ok = true
		elif ch == "_" or ch == "-" or ch == ".":
			ok = true
		if ok:
			clean += ch
		elif ch == " " or ch == "/" or ch == "\\" or ch == ":":
			clean += "_"
	if clean.length() > 64:
		clean = clean.substr(0, 64)
	return clean


static func _canonicalize(v: Variant) -> Variant:
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
