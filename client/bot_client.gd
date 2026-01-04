## Driftline headless bot client.
##
## Goals:
## - Connects to the authoritative server like a normal client
## - Sends tick-tagged inputs every tick
## - Maintains local prediction + snapshot reconciliation (input replay)
## - No rendering
##
## Run:
##   godot --headless --path . --script res://client/bot_client.gd

extends SceneTree

const DriftWorld = preload("res://shared/drift_world.gd")
const DriftTypes = preload("res://shared/drift_types.gd")
const DriftConstants = preload("res://shared/drift_constants.gd")
const DriftNet = preload("res://shared/drift_net.gd")
const DriftValidate = preload("res://shared/drift_validate.gd")
const DriftMapLoader = preload("res://server/map_loader.gd")
const DriftTileDefs = preload("res://shared/drift_tile_defs.gd")

const SERVER_HOST: String = "127.0.0.1"
const SERVER_PORT: int = 5000

const NET_CHANNEL: int = 1
const DEBUG_NET: bool = false

const QUIT_FLAG_PATH := "user://bot.quit"
const QUIT_POLL_INTERVAL_SECONDS: float = 0.25

const DEFAULT_SPAWN: Vector2 = Vector2(512.0, 512.0)


# --- Bot behavior tuning knobs (command-line args friendly) ---
# Note: this script runs as a headless SceneTree, so we keep configuration via
# command-line args (see _parse_user_args) rather than editor export UI.
var skill: float = 0.55 # 0..1 (higher = faster reactions + smoother aim)
var aggression: float = 0.55 # 0..1 (higher = seeks fights, fires more)
var accuracy: float = 0.55 # 0..1 (higher = less aim error)
var reaction_ms: int = 160 # ~100..250 typical
var burst_len_s: float = 0.45
var burst_pause_s: float = 0.55
var preferred_range_px: float = 340.0
var evade_chance: float = 0.15

# Safe-zone braking (bot only): reduce robotic-looking perfect fire-spam braking.
# Bots may still use fire-to-stop in safe zones, but only sometimes.
var brake_fire_cooldown_ms_min: int = 400
var brake_fire_cooldown_ms_max: int = 800
var brake_fire_speed_threshold_px_s: float = 140.0

# Bot perception (imperfect info): only update target beliefs periodically.
var perception_update_ms_min: int = 150
var perception_update_ms_max: int = 300
var target_memory_ms: int = 1100
var perception_fov_deg: float = 120.0
var perception_range_mult: float = 2.2

const LOW_ENERGY_FRAC: float = 0.18
const REENGAGE_ENERGY_FRAC: float = 0.35

const DEBUG_BOT: bool = false


enum BotState {
	SPAWN_RECOVER,
	ROAM,
	ENGAGE,
	EVADE,
	REPOSITION,
	RESET,
}


class BotBrain:
	var state: int = BotState.SPAWN_RECOVER
	var state_ticks_left: int = 0
	var target_id: int = -1
	var target_lock_ticks_left: int = 0
	var reaction_ticks_left: int = 0

	# Imperfect information: periodic perception with short memory.
	var perception := BotPerception.new()
	var personality := BotPersonality.new()

	# Occasional "social" behavior timers.
	var safe_hesitate_ticks_left: int = 0
	var circle_ticks_left: int = 0

	# Smoothed/held inputs so we don't snap.
	var turn_cmd_smoothed: float = 0.0
	var thrust_cmd_smoothed: float = 0.0

	# Burst fire state (edge-triggered pulses).
	var burst_ticks_left: int = 0
	var burst_pause_ticks_left: int = 0
	var fire_pulse_cooldown_ticks: int = 0
	# Imperfect-human timing.
	var fire_hesitation_ticks_left: int = 0
	var fire_intent_active: bool = false
	var turn_stall_ticks_left: int = 0
	# Energy-aware disengage.
	var energy_disengaged: bool = false

	# Movement flavor state.
	var orbit_dir: int = 1
	var approach_offset_rad: float = 0.0
	var feint_ticks_left: int = 0

	# Stuck/collision tracking.
	var recent_wall_bounce_ticks: int = 0
	var wall_bounce_count: int = 0

	# Safe zone behavior: pick an exit heading for a short time.
	var safe_exit_angle: float = 0.0
	var safe_exit_ticks_left: int = 0

	# Safe-zone brake-fire gating.
	var brake_fire_cooldown_ticks_left: int = 0
	var debug_brake_fire_count: int = 0

	func _reset_for_spawn() -> void:
		state = BotState.SPAWN_RECOVER
		state_ticks_left = 0
		target_id = -1
		target_lock_ticks_left = 0
		reaction_ticks_left = 0
		perception.reset()
		safe_hesitate_ticks_left = 0
		circle_ticks_left = 0
		turn_cmd_smoothed = 0.0
		thrust_cmd_smoothed = 0.0
		burst_ticks_left = 0
		burst_pause_ticks_left = 0
		fire_pulse_cooldown_ticks = 0
		fire_hesitation_ticks_left = 0
		fire_intent_active = false
		turn_stall_ticks_left = 0
		energy_disengaged = false
		orbit_dir = 1
		approach_offset_rad = 0.0
		feint_ticks_left = 0
		recent_wall_bounce_ticks = 0
		wall_bounce_count = 0
		safe_exit_angle = 0.0
		safe_exit_ticks_left = 0
		brake_fire_cooldown_ticks_left = 0
		debug_brake_fire_count = 0


func _bot_brake_use_chance() -> float:
	# Per-bot personality baseline + skill scaling.
	# (Skill represents mechanical execution; personality represents style.)
	var base: float = clampf(lerpf(0.20, 0.80, clampf(brain.personality.brake_use_chance, 0.0, 1.0)), 0.0, 1.0)
	var skill_scale: float = lerpf(0.75, 1.05, clampf(skill, 0.0, 1.0))
	return clampf(base * skill_scale, 0.0, 1.0)


class BotPersonality:
	var reaction_ms_base: int = 160
	var reaction_jitter: float = 0.25
	var aim_error_sigma: float = 0.05
	var brake_use_chance: float = 0.50
	var aggression: float = 0.55
	var disengage_low_energy_frac: float = LOW_ENERGY_FRAC
	var disengage_reengage_energy_frac: float = REENGAGE_ENERGY_FRAC
	var chase_persistence_mult: float = 1.0
	var preferred_range_mult: float = 1.0

	# "Social" behaviors.
	var safe_zone_hesitate_p: float = 0.04
	var safe_zone_hesitate_ticks_min: int = int(round(0.12 / DriftConstants.TICK_DT))
	var safe_zone_hesitate_ticks_max: int = int(round(0.35 / DriftConstants.TICK_DT))
	var circle_bias: float = 0.35
	var target_switch_indecision_p: float = 0.12
	var drop_target_indecision_p: float = 0.04


func _hash32(x: int) -> int:
	# Deterministic 32-bit mix (portable, no RNG state).
	var v: int = int(x) & 0xffffffff
	v = int(v ^ (v >> 16)) & 0xffffffff
	v = int((v * 0x7feb352d) & 0xffffffff)
	v = int(v ^ (v >> 15)) & 0xffffffff
	v = int((v * 0x846ca68b) & 0xffffffff)
	v = int(v ^ (v >> 16)) & 0xffffffff
	return v


func _u32_to_unit_float(u: int) -> float:
	return float(int(u) & 0xffffffff) / 4294967295.0


