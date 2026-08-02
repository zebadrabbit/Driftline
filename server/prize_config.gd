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
# Game-mode profiles hold only the keys that differ from res://server.cfg, mirroring the
# per-arena SERVER.CFG deltas the original shipped (WAR, CHAOS, KING, ...).
const MODE_DIR: String = "res://modes/"


static func mode_path_for(mode_name: String) -> String:
	var m: String = String(mode_name).strip_edges().to_lower()
	if m.is_empty():
		return ""
	return "%s%s.cfg" % [MODE_DIR, m]


static func _seconds_to_ticks(seconds_value: float) -> int:
	return int(round(float(seconds_value) / DriftConstants.TICK_DT))


static func _layered_get_value(user_cfg: ConfigFile, has_user: bool, res_cfg: ConfigFile, has_res: bool, section: String, key: String, default_value: Variant, mode_cfg: ConfigFile = null) -> Variant:
	# Priority: user:// > mode profile > res:// > default.
	if has_user and user_cfg.has_section_key(section, key):
		return user_cfg.get_value(section, key, default_value)
	if mode_cfg != null and mode_cfg.has_section_key(section, key):
		return mode_cfg.get_value(section, key, default_value)
	if has_res and res_cfg.has_section_key(section, key):
		return res_cfg.get_value(section, key, default_value)
	return default_value


static func _load_mode_cfg(user_cfg: ConfigFile, has_user: bool, res_cfg: ConfigFile, has_res: bool) -> ConfigFile:
	## Resolves [Game] Mode to res://modes/<mode>.cfg. Returns null when unset or absent.
	var mode_name: String = String(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Game", "Mode", ""))
	var path: String = mode_path_for(mode_name)
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		push_warning("[PrizeConfig] Failed to load mode profile: %s" % path)
		return null
	return cfg


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

	var mode_cfg: ConfigFile = _load_mode_cfg(user_cfg, has_user, res_cfg, has_res)

	# [Prize] section defaults (seconds + tiles).
	var prize_delay_s: float = float(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "PrizeDelay", 0.0, mode_cfg))
	var prize_hide_count: int = int(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "PrizeHideCount", 0, mode_cfg))
	var min_virtual: int = int(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "MinimumVirtual", 0, mode_cfg))
	var upgrade_virtual: int = int(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "UpgradeVirtual", 0, mode_cfg))
	var prize_min_exist_s: float = float(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "PrizeMinExist", 0.0, mode_cfg))
	var prize_max_exist_s: float = float(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "PrizeMaxExist", 0.0, mode_cfg))
	var prize_negative_factor: int = int(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "PrizeNegativeFactor", 0, mode_cfg))
	var death_prize_time_s: float = float(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "DeathPrizeTime", 0.0, mode_cfg))
	var multi_prize_count: int = int(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "MultiPrizeCount", 0, mode_cfg))
	var engine_shutdown_time_s: float = float(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Prize", "EngineShutdownTime", 0.0, mode_cfg))

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
		var w: int = int(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "PrizeWeight", key, 0, mode_cfg))
		if w < 0:
			w = 0
		weights_by_kind[key] = w

	# [King] -- King of the Hill. Times are seconds here (original used centiseconds).
	var king_enabled: bool = bool(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "King", "Enabled", false, mode_cfg))
	var king := {
		"enabled": king_enabled,
		"expire_ticks": _seconds_to_ticks(float(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "King", "ExpireTime", 0.0, mode_cfg))),
		"death_count": maxi(0, int(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "King", "DeathCount", 0, mode_cfg))),
		"noncrown_adjust_ticks": _seconds_to_ticks(float(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "King", "NonCrownAdjustTime", 0.0, mode_cfg))),
		"noncrown_min_bounty": maxi(0, int(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "King", "NonCrownMinimumBounty", 0, mode_cfg))),
		"crown_recover_kills": maxi(0, int(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "King", "CrownRecoverKills", 0, mode_cfg))),
		"reward_factor": maxi(0, int(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "King", "RewardFactor", 0, mode_cfg))),
	}

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
		"mode": String(_layered_get_value(user_cfg, has_user, res_cfg, has_res, "Game", "Mode", "")),
		"mode_applied": mode_cfg != null,
		"king": king,
		"prize": canonical,
		"weights": weights_by_kind,
	}
