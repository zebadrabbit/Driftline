## Prize feedback pipeline (client-only UI).
##
## Requirements:
## - Transient: expires after a fixed number of simulation ticks.
## - Non-stacking: new local pickup replaces the current message.
## - Non-authoritative: never mutates simulation state.
## - Deterministic + replay-safe: tick-based timing, driven only by authoritative snapshot events.

extends RefCounted

const DriftTypes := preload("res://shared/drift_types.gd")
const DriftConstants := preload("res://shared/drift_constants.gd")
const DriftPrizeTypes := preload("res://client/ui/prize_types.gd")

# 2.5s shown as deterministic ticks using ceil(ms * TICK_RATE / 1000).
const PRIZE_FEEDBACK_DURATION_MS: int = 2500
const PRIZE_FEEDBACK_DURATION_TICKS: int = int((PRIZE_FEEDBACK_DURATION_MS * DriftConstants.TICK_RATE + 999) / 1000)

# prize_id -> {kind:int, is_negative:bool, is_death_drop:bool}
var _cache_by_id: Dictionary = {}

var _active_text: String = ""
var _active_until_tick: int = -1
var _active_icon_atlas: Vector2i = Vector2i(-1, -1)
var _active_sound_id: String = ""
var _active_prize_type: int = -1
var _active_toast_label: String = ""
var _pending_pickup_sfx: bool = false
var _pending_awarded_prize_type: int = -1
var _pending_toast_label: String = ""


func cache_prize_states(prize_states: Array) -> void:
	# Called with the authoritative prize list from snapshots.
	for p in prize_states:
		if p == null:
			continue
		_cache_by_id[int(p.id)] = {
			"kind": int(p.kind),
			"is_negative": bool(p.is_negative),
			"is_death_drop": bool(p.is_death_drop),
		}


func consume_prize_events(snap_tick: int, prize_events: Array, local_ship_id: int) -> void:
	# Consume authoritative prize events and update transient UI state.
	# Non-stacking: if multiple local pickups are present, the last one wins.
	var last_local_pickup_pid: int = -1
	var last_local_msg: String = ""
	var last_local_icon: Vector2i = Vector2i(-1, -1)
	var last_local_sound_id: String = ""
	var last_local_prize_type: int = -1
	var last_local_toast_label: String = ""
	for ev in prize_events:
		if ev == null or typeof(ev) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = ev
		if String(d.get("type", "")) != "pickup":
			continue
		var pid: int = int(d.get("prize_id", -1))
		var is_local: bool = int(d.get("ship_id", -1)) == int(local_ship_id)
		if is_local:
			last_local_pickup_pid = pid
			# Format BEFORE pruning cache so labels are stable.
			last_local_msg = _format_prize_pickup_message(pid)
			var kind: int = -1
			if pid >= 0 and _cache_by_id.has(pid) and (_cache_by_id.get(pid) is Dictionary):
				var info0: Dictionary = _cache_by_id.get(pid)
				kind = int(info0.get("kind", -1))
				var pt0: int = DriftPrizeTypes.prize_type_from_prize_kind(kind)
				last_local_prize_type = pt0
				_pending_awarded_prize_type = pt0
				var base_label: String = DriftPrizeTypes.label_for_prize_kind(kind)
				if base_label != "":
					var sign0: String = "-" if bool(info0.get("is_negative", false)) else "+"
					last_local_toast_label = "%s%s" % [sign0, base_label]
			last_local_icon = DriftPrizeTypes.icon_atlas_coords_for_prize_kind(kind)
			last_local_sound_id = DriftPrizeTypes.sound_id_for_prize_kind(kind)
			_pending_pickup_sfx = true
		# Prune cache entries after they are consumed.
		if pid >= 0 and _cache_by_id.has(pid):
			_cache_by_id.erase(pid)

	if last_local_pickup_pid >= 0:
		_active_text = last_local_msg if last_local_msg != "" else "Prize collected"
		_active_until_tick = int(snap_tick) + int(PRIZE_FEEDBACK_DURATION_TICKS)
		_active_icon_atlas = last_local_icon
		_active_sound_id = last_local_sound_id
		_active_prize_type = last_local_prize_type
		_active_toast_label = last_local_toast_label
		_pending_toast_label = last_local_toast_label


func take_toast_label_trigger() -> String:
	# Returns the last locally-generated toast label once, or "".
	var v: String = String(_pending_toast_label)
	_pending_toast_label = ""
	return v


func take_pickup_sfx_trigger() -> bool:
	# Returns true at most once per consumed pickup batch.
	if _pending_pickup_sfx:
		_pending_pickup_sfx = false
		return true
	return false


func take_awarded_prize_type_trigger() -> int:
	# Returns the last locally-awarded PrizeType once, or -1.
	var v: int = int(_pending_awarded_prize_type)
	_pending_awarded_prize_type = -1
	return v


func get_feedback_text_for_tick(tick: int) -> String:
	if _active_text != "" and int(tick) >= 0 and int(tick) < int(_active_until_tick):
		return _active_text
	return ""


func get_feedback_icon_for_tick(tick: int) -> Vector2i:
	if int(tick) >= 0 and int(tick) < int(_active_until_tick):
		return _active_icon_atlas
	return Vector2i(-1, -1)


func get_feedback_sound_id_for_tick(tick: int) -> String:
	if int(tick) >= 0 and int(tick) < int(_active_until_tick):
		return _active_sound_id
	return ""


func get_feedback_prize_type_for_tick(tick: int) -> int:
	if int(tick) >= 0 and int(tick) < int(_active_until_tick):
		return int(_active_prize_type)
	return -1


func get_feedback_toast_label_for_tick(tick: int) -> String:
	if int(tick) >= 0 and int(tick) < int(_active_until_tick):
		return String(_active_toast_label)
	return ""


func get_feedback_until_tick() -> int:
	return int(_active_until_tick)


func _format_prize_pickup_message(prize_id: int) -> String:
	var pid: int = int(prize_id)
	if pid >= 0 and _cache_by_id.has(pid) and (_cache_by_id.get(pid) is Dictionary):
		var info: Dictionary = _cache_by_id.get(pid)
		var label: String = DriftPrizeTypes.label_for_prize_kind(int(info.get("kind", -1)))
		if label != "":
			var sign: String = "-" if bool(info.get("is_negative", false)) else "+"
			return "Prize %s%s" % [sign, label]
	return "Prize collected"
