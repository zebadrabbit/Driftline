## Deterministic per-tick player input for replay + verification.
##
## Rules:
## - Serializable (Dictionary primitives only)
## - Deterministic across platforms
## - No floats, OS time, frame delta, RNG, or Godot physics

class_name DriftInput
extends RefCounted

const _SELF_SCRIPT_PATH: String = "res://shared/drift_input.gd"


# Thrust intent: -1 (reverse), 0 (none), 1 (forward)
var thrust: int = 0

# Turn intent: -1 (left), 0 (none), 1 (right)
var turn: int = 0

var fire: bool = false
var bomb: bool = false
var afterburner: bool = false

# Placeholder for deterministic ability buttons (future)
var ability1: bool = false


func _init(
	thrust_value: int = 0,
	turn_value: int = 0,
	fire_value: bool = false,
	bomb_value: bool = false,
	afterburner_value: bool = false,
	ability1_value: bool = false
) -> void:
	thrust = _clamp_trit_int(thrust_value)
	turn = _clamp_trit_int(turn_value)
	fire = bool(fire_value)
	bomb = bool(bomb_value)
	afterburner = bool(afterburner_value)
	ability1 = bool(ability1_value)


func to_dict() -> Dictionary:
	# Only primitives: int/bool
	return {
		"thrust": int(thrust),
		"turn": int(turn),
		"fire": bool(fire),
		"bomb": bool(bomb),
		"afterburner": bool(afterburner),
		"ability1": bool(ability1),
	}


static func from_dict(d: Dictionary):
	# Strict-ish: missing fields default; invalid types assert.
	var script = load(_SELF_SCRIPT_PATH)
	assert(script != null, "DriftInput.from_dict: failed to load %s" % _SELF_SCRIPT_PATH)
	var out = script.new()
	if d.has("thrust"):
		out.thrust = _clamp_trit_int(_require_int(d["thrust"], "thrust"))
	if d.has("turn"):
		out.turn = _clamp_trit_int(_require_int(d["turn"], "turn"))
	if d.has("fire"):
		out.fire = _require_bool(d["fire"], "fire")
	if d.has("bomb"):
		out.bomb = _require_bool(d["bomb"], "bomb")
	if d.has("afterburner"):
		out.afterburner = _require_bool(d["afterburner"], "afterburner")
	if d.has("ability1"):
		out.ability1 = _require_bool(d["ability1"], "ability1")
	return out


func equals(other) -> bool:
	if other == null:
		return false
	return (
		int(thrust) == int(other.thrust)
		and int(turn) == int(other.turn)
		and bool(fire) == bool(other.fire)
		and bool(bomb) == bool(other.bomb)
		and bool(afterburner) == bool(other.afterburner)
		and bool(ability1) == bool(other.ability1)
	)


func clone():
	var script = load(_SELF_SCRIPT_PATH)
	assert(script != null, "DriftInput.clone: failed to load %s" % _SELF_SCRIPT_PATH)
	return script.new(thrust, turn, fire, bomb, afterburner, ability1)


static func _clamp_trit_int(v: int) -> int:
	if v < -1:
		return -1
	if v > 1:
		return 1
	return int(v)


static func _require_int(v: Variant, field_name: String) -> int:
	assert(typeof(v) == TYPE_INT, "DriftInput.from_dict: '%s' must be int" % field_name)
	return int(v)


static func _require_bool(v: Variant, field_name: String) -> bool:
	assert(typeof(v) == TYPE_BOOL, "DriftInput.from_dict: '%s' must be bool" % field_name)
	return bool(v)