func _make_personality(bot_id: int) -> BotPersonality:
	var p := BotPersonality.new()
	var base_seed: int = _hash32(int(bot_id) ^ 0x6ac690c5)
	var r1: float = _u32_to_unit_float(_hash32(base_seed ^ 0x01))
	var r2: float = _u32_to_unit_float(_hash32(base_seed ^ 0x02))
	var r3: float = _u32_to_unit_float(_hash32(base_seed ^ 0x03))
	var r4: float = _u32_to_unit_float(_hash32(base_seed ^ 0x04))
	var r5: float = _u32_to_unit_float(_hash32(base_seed ^ 0x05))
	var r6: float = _u32_to_unit_float(_hash32(base_seed ^ 0x06))
	var r7: float = _u32_to_unit_float(_hash32(base_seed ^ 0x07))
	var r8: float = _u32_to_unit_float(_hash32(base_seed ^ 0x08))
	var r9: float = _u32_to_unit_float(_hash32(base_seed ^ 0x09))

	# Core feel.
	p.reaction_ms_base = int(round(lerpf(115.0, 250.0, r1)))
	p.reaction_jitter = clampf(lerpf(0.10, 0.45, r2), 0.0, 0.75)
	p.aim_error_sigma = clampf(lerpf(0.018, 0.090, r3), 0.0, 0.20)
	p.brake_use_chance = clampf(lerpf(0.18, 0.78, r4), 0.0, 1.0)
	p.aggression = clampf(lerpf(0.28, 0.82, r5), 0.0, 1.0)
	p.chase_persistence_mult = clampf(lerpf(0.75, 1.45, r6), 0.4, 2.0)
	p.preferred_range_mult = clampf(lerpf(0.85, 1.25, r7), 0.6, 1.6)

	# Energy discipline.
	p.disengage_low_energy_frac = clampf(lerpf(0.12, 0.24, r8), 0.05, 0.40)
	# Ensure reengage is comfortably above disengage.
	var re: float = lerpf(p.disengage_low_energy_frac + 0.10, p.disengage_low_energy_frac + 0.22, r9)
	p.disengage_reengage_energy_frac = clampf(re, 0.18, 0.60)

	# Social details (small, occasional).
	var s1: float = _u32_to_unit_float(_hash32(base_seed ^ 0xA1))
	var s2: float = _u32_to_unit_float(_hash32(base_seed ^ 0xA2))
	var s3: float = _u32_to_unit_float(_hash32(base_seed ^ 0xA3))
	var s4: float = _u32_to_unit_float(_hash32(base_seed ^ 0xA4))
	var s5: float = _u32_to_unit_float(_hash32(base_seed ^ 0xA5))
	var s6: float = _u32_to_unit_float(_hash32(base_seed ^ 0xA6))

	p.safe_zone_hesitate_p = clampf(lerpf(0.015, 0.080, s1), 0.0, 0.2)
	var hz_min: float = lerpf(0.10, 0.18, s2)
	var hz_max: float = lerpf(0.26, 0.44, s3)
	p.safe_zone_hesitate_ticks_min = maxi(1, int(round(hz_min / DriftConstants.TICK_DT)))
	p.safe_zone_hesitate_ticks_max = maxi(p.safe_zone_hesitate_ticks_min, int(round(hz_max / DriftConstants.TICK_DT)))
	p.circle_bias = clampf(lerpf(0.10, 0.80, s4), 0.0, 1.0)
	p.target_switch_indecision_p = clampf(lerpf(0.05, 0.26, s5), 0.0, 0.6)
	p.drop_target_indecision_p = clampf(lerpf(0.01, 0.08, s6), 0.0, 0.3)

	return p


func _brake_fire_cooldown_ticks() -> int:
	# Randomized cooldown (ms) to avoid a perfect cadence.
	var ms_min: int = maxi(0, int(brake_fire_cooldown_ms_min))
	var ms_max: int = maxi(ms_min, int(brake_fire_cooldown_ms_max))
	var ms: int = int(rng.randi_range(ms_min, ms_max))
	return maxi(1, int(round((float(ms) / 1000.0) / DriftConstants.TICK_DT)))


class BotPerception:
	# perceived_targets[ship_id] = {
	#   last_seen_tick: int,
	#   last_pos: Vector2,
	#   last_vel: Vector2,
	#   visible: bool,
	#   los_ok: bool,
	#   confidence: float,
	#   pursue_ticks_left: int,
	#   aim_jitter_rad: float,
	# }
	var perceived_targets: Dictionary = {}
	var update_ticks_left: int = 0
	# Optional debug counters.
	var debug_updates: int = 0
	var debug_drops_los: int = 0

	func reset() -> void:
		perceived_targets.clear()
		update_ticks_left = 0
		debug_updates = 0
		debug_drops_los = 0

	func _ms_to_ticks(ms: int) -> int:
		return maxi(0, int(round((float(maxi(0, ms)) / 1000.0) / DriftConstants.TICK_DT)))

	func _next_update_ticks(rng_local: RandomNumberGenerator, min_ms: int, max_ms: int) -> int:
		var ms_min: int = maxi(0, int(min_ms))
		var ms_max: int = maxi(ms_min, int(max_ms))
		var ms: int = int(rng_local.randi_range(ms_min, ms_max))
		return maxi(1, int(round((float(ms) / 1000.0) / DriftConstants.TICK_DT)))

	func _fov_cos_half(fov_deg: float) -> float:
		var half_rad: float = deg_to_rad(clampf(float(fov_deg), 1.0, 179.0) * 0.5)
		return cos(half_rad)

	func update(
		world_local: DriftWorld,
		self_ship: DriftTypes.DriftShipState,
		local_ship_id_value: int,
		has_map_value: bool,
		call_has_los: Callable,
		rng_local: RandomNumberGenerator,
		update_ms_min: int,
		update_ms_max: int,
		memory_ms: int,
		fov_deg: float,
		range_px: float,
		skill_value: float,
		aggression_value: float,
		chase_persistence_mult: float
	) -> void:
		var mem_ticks: int = _ms_to_ticks(memory_ms)
		if update_ticks_left > 0:
			update_ticks_left -= 1
			_prune(int(world_local.tick), mem_ticks)
			return
		update_ticks_left = _next_update_ticks(rng_local, update_ms_min, update_ms_max)
		debug_updates += 1

		var fov_cos: float = _fov_cos_half(fov_deg)
		var fwd: Vector2 = Vector2(cos(float(self_ship.rotation)), sin(float(self_ship.rotation)))

		# Mark all as not currently visible; refresh below.
		for k in perceived_targets.keys():
			var e0: Dictionary = perceived_targets.get(k, {})
			e0["visible"] = false
			perceived_targets[k] = e0

		var ids: Array = world_local.ships.keys()
		ids.sort()
		for sid in ids:
			var other_id: int = int(sid)
			if other_id == int(local_ship_id_value):
				continue
			var o: DriftTypes.DriftShipState = world_local.ships.get(other_id)
			if o == null:
				continue
			# Ignore dead targets.
			if int(o.dead_until_tick) > 0 and int(world_local.tick) < int(o.dead_until_tick):
				continue

			var delta: Vector2 = o.position - self_ship.position
			var dist: float = delta.length()
			if dist <= 0.001:
				continue
			if dist > float(range_px):
				continue
			var dir: Vector2 = delta / dist
			var in_fov: bool = fwd.dot(dir) >= fov_cos

			var had_entry: bool = perceived_targets.has(other_id)
			# Only acquire new targets when in range and in front.
			if (not in_fov) and (not had_entry):
				continue

			var los_ok: bool = true
			if bool(has_map_value):
				los_ok = bool(call_has_los.call(self_ship.position, o.position))

			# If LOS is blocked, increase uncertainty: sometimes drop.
			var conf: float = 1.0
			var aim_jitter_rad: float = 0.0
			if not los_ok:
				var drop_p: float = clampf(lerpf(0.55, 0.20, clampf(skill_value, 0.0, 1.0)), 0.0, 1.0)
				if rng_local.randf() < drop_p:
					debug_drops_los += 1
					continue
				conf = lerpf(0.35, 0.70, clampf(skill_value, 0.0, 1.0))
				aim_jitter_rad = lerpf(0.22, 0.10, clampf(skill_value, 0.0, 1.0))
			else:
				conf = 1.0
				aim_jitter_rad = lerpf(0.08, 0.02, clampf(skill_value, 0.0, 1.0))

			var entry: Dictionary = perceived_targets.get(other_id, {})
			entry["last_seen_tick"] = int(world_local.tick)
			entry["last_pos"] = o.position
			entry["last_vel"] = o.velocity
			entry["visible"] = bool(in_fov)
			entry["los_ok"] = bool(los_ok)
			entry["confidence"] = float(conf)
			entry["aim_jitter_rad"] = float(aim_jitter_rad)
			if not had_entry:
				# New acquisition: set a short "pursuit" window for when it disappears.
				var base_s: float = rng_local.randf_range(0.22, 0.55)
				var aggro_scale: float = lerpf(0.85, 1.30, clampf(aggression_value, 0.0, 1.0))
				var pers_scale: float = clampf(float(chase_persistence_mult), 0.4, 2.0)
				entry["pursue_ticks_left"] = int(round((base_s * aggro_scale * pers_scale) / DriftConstants.TICK_DT))
			perceived_targets[other_id] = entry

		_prune(int(world_local.tick), mem_ticks)

	func _prune(now_tick: int, mem_ticks: int) -> void:
		var to_remove: Array = []
		for k in perceived_targets.keys():
			var e: Dictionary = perceived_targets.get(k, {})
			var last_seen: int = int(e.get("last_seen_tick", -999999))
			if (now_tick - last_seen) > int(mem_ticks):
				to_remove.append(k)
				continue
			# Decay pursuit window when not actively visible.
			if not bool(e.get("visible", false)):
				var p: int = int(e.get("pursue_ticks_left", 0))
				if p > 0:
					p -= 1
					e["pursue_ticks_left"] = p
					perceived_targets[k] = e
		for k2 in to_remove:
			perceived_targets.erase(k2)

	func get_entry(target_id: int) -> Dictionary:
		return perceived_targets.get(int(target_id), {})

	func best_target_id(self_pos: Vector2) -> int:
		# Choose among perceived targets (not perfect world state).
		var best_id: int = -1
		var best_score: float = -1e18
		var keys: Array = perceived_targets.keys()
		keys.sort()
		for k in keys:
			var tid: int = int(k)
			var e: Dictionary = perceived_targets.get(tid, {})
			var ppos: Vector2 = e.get("last_pos", Vector2.ZERO)
			var d: float = (ppos - self_pos).length()
			var conf: float = float(e.get("confidence", 0.0))
			var visible: bool = bool(e.get("visible", false))
			var pursue_ok: bool = visible or int(e.get("pursue_ticks_left", 0)) > 0
			if not pursue_ok:
				continue
			var vis_bonus: float = 1.0 if visible else 0.55
			var score: float = (conf * 2.2 * vis_bonus) - (d * 0.002)
			if score > best_score:
				best_score = score
				best_id = tid
		return best_id

