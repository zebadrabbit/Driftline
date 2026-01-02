## Server prize configuration loader (server.cfg)
##
## Loads user://server.cfg first, then res://server.cfg.
##
## Notes:
## - server.cfg is treated as config input (not a versioned JSON contract).
## - Unknown keys are ignored (cfg is not a contract), but missing keys use defaults.

class_name DriftPrizeConfig

const DriftConstants = preload("res://shared/drift_constants.gd")
const DriftTypes = preload("res://shared/drift_types.gd")

const USER_PATH: String = "user://server.cfg"
const RES_PATH: String = "res://server.cfg"


static func _seconds_to_ticks(seconds_value: float) -> int:
	return int(round(float(seconds_value) / DriftConstants.TICK_DT))


static func _layered_get_value(user_cfg: ConfigFile, has_user: bool, res_cfg: ConfigFile, has_res: bool, section: String, key: String, default_value: Variant) -> Variant:
	if has_user and user_cfg.has_section_key(section, key):
		return user_cfg.get_value(section, key, default_value)
	if has_res and res_cfg.has_section_key(section, key):
		return res_cfg.get_value(section, key, default_value)
	return default_value


static func load_config() -> Dictionary:
	# Layering behavior:
	# - res://server.cfg provides defaults
	# - user://server.cfg overrides keys it defines
	# This prevents an incomplete user config from disabling prizes.
	var res_cfg := ConfigFile.new()
	var user_cfg := ConfigFile.new()
	var loaded_any: bool = false
	var loaded_paths: Array[String] = []
	var has_res: bool = FileAccess.file_exists(RES_PATH)
	var has_user: bool = FileAccess.file_exists(USER_PATH)
	if has_res:
		var err_res := res_cfg.load(RES_PATH)
		if err_res != OK:
			return {
				"ok": false,
				"error": "Failed to load server.cfg: %s (err=%d)" % [RES_PATH, err_res],
				"path": RES_PATH,
			}
		loaded_any = true
		loaded_paths.append(RES_PATH)
	if has_user:
		var err_user := user_cfg.load(USER_PATH)
		if err_user != OK:
			return {
				"ok": false,
				"error": "Failed to load server.cfg: %s (err=%d)" % [USER_PATH, err_user],
				"path": USER_PATH,
			}
		loaded_any = true
		loaded_paths.append(USER_PATH)
	if not loaded_any:
		return {
			"ok": false,
			"error": "server.cfg not found (looked in user:// and res://)",
			"paths": PackedStringArray([USER_PATH, RES_PATH]),
		}

	var used_path: String = (USER_PATH if has_user else RES_PATH)

	# [Prize] section defaults (seconds + tiles).
	var prize_delay_s: float = float(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "PrizeDelay", 0.0))
	var prize_hide_count: int = int(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "PrizeHideCount", 0))
	var min_virtual: int = int(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "MinimumVirtual", 0))
	var upgrade_virtual: int = int(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "UpgradeVirtual", 0))
	var prize_min_exist_s: float = float(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "PrizeMinExist", 0.0))
	var prize_max_exist_s: float = float(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "PrizeMaxExist", 0.0))
	var prize_negative_factor: int = int(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "PrizeNegativeFactor", 0))
	var death_prize_time_s: float = float(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "DeathPrizeTime", 0.0))
	var multi_prize_count: int = int(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "MultiPrizeCount", 0))
	var engine_shutdown_time_s: float = float(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "EngineShutdownTime", 0.0))

	# Convert times to ticks once.
	var prize_delay_ticks: int = _seconds_to_ticks(prize_delay_s)
	var prize_min_exist_ticks: int = _seconds_to_ticks(prize_min_exist_s)
	var prize_max_exist_ticks: int = _seconds_to_ticks(prize_max_exist_s)
	var death_prize_time_ticks: int = _seconds_to_ticks(death_prize_time_s)
	var engine_shutdown_time_ticks: int = _seconds_to_ticks(engine_shutdown_time_s)

	# Clamp/sanitize.
	prize_hide_count = clampi(prize_hide_count, 0, 256)
	prize_negative_factor = maxi(0, prize_negative_factor)
	multi_prize_count = clampi(multi_prize_count, 0, 16)
	prize_delay_ticks = maxi(0, prize_delay_ticks)
	prize_min_exist_ticks = maxi(0, prize_min_exist_ticks)
	prize_max_exist_ticks = maxi(prize_min_exist_ticks, prize_max_exist_ticks)
	death_prize_time_ticks = maxi(0, death_prize_time_ticks)
	engine_shutdown_time_ticks = maxi(0, engine_shutdown_time_ticks)

	# [PrizeWeight]
	var weights_by_kind: Dictionary = {}
	var keys_in_order: Array[String] = DriftTypes.prize_kind_keys_in_order()
	for key in keys_in_order:
		var w: int = int(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "PrizeWeight", key, 0))
		if w < 0:
			w = 0
		weights_by_kind[key] = w

	var canonical := {
		"prize_delay_ticks": prize_delay_ticks,
		"prize_hide_count": prize_hide_count,
		"minimum_virtual": min_virtual,
		"upgrade_virtual": upgrade_virtual,
		"prize_min_exist_ticks": prize_min_exist_ticks,
		"prize_max_exist_ticks": prize_max_exist_ticks,
		"prize_negative_factor": prize_negative_factor,
		"death_prize_time_ticks": death_prize_time_ticks,
		"multi_prize_count": multi_prize_count,
		"engine_shutdown_time_ticks": engine_shutdown_time_ticks,
	}

	return {
		"ok": true,
		"path": used_path,
		"paths": loaded_paths,
		"prize": canonical,
		"weights": weights_by_kind,
	}