var world: DriftWorld
var accumulator_seconds: float = 0.0

var enet_peer: ENetMultiplayerPeer
var last_connection_status: int = MultiplayerPeer.CONNECTION_DISCONNECTED
var connected: bool = false

var quit_flag_path: String = QUIT_FLAG_PATH
var quit_after_seconds: float = -1.0
var runtime_seconds: float = 0.0
var shutdown_requested: bool = false

var quit_poll_accumulator_seconds: float = 0.0

var local_ship_id: int = -1

var authoritative_tick: int = -1
var authoritative_ship_state: DriftTypes.DriftShipState
var has_authoritative: bool = false

# input_history[tick] = input applied when stepping into that tick.
var input_history: Dictionary = {} # Dictionary[int, DriftTypes.DriftInputCmd]

# Wander behavior.
var rng: RandomNumberGenerator
var bot_seed: int = 1
var brain := BotBrain.new()

# Map/cache (for wall avoidance + LOS). This is not cheating: clients already have the map.
var has_map: bool = false
var map_path: String = ""
var map_checksum: PackedByteArray = PackedByteArray()


func _initialize() -> void:
	_parse_user_args()
	print("Bot soft stop: create ", quit_flag_path, " to quit")
	print("Bot soft stop path (absolute): ", ProjectSettings.globalize_path(quit_flag_path))
	if quit_after_seconds > 0.0:
		print("Bot soft stop: will quit after ", quit_after_seconds, " seconds")

	world = DriftWorld.new()

	# Determinism: do not randomize(). Seed will be finalized after welcome using
	# map checksum + assigned ship_id (stable per match).
	rng = RandomNumberGenerator.new()
	rng.seed = int(bot_seed)
	brain._reset_for_spawn()

	enet_peer = ENetMultiplayerPeer.new()
	var err: int = enet_peer.create_client(SERVER_HOST, SERVER_PORT)
	if err != OK:
		push_error("Bot failed to create ENet client (err=%d)" % err)
		quit()
		return

	last_connection_status = enet_peer.get_connection_status()

	print("Bot starting, connecting to ", SERVER_HOST, ":", SERVER_PORT)


func _finalize() -> void:
	shutdown_requested = true
	if enet_peer != null:
		enet_peer.close()
		enet_peer = null
	print("Bot shutdown complete")


func _process(delta: float) -> bool:
	if shutdown_requested:
		return false

	runtime_seconds += delta
	if quit_after_seconds > 0.0 and runtime_seconds >= quit_after_seconds:
		_request_shutdown("quit_after")
		return false

	quit_poll_accumulator_seconds += delta
	if quit_flag_path != "" and quit_poll_accumulator_seconds >= QUIT_POLL_INTERVAL_SECONDS:
		quit_poll_accumulator_seconds -= QUIT_POLL_INTERVAL_SECONDS
		if FileAccess.file_exists(quit_flag_path):
			_request_shutdown("quit_flag")
			return false

	_poll_network_packets()

	# Run fixed 60Hz ticks.
	accumulator_seconds += delta
	while accumulator_seconds >= DriftConstants.TICK_DT:
		accumulator_seconds -= DriftConstants.TICK_DT
		_step_one_tick()

	return false


func _request_shutdown(reason: String) -> void:
	if shutdown_requested:
		return
	shutdown_requested = true
	print("[BOT] shutdown requested (", reason, ")")
	if enet_peer != null:
		enet_peer.close()
		enet_peer = null
	quit(0)


func _parse_user_args() -> void:
	# User args come after `--`.
	# Supported:
	#   --quit_after=SECONDS
	#   --quit_flag=user://bot.quit
	#   --seed=INT
	#   --skill=0..1
	#   --aggression=0..1
	#   --accuracy=0..1
	#   --reaction_ms=INT
	#   --burst_len=SECONDS
	#   --burst_pause=SECONDS
	#   --preferred_range=PX
	#   --evade_chance=0..1
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for raw in args:
		var s: String = String(raw)
		if s.begins_with("--"):
			s = s.substr(2)
		if not s.contains("="):
			continue
		var parts: PackedStringArray = s.split("=", false, 2)
		if parts.size() != 2:
			continue
		var key: String = parts[0]
		var value: String = parts[1]
		if key == "quit_after":
			quit_after_seconds = float(value)
		elif key == "quit_flag":
			quit_flag_path = value
		elif key == "seed":
			bot_seed = int(value)
		elif key == "skill":
			skill = clampf(float(value), 0.0, 1.0)
		elif key == "aggression":
			aggression = clampf(float(value), 0.0, 1.0)
		elif key == "accuracy":
			accuracy = clampf(float(value), 0.0, 1.0)
		elif key == "reaction_ms":
			reaction_ms = maxi(0, int(value))
		elif key == "burst_len":
			burst_len_s = maxf(0.0, float(value))
		elif key == "burst_pause":
			burst_pause_s = maxf(0.0, float(value))
		elif key == "preferred_range":
			preferred_range_px = maxf(0.0, float(value))
		elif key == "evade_chance":
			evade_chance = clampf(float(value), 0.0, 1.0)


func _step_one_tick() -> void:
	if not connected:
		return
	if local_ship_id < 0:
		# Waiting for welcome packet.
		return

	# Ensure local ship exists (it may have been reset on reconnect).
	if not world.ships.has(local_ship_id):
		world.add_ship(local_ship_id, DEFAULT_SPAWN)

	var s: DriftTypes.DriftShipState = world.ships.get(local_ship_id)
	if s == null:
		return

	# Ensure personality is initialized after we know our bot_id.
	if brain.personality == null:
		brain.personality = _make_personality(local_ship_id)

	# Safe zones: never attack/ability in safe zone.
	# IMPORTANT: server now spawns players inside safe zones when available, so bots
	# must still move/roam to exit (they just can’t fight while safe).
	var in_safe: bool = bool(s.in_safe_zone)

	# Update "reaction" timer: bots should not instantly adapt every tick.
	if brain.reaction_ticks_left > 0:
		brain.reaction_ticks_left -= 1
	if brain.brake_fire_cooldown_ticks_left > 0:
		brain.brake_fire_cooldown_ticks_left -= 1

	# Observe collisions to detect being stuck.
	if not world.collision_events.is_empty():
		for ev in world.collision_events:
			if typeof(ev) == TYPE_DICTIONARY and int((ev as Dictionary).get("ship_id", -1)) == local_ship_id:
				brain.wall_bounce_count += 1
				brain.recent_wall_bounce_ticks = int(round(0.8 / DriftConstants.TICK_DT))
				break
	if brain.recent_wall_bounce_ticks > 0:
		brain.recent_wall_bounce_ticks -= 1
		if brain.recent_wall_bounce_ticks == 0:
			brain.wall_bounce_count = 0

	# Perception update (imperfect info): updates periodically with memory.
	# This only affects bot behavior; authoritative validation remains unchanged.
	var perception_range_px: float = maxf(0.0, preferred_range_px) * float(perception_range_mult)
	var effective_aggression: float = clampf((aggression * 0.60) + (brain.personality.aggression * 0.40), 0.0, 1.0)
	brain.perception.update(
		world,
		s,
		local_ship_id,
		has_map,
		Callable(self, "_has_line_of_sight"),
		rng,
		perception_update_ms_min,
		perception_update_ms_max,
		target_memory_ms,
		perception_fov_deg,
		perception_range_px,
		skill,
		effective_aggression,
		brain.personality.chase_persistence_mult
	)

	# Pick/maintain target.
	if in_safe or bool(brain.energy_disengaged):
		# Do not engage targets while safe.
		brain.target_id = -1
		brain.target_lock_ticks_left = 0
	else:
		var target_id := _select_target(s, brain.perception)
		if target_id != -1:
			brain.target_id = target_id
			# lock time prevents rapid swapping.
			brain.target_lock_ticks_left = maxi(brain.target_lock_ticks_left, int(round(1.2 / DriftConstants.TICK_DT)))
		elif brain.target_lock_ticks_left <= 0:
			brain.target_id = -1

		if brain.target_lock_ticks_left > 0:
			brain.target_lock_ticks_left -= 1

	# Energy discipline: if low, disengage/reset.
	var energy_now: int = int(s.energy_current)
	var low_energy: bool = (energy_now <= int(world.bullet_energy_cost) + 10)
	var energy_frac: float = float(energy_now) / float(maxi(1, int(s.energy_max)))
	var disengage_low: float = float(brain.personality.disengage_low_energy_frac)
	var disengage_re: float = float(brain.personality.disengage_reengage_energy_frac)
	if bool(brain.energy_disengaged):
		if energy_frac >= disengage_re:
			brain.energy_disengaged = false
	else:
		if energy_frac <= disengage_low:
			brain.energy_disengaged = true

	# State transitions.
	if brain.state == BotState.SPAWN_RECOVER and world.tick > 0:
		if brain.state_ticks_left <= 0:
			brain.state_ticks_left = int(round(rng.randf_range(0.25, 0.55) / DriftConstants.TICK_DT))
		if brain.state_ticks_left > 0:
			brain.state_ticks_left -= 1
			# gentle orienting
			pass
		else:
			brain.state = BotState.ROAM
	elif low_energy and brain.state != BotState.RESET:
		brain.state = BotState.RESET
		brain.state_ticks_left = int(round(rng.randf_range(0.8, 1.4) / DriftConstants.TICK_DT))
		brain.burst_ticks_left = 0
		brain.burst_pause_ticks_left = 0
		brain.fire_pulse_cooldown_ticks = 0
	elif brain.wall_bounce_count >= 3 and brain.state != BotState.RESET:
		brain.state = BotState.RESET
		brain.state_ticks_left = int(round(rng.randf_range(0.7, 1.1) / DriftConstants.TICK_DT))
	elif (not in_safe) and brain.target_id != -1 and brain.state in [BotState.ROAM, BotState.REPOSITION]:
		brain.state = BotState.ENGAGE
		brain.state_ticks_left = int(round(rng.randf_range(1.0, 2.0) / DriftConstants.TICK_DT))
		brain.approach_offset_rad = rng.randf_range(-0.9, 0.9)
		brain.orbit_dir = -1 if rng.randf() < 0.5 else 1
	elif (brain.target_id == -1 or in_safe) and brain.state == BotState.ENGAGE:
		brain.state = BotState.ROAM
		brain.state_ticks_left = int(round(rng.randf_range(0.6, 1.4) / DriftConstants.TICK_DT))
	elif brain.state == BotState.ENGAGE and rng.randf() < (evade_chance * (1.0 - 0.3 * aggression)):
		brain.state = BotState.EVADE
		brain.state_ticks_left = int(round(rng.randf_range(0.4, 0.9) / DriftConstants.TICK_DT))
		brain.approach_offset_rad = rng.randf_range(-1.4, 1.4)
		brain.feint_ticks_left = int(round(rng.randf_range(0.1, 0.25) / DriftConstants.TICK_DT))
	elif brain.state == BotState.ENGAGE and brain.state_ticks_left <= 0:
		# periodically vary approach.
		brain.state = BotState.REPOSITION
		brain.state_ticks_left = int(round(rng.randf_range(0.6, 1.2) / DriftConstants.TICK_DT))
		brain.approach_offset_rad = rng.randf_range(-1.0, 1.0)
	elif brain.state in [BotState.EVADE, BotState.REPOSITION, BotState.RESET] and brain.state_ticks_left <= 0:
		brain.state = BotState.ROAM
		brain.state_ticks_left = int(round(rng.randf_range(0.8, 1.8) / DriftConstants.TICK_DT))

	if brain.state_ticks_left > 0 and brain.state != BotState.SPAWN_RECOVER:
		brain.state_ticks_left -= 1

	# Decide desired movement + firing. Only recompute when reaction timer expires.
	var desired_turn: float = brain.turn_cmd_smoothed
	var desired_thrust: float = brain.thrust_cmd_smoothed
	var want_fire: bool = false

	if brain.reaction_ticks_left <= 0:
		# Reaction cadence: per-bot base + per-bot jitter, then scaled by skill.
		var base_ms: float = float(int(round(lerpf(float(reaction_ms), float(brain.personality.reaction_ms_base), 0.65))))
		var jitter: float = clampf(float(brain.personality.reaction_jitter), 0.0, 0.85)
		var mul: float = rng.randf_range(1.0 - jitter, 1.0 + jitter)
		var eff_s: float = (base_ms / 1000.0) * mul * (1.10 - 0.60 * clampf(skill, 0.0, 1.0))
		brain.reaction_ticks_left = maxi(1, int(round(eff_s / DriftConstants.TICK_DT)))

		var decision := _compute_decision(s)
		desired_turn = float(decision.get("turn", 0.0))
		desired_thrust = float(decision.get("thrust", 0.0))
		want_fire = bool(decision.get("fire", false))
		if in_safe:
			want_fire = false
		if bool(brain.energy_disengaged):
			want_fire = false

	# Occasional delayed turns (human hesitation / missed correction).
	if brain.turn_stall_ticks_left > 0:
		brain.turn_stall_ticks_left -= 1
		desired_turn = 0.0
	elif rng.randf() < lerpf(0.012, 0.003, clampf(skill, 0.0, 1.0)):
		brain.turn_stall_ticks_left = int(round(rng.randf_range(0.06, 0.14) / DriftConstants.TICK_DT))
		desired_turn = 0.0

	# Aim/turn smoothing with occasional under/oversteer.
	var steer_alpha: float = clampf(0.10 + 0.25 * skill, 0.05, 0.40)
	brain.turn_cmd_smoothed = lerpf(brain.turn_cmd_smoothed, desired_turn, steer_alpha)
	if rng.randf() < 0.02:
		brain.turn_cmd_smoothed *= rng.randf_range(0.85, 1.15)
	brain.turn_cmd_smoothed = clampf(brain.turn_cmd_smoothed, -1.0, 1.0)

	# Thrust smoothing (avoid robotic on/off).
	var thrust_alpha: float = clampf(0.18 + 0.22 * skill, 0.10, 0.55)
	brain.thrust_cmd_smoothed = lerpf(brain.thrust_cmd_smoothed, desired_thrust, thrust_alpha)
	brain.thrust_cmd_smoothed = clampf(brain.thrust_cmd_smoothed, -1.0, 1.0)

	# Burst firing: edge-triggered pulses only.
	var fire_primary: bool = false
	if brain.fire_pulse_cooldown_ticks > 0:
		brain.fire_pulse_cooldown_ticks -= 1
	if brain.burst_pause_ticks_left > 0:
		brain.burst_pause_ticks_left -= 1
	if brain.burst_ticks_left > 0:
		brain.burst_ticks_left -= 1
	else:
		if brain.burst_pause_ticks_left <= 0 and want_fire:
			brain.burst_ticks_left = int(round(maxf(0.05, burst_len_s * rng.randf_range(0.85, 1.15)) / DriftConstants.TICK_DT))
			brain.burst_pause_ticks_left = int(round(maxf(0.05, burst_pause_s * rng.randf_range(0.85, 1.25)) / DriftConstants.TICK_DT))
			brain.fire_pulse_cooldown_ticks = 0

	if brain.burst_ticks_left > 0:
		# Energy budget: avoid draining to zero.
		var min_energy_to_fire: int = int(world.bullet_energy_cost) + int(round(8.0 * (1.0 - aggression)))
		if int(s.energy_current) >= min_energy_to_fire:
			if brain.fire_pulse_cooldown_ticks <= 0:
				fire_primary = true
				# cadence: faster when more aggressive/skillful
				var min_cd := int(round(3 + 5 * (1.0 - skill)))
				var max_cd := int(round(7 + 10 * (1.0 - aggression)))
				brain.fire_pulse_cooldown_ticks = clampi(int(rng.randi_range(min_cd, max_cd)), 1, 30)

	# Hesitation/random delay before firing (reaction time).
	if want_fire and not bool(brain.fire_intent_active):
		brain.fire_intent_active = true
		var base_s := clampf(float(reaction_ms) / 1000.0, 0.05, 0.35)
		var jitter := rng.randf_range(0.75, 1.25)
		var eff_s := base_s * jitter * (1.15 - 0.85 * skill)
		brain.fire_hesitation_ticks_left = int(round(eff_s / DriftConstants.TICK_DT))
	elif (not want_fire) and bool(brain.fire_intent_active):
		brain.fire_intent_active = false
		brain.fire_hesitation_ticks_left = 0
		brain.burst_ticks_left = 0
		brain.burst_pause_ticks_left = 0
		brain.fire_pulse_cooldown_ticks = 0

	if brain.fire_hesitation_ticks_left > 0:
		brain.fire_hesitation_ticks_left -= 1
		fire_primary = false

	# Occasional missed shots.
	if fire_primary:
		var miss_p := lerpf(0.10, 0.015, clampf(0.5 * accuracy + 0.5 * skill, 0.0, 1.0))
		if rng.randf() < miss_p:
			fire_primary = false

	# Safe-zone emergency brake: if we’re safe and about to collide at speed, tap fire
	# to stop (shared sim converts fire->brake in safe zones).
	if in_safe and has_map:
		var speed_now := s.velocity.length()
		if speed_now > float(brake_fire_speed_threshold_px_s):
			var look_dir := s.velocity.normalized()
			var probe := s.position + look_dir * clampf(80.0 + speed_now * 0.25, 80.0, 200.0)
			if world.is_position_blocked(probe, DriftConstants.SHIP_RADIUS):
				# Gated, imperfect braking: cooldown + probability.
				var can_try: bool = brain.brake_fire_cooldown_ticks_left <= 0
				var use_p: float = _bot_brake_use_chance()
				if can_try and rng.randf() < use_p:
					fire_primary = true
					brain.brake_fire_cooldown_ticks_left = _brake_fire_cooldown_ticks()
					brain.debug_brake_fire_count += 1
					# Brake-fire should also stop intentional thrust/turn in the same tick.
					brain.thrust_cmd_smoothed = 0.0
					brain.turn_cmd_smoothed = 0.0
					if DEBUG_BOT and (brain.debug_brake_fire_count % 10) == 0:
						print("[BOT] brake-fire count=", brain.debug_brake_fire_count)
				else:
					# Otherwise: do NOT fire (stay safe-zone compliant). Stop thrusting and let
					# drift/normal movement slow us down naturally.
					fire_primary = false
					brain.thrust_cmd_smoothed = 0.0

	# Route firing through the same action validation pipeline as humans.
	# - If rejected in safe zone, allow it only when it triggers the brake behavior.
	if fire_primary:
		var gate := world.can_perform_action(s, DriftWorld.ActionType.FIRE_PRIMARY, {"tick": world.tick, "ship_id": local_ship_id})
		if not bool(gate.get("ok", true)):
			var should_brake: bool = bool(gate.get("brake", false)) and s.velocity.length() > 0.5
			if should_brake:
				brain.thrust_cmd_smoothed = 0.0
				brain.turn_cmd_smoothed = 0.0
			else:
				fire_primary = false

	var cmd: DriftTypes.DriftInputCmd = DriftTypes.DriftInputCmd.new(brain.thrust_cmd_smoothed, brain.turn_cmd_smoothed, fire_primary, false, false)
	var next_tick: int = world.tick + 1

	input_history[next_tick] = cmd
	_send_input(next_tick, cmd)

	# Predict locally.
	world.step_tick({ local_ship_id: cmd })


func _angle_wrap(a: float) -> float:
	var x := fmod(a + PI, TAU)
	if x < 0.0:
		x += TAU
	return x - PI


func _forward_dir(rot: float) -> Vector2:
	return Vector2(cos(rot), sin(rot))


func _has_line_of_sight(a: Vector2, b: Vector2) -> bool:
	# Conservative LOS check using local map collision.
	# If we don't have map solids, assume LOS.
	if not has_map:
		return true
	var d := b - a
	var dist := d.length()
	if dist <= 1.0:
		return true
	var step := float(DriftWorld.TILE_SIZE) * 0.5
	var steps := int(ceil(dist / step))
	var dir := d / dist
	for i in range(1, steps):
		var p := a + dir * (float(i) * step)
		if world.is_position_blocked(p, 2.0):
			return false
	return true


func _select_target(self_ship: DriftTypes.DriftShipState, perception: BotPerception) -> int:
	# Keep current target until lock expires (unless target vanished).
	if brain.target_id != -1 and perception.perceived_targets.has(brain.target_id) and brain.target_lock_ticks_left > 0:
		var best_locked: int = perception.best_target_id(self_ship.position)
		if best_locked != -1 and best_locked != brain.target_id:
			var e_best: Dictionary = perception.get_entry(best_locked)
			var e_cur: Dictionary = perception.get_entry(brain.target_id)
			var best_vis: bool = bool(e_best.get("visible", false))
			var cur_vis: bool = bool(e_cur.get("visible", false))
			# Target switching indecision when another visible enemy appears.
			var p_switch: float = clampf(float(brain.personality.target_switch_indecision_p), 0.0, 0.9)
			if best_vis and rng.randf() < p_switch:
				return best_locked
			# Rarely: "freeze" and drop lock briefly if multiple threats are visible.
			var p_drop: float = clampf(float(brain.personality.drop_target_indecision_p), 0.0, 0.5)
			if best_vis and cur_vis and rng.randf() < p_drop:
				return -1
		return brain.target_id
	return perception.best_target_id(self_ship.position)


func _compute_decision(self_ship: DriftTypes.DriftShipState) -> Dictionary:
	# Compute desired inputs for the current state.
	var turn: float = 0.0
	var thrust: float = 0.0
	var fire: bool = false
	var in_safe: bool = bool(self_ship.in_safe_zone)

	# Basic wall avoidance lookahead.
	var avoid_angle: float = 0.0
	if has_map:
		var v := self_ship.velocity
		var speed := v.length()
		var look_dir := v.normalized() if speed > 10.0 else _forward_dir(float(self_ship.rotation))
		var look_dist := clampf(70.0 + speed * 0.35, 70.0, 240.0)
		var probe := self_ship.position + look_dir * look_dist
		if world.is_position_blocked(probe, DriftConstants.SHIP_RADIUS):
			# Steer away from the collision normal.
			var n := world.get_collision_normal(self_ship.position, probe, DriftConstants.SHIP_RADIUS)
			if n != Vector2.ZERO:
				avoid_angle = atan2(n.y, n.x)

	# Safe zone movement: roam/exit only, never attack.
	if in_safe:
		# Occasional "hesitation" (looks like deciding / looking around).
		if brain.safe_hesitate_ticks_left > 0:
			brain.safe_hesitate_ticks_left -= 1
			return {"turn": 0.0, "thrust": 0.0, "fire": false}
		elif rng.randf() < clampf(float(brain.personality.safe_zone_hesitate_p), 0.0, 0.2):
			brain.safe_hesitate_ticks_left = int(rng.randi_range(brain.personality.safe_zone_hesitate_ticks_min, brain.personality.safe_zone_hesitate_ticks_max))
			return {"turn": 0.0, "thrust": 0.0, "fire": false}

		# Keep an exit heading for a short time so we don’t jitter.
		if brain.safe_exit_ticks_left <= 0:
			brain.safe_exit_ticks_left = int(round(rng.randf_range(1.0, 2.0) / DriftConstants.TICK_DT))
			brain.safe_exit_angle = rng.randf_range(-PI, PI)
		else:
			brain.safe_exit_ticks_left -= 1

		var desired_angle := brain.safe_exit_angle
		# If avoiding a wall, bias away.
		if avoid_angle != 0.0:
			desired_angle = avoid_angle
		var ang_diff := _angle_wrap(desired_angle - float(self_ship.rotation))
		var full_turn_angle := lerpf(0.85, 0.55, clampf(skill, 0.0, 1.0))
		turn = clampf(ang_diff / full_turn_angle, -1.0, 1.0)
		# Preferred “gentle but steady” exit thrust.
		var speed := self_ship.velocity.length()
		var want_speed := lerpf(180.0, 320.0, clampf(skill, 0.0, 1.0))
		thrust = 1.0 if speed < want_speed else 0.35
		fire = false
		return {"turn": turn, "thrust": thrust, "fire": fire}

	if brain.state == BotState.SPAWN_RECOVER:
		# Brief grace: gentle forward, minimal turning.
		thrust = 0.35
		turn = rng.randf_range(-0.2, 0.2)
		fire = false
		return {"turn": turn, "thrust": thrust, "fire": fire}

	if brain.state == BotState.RESET:
		# Break out of corners: turn hard-ish and push.
		thrust = 0.75
		turn = rng.randf_range(-1.0, 1.0)
		fire = false
		return {"turn": turn, "thrust": thrust, "fire": fire}

	# Default: roam unless we have a target.
	if brain.target_id == -1 or brain.perception.get_entry(brain.target_id).is_empty():
		# ROAM: keep speed in a band, gentle turns, avoid walls.
		var speed2 := self_ship.velocity.length()
		var want_speed := rng.randf_range(160.0, 360.0)
		thrust = 1.0 if speed2 < want_speed else 0.0
		turn = rng.randf_range(-0.5, 0.5)
		if avoid_angle != 0.0:
			var fwd := _forward_dir(float(self_ship.rotation))
			var away := Vector2(cos(avoid_angle), sin(avoid_angle))
			turn = clampf(turn + clampf(fwd.cross(away), -1.0, 1.0) * 0.9, -1.0, 1.0)
		fire = false
		return {"turn": turn, "thrust": thrust, "fire": fire}

	var entry: Dictionary = brain.perception.get_entry(brain.target_id)
	if entry.is_empty():
		return {"turn": 0.0, "thrust": 0.0, "fire": false}
	var target_pos: Vector2 = entry.get("last_pos", Vector2.ZERO)
	var to_t := target_pos - self_ship.position
	var dist := to_t.length()
	var dir := (to_t / dist) if dist > 1.0 else _forward_dir(float(self_ship.rotation))
	var desired_dir := dir

	# Per-bot style modifiers.
	var eff_aggression: float = clampf((aggression * 0.60) + (brain.personality.aggression * 0.40), 0.0, 1.0)
	var eff_range: float = float(preferred_range_px) * clampf(float(brain.personality.preferred_range_mult), 0.5, 2.0)

	# State-based movement styles.
	if brain.state == BotState.EVADE:
		# EVADE: break line by offsetting sharply.
		desired_dir = dir.rotated(brain.approach_offset_rad)
		thrust = 1.0
		fire = false
	elif brain.state == BotState.REPOSITION:
		# REPOSITION: take an offset approach angle, not straight chase.
		desired_dir = dir.rotated(brain.approach_offset_rad)
		thrust = 1.0 if dist > (eff_range * 0.8) else 0.5
		fire = false
	else:
		# ENGAGE: orbit-ish at preferred range.
		# Occasional circling instead of hard-commit.
		if brain.circle_ticks_left > 0:
			brain.circle_ticks_left -= 1
			desired_dir = dir.rotated(float(brain.orbit_dir) * 1.25)
			thrust = 0.55
			fire = false
		elif rng.randf() < (0.05 + 0.12 * clampf(float(brain.personality.circle_bias), 0.0, 1.0)) and dist > (eff_range * 1.15):
			brain.circle_ticks_left = int(round(rng.randf_range(0.55, 1.25) / DriftConstants.TICK_DT))
			desired_dir = dir.rotated(float(brain.orbit_dir) * 1.10)
			thrust = 0.60
			fire = false
		elif dist < eff_range * 0.85:
			desired_dir = dir.rotated(float(brain.orbit_dir) * 1.2)
			thrust = 0.65
		elif dist > eff_range * 1.25:
			desired_dir = dir.rotated(brain.approach_offset_rad * 0.4)
			thrust = 1.0
		else:
			desired_dir = dir.rotated(float(brain.orbit_dir) * 0.55)
			thrust = 0.8

	# Convert desired direction to a turn command toward that heading.
	var desired_angle := atan2(desired_dir.y, desired_dir.x)
	# Aim error (imperfect; increases with distance; reduced by accuracy/skill).
	var base_sigma := lerpf(0.22, 0.04, clampf(0.5 * skill + 0.5 * accuracy, 0.0, 1.0))
	base_sigma += clampf(float(brain.personality.aim_error_sigma), 0.0, 0.25)
	var dist_sigma := dist * lerpf(0.00045, 0.00015, clampf(accuracy, 0.0, 1.0))
	var aim_err := rng.randfn(0.0, base_sigma + dist_sigma)
	# Additional perception uncertainty (esp. when LOS blocked).
	var p_jitter: float = float(entry.get("aim_jitter_rad", 0.0))
	if p_jitter > 0.0:
		aim_err += rng.randf_range(-p_jitter, p_jitter)
	# Micro-correction jitter (humans do small corrections).
	if rng.randf() < 0.08:
		aim_err += rng.randf_range(-0.03, 0.03)
	desired_angle += aim_err

	var ang_diff := _angle_wrap(desired_angle - float(self_ship.rotation))
	# Normalize into [-1..1] turn command based on a reasonable "full deflection" threshold.
	var full_turn_angle := lerpf(0.8, 0.45, clampf(skill, 0.0, 1.0))
	turn = clampf(ang_diff / full_turn_angle, -1.0, 1.0)
	# Occasional feint: brief turn reversal.
	if brain.feint_ticks_left > 0:
		brain.feint_ticks_left -= 1
		turn = -turn
	elif rng.randf() < 0.015:
		brain.feint_ticks_left = int(round(rng.randf_range(0.10, 0.22) / DriftConstants.TICK_DT))

	# Apply wall avoidance steer if needed.
	if avoid_angle != 0.0:
		var fwd2 := _forward_dir(float(self_ship.rotation))
		var away2 := Vector2(cos(avoid_angle), sin(avoid_angle))
		turn = clampf(turn + clampf(fwd2.cross(away2), -1.0, 1.0) * 1.0, -1.0, 1.0)

	# Decide firing: only in ENGAGE and only with LOS + alignment.
	if brain.state == BotState.ENGAGE:
		var visible: bool = bool(entry.get("visible", false))
		var los_ok: bool = bool(entry.get("los_ok", false))
		var align_ok := absf(ang_diff) < lerpf(0.22, 0.08, clampf(accuracy, 0.0, 1.0))
		# Distance gating: more likely to shoot near preferred range.
		var range_ok := (dist < eff_range * lerpf(1.45, 1.80, eff_aggression))
		# Only shoot when the target is actually perceived as visible with clear LOS.
		fire = visible and los_ok and align_ok and range_ok and (rng.randf() < lerpf(0.22, 0.80, eff_aggression))

	return {"turn": turn, "thrust": thrust, "fire": fire}


func _send_input(tick: int, cmd: DriftTypes.DriftInputCmd) -> void:
	var packet: PackedByteArray = DriftNet.pack_input_packet(tick, local_ship_id, cmd)
	# Server peer id is always 1.
	enet_peer.set_transfer_channel(NET_CHANNEL)
	enet_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	enet_peer.set_target_peer(1)
	enet_peer.put_packet(packet)


func _poll_network_packets() -> void:
	if enet_peer == null:
		return

	enet_peer.poll()
	_update_connection_state()

	var best_snapshot_tick: int = -1
	var best_snapshot_dict: Dictionary = {}

	while enet_peer.get_available_packet_count() > 0:
		var channel: int = enet_peer.get_packet_channel()
		var _sender_id: int = enet_peer.get_packet_peer()
		var bytes: PackedByteArray = enet_peer.get_packet()
		if channel != NET_CHANNEL:
			continue

		var pkt_type: int = DriftNet.get_packet_type(bytes)
		if pkt_type == DriftNet.PKT_WELCOME:
			var w: Dictionary = DriftNet.unpack_welcome_packet(bytes)
			if not w.is_empty():
				local_ship_id = w["ship_id"]
				print("Bot assigned ship_id=", local_ship_id)
				map_path = String(w.get("map_path", "")).strip_edges()
				map_checksum = w.get("map_checksum", PackedByteArray())
				# Finalize deterministic seed now that we know ship_id and map checksum.
				var acc: int = int(bot_seed)
				if map_checksum != null and (map_checksum as PackedByteArray).size() > 0:
					var n: int = mini(8, (map_checksum as PackedByteArray).size())
					for i in range(n):
						acc = int((acc * 31 + int(map_checksum[i])) & 0x7fffffff)
				acc = int((acc ^ int(local_ship_id) ^ 0x5bd1e995) & 0x7fffffff)
				if acc == 0:
					acc = 1
				bot_seed = acc
				rng.seed = int(bot_seed)
				if DEBUG_BOT:
					print("[BOT] seed=", bot_seed, " map_path=", map_path)

				# Reset local state for clean start.
				world.tick = 0
				world.ships.clear()
				world.add_ship(local_ship_id, DEFAULT_SPAWN)
				input_history.clear()
				authoritative_tick = -1
				authoritative_ship_state = null
				has_authoritative = false
				brain._reset_for_spawn()
				brain.state_ticks_left = int(round(rng.randf_range(0.20, 0.45) / DriftConstants.TICK_DT))
				# Per-bot personality: derived deterministically from bot_id (ship_id).
				brain.personality = _make_personality(local_ship_id)

				# Load map for local collision/LOS and safe zones.
				has_map = false
				if map_path != "":
					var mres: Dictionary = DriftMapLoader.load_map(map_path)
					if bool(mres.get("ok", false)):
						var canonical: Dictionary = mres.get("map", {})
						var meta: Dictionary = canonical.get("meta", {})
						var w_tiles: int = int(meta.get("w", 64))
						var h_tiles: int = int(meta.get("h", 64))
						var tileset_name: String = String(meta.get("tileset", "")).strip_edges()
						if tileset_name != "":
							var tileset_def := DriftTileDefs.load_tileset(tileset_name)
							var canonical_layers: Dictionary = canonical.get("layers", {})
							var solid_layer_cells: Array = canonical_layers.get("solid", [])
							var solid_cells: Array = DriftTileDefs.build_solid_cells_from_layer_cells(solid_layer_cells, tileset_def)
							var door_cells: Array = DriftTileDefs.build_door_cells_from_layer_cells(solid_layer_cells, tileset_def)
							var safe_zone_cells: Array = DriftTileDefs.build_safe_zone_cells(canonical, tileset_def)
							world.set_solid_tiles(solid_cells)
							world.set_door_tiles(door_cells)
							world.set_safe_zone_tiles(safe_zone_cells)
							var door_open_s: float = float(meta.get("door_open_seconds", DriftConstants.DOOR_OPEN_SECONDS))
							var door_closed_s: float = float(meta.get("door_closed_seconds", DriftConstants.DOOR_CLOSED_SECONDS))
							var door_frame_s: float = float(meta.get("door_frame_seconds", DriftConstants.DOOR_FRAME_SECONDS))
							var door_start_open: bool = bool(meta.get("door_start_open", DriftConstants.DOOR_START_OPEN))
							world.configure_doors(door_open_s, door_closed_s, door_frame_s, door_start_open)
							world.add_boundary_tiles(w_tiles, h_tiles)
							world.set_map_dimensions(w_tiles, h_tiles)
							has_map = true
				var ruleset_json: String = String(w.get("ruleset_json", "")).strip_edges()
				if ruleset_json != "":
					var json := JSON.new()
					var parse_err := json.parse(ruleset_json)
					if parse_err == OK and typeof(json.data) == TYPE_DICTIONARY:
						var validated := DriftValidate.validate_ruleset(json.data)
						if bool(validated.get("ok", false)):
							world.apply_ruleset(validated.get("ruleset", {}))
				else:
					# Backward compat: accept wall_restitution-only handshake.
					var wr: float = float(w.get("wall_restitution", -1.0))
					if wr >= 0.0:
						world.wall_restitution = wr
				# Optional: tangent damping (present in newer handshakes).
				var td: float = float(w.get("tangent_damping", -1.0))
				if td >= 0.0:
					world.tangent_damping = td
			continue

		if pkt_type == DriftNet.PKT_SNAPSHOT:
			var snap_dict: Dictionary = DriftNet.unpack_snapshot_packet(bytes)
			if snap_dict.is_empty():
				continue

			var snap_tick: int = snap_dict["tick"]
			if snap_tick > best_snapshot_tick:
				best_snapshot_tick = snap_tick
				best_snapshot_dict = snap_dict

	if best_snapshot_tick != -1:
		_apply_snapshot_dict(best_snapshot_dict)


func _update_connection_state() -> void:
	var status: int = enet_peer.get_connection_status()
	if status == last_connection_status:
		return

	if status == MultiplayerPeer.CONNECTION_CONNECTED:
		connected = true
		print("Bot connected")
	elif status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if last_connection_status == MultiplayerPeer.CONNECTION_CONNECTING:
			push_error("Bot connection failed")
			quit()
			return
		elif last_connection_status == MultiplayerPeer.CONNECTION_CONNECTED:
			print("Bot disconnected")
			connected = false
			local_ship_id = -1
			has_authoritative = false
			authoritative_tick = -1
			authoritative_ship_state = null
			input_history.clear()

	last_connection_status = status


func _apply_snapshot_dict(snap_dict: Dictionary) -> void:
	var snap_tick: int = snap_dict["tick"]
	if snap_tick <= authoritative_tick:
		return
	var auth_bullets: Array = []
	if snap_dict.has("bullets") and (snap_dict.get("bullets") is Array):
		auth_bullets = snap_dict.get("bullets")

	var ships: Array = snap_dict["ships"]
	for ship_state in ships:
		if ship_state.id == local_ship_id:
			authoritative_tick = snap_tick
			authoritative_ship_state = ship_state
			has_authoritative = true
			_reconcile_to_authoritative_snapshot(snap_tick, ship_state, auth_bullets)
			break


func _reconcile_to_authoritative_snapshot(snapshot_tick: int, auth_state: DriftTypes.DriftShipState, auth_bullets_for_tick: Array) -> void:
	var current_tick: int = world.tick

	if not world.ships.has(local_ship_id):
		world.add_ship(local_ship_id, auth_state.position)

	var local_state: DriftTypes.DriftShipState = world.ships[local_ship_id]
	local_state.position = auth_state.position
	local_state.velocity = auth_state.velocity
	local_state.rotation = auth_state.rotation
	# Deterministic energy state (v3 snapshot extras).
	if "energy_current" in auth_state:
		local_state.energy_current = int(auth_state.energy_current)
	if "energy_max" in auth_state:
		local_state.energy_max = int(auth_state.energy_max)
	if "energy_recharge_rate_per_sec" in auth_state:
		local_state.energy_recharge_rate_per_sec = int(auth_state.energy_recharge_rate_per_sec)
	if "energy_recharge_delay_ticks" in auth_state:
		local_state.energy_recharge_delay_ticks = int(auth_state.energy_recharge_delay_ticks)
	if "energy_recharge_wait_ticks" in auth_state:
		local_state.energy_recharge_wait_ticks = int(auth_state.energy_recharge_wait_ticks)
	if "energy_recharge_fp_accum" in auth_state:
		local_state.energy_recharge_fp_accum = int(auth_state.energy_recharge_fp_accum)
	if "energy_drain_fp_accum" in auth_state:
		local_state.energy_drain_fp_accum = int(auth_state.energy_drain_fp_accum)
	if "energy" in auth_state:
		local_state.energy = float(auth_state.energy)
	# Ability state (replicated via snapshot extension).
	if "stealth_on" in auth_state:
		local_state.stealth_on = bool(auth_state.stealth_on)
	if "cloak_on" in auth_state:
		local_state.cloak_on = bool(auth_state.cloak_on)
	if "xradar_on" in auth_state:
		local_state.xradar_on = bool(auth_state.xradar_on)
	if "antiwarp_on" in auth_state:
		local_state.antiwarp_on = bool(auth_state.antiwarp_on)
	if "in_safe_zone" in auth_state:
		local_state.in_safe_zone = bool(auth_state.in_safe_zone)
	if "damage_protect_until_tick" in auth_state:
		local_state.damage_protect_until_tick = int(auth_state.damage_protect_until_tick)

	world.tick = snapshot_tick

	# Reset predicted bullets baseline for this bot.
	if world != null:
		world.bullets.clear()
		for b in auth_bullets_for_tick:
			if b == null:
				continue
			if int(b.owner_id) != local_ship_id:
				continue
			world.bullets[int(b.id)] = DriftTypes.DriftBulletState.new(int(b.id), int(b.owner_id), int(b.level), b.position, b.velocity, int(b.spawn_tick), int(b.die_tick), int(b.bounces_left))
		var base_cmd: DriftTypes.DriftInputCmd = input_history.get(snapshot_tick, DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false))
		world._prev_fire_by_ship[local_ship_id] = bool(base_cmd.fire_primary)
		var abits: int = 0
		if bool(base_cmd.stealth_btn):
			abits |= 1
		if bool(base_cmd.cloak_btn):
			abits |= 2
		if bool(base_cmd.xradar_btn):
			abits |= 4
		if bool(base_cmd.antiwarp_btn):
			abits |= 8
		world._prev_ability_buttons_by_ship[local_ship_id] = abits

	# If snapshot is ahead, snap forward and stop.
	if snapshot_tick >= current_tick:
		_prune_input_history(authoritative_tick)
		return

	for t in range(snapshot_tick + 1, current_tick + 1):
		var cmd: DriftTypes.DriftInputCmd = input_history.get(t, DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false))
		world.step_tick({ local_ship_id: cmd })

	_prune_input_history(authoritative_tick)

	if DEBUG_NET:
		var drift: float = world.ships[local_ship_id].position.distance_to(auth_state.position)
		print("[BOT] reconciled tick=", snapshot_tick, " world.tick=", world.tick, " drift=", drift)


func _prune_input_history(upto_tick_inclusive: int) -> void:
	var keys: Array = input_history.keys()
	for k in keys:
		if int(k) <= upto_tick_inclusive:
			input_history.erase(k)
