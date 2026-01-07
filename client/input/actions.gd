## Centralized input action definitions and defaults.
##
## This is the single place allowed to define concrete default key choices.
## Gameplay code should only reference action ids via InputMap/Input.

class_name DriftActions
extends RefCounted

# Ordered list of actions that are safe/expected to be rebound by players.
const REBINDABLE_ACTIONS: Array[String] = [
	"drift_thrust_forward",
	"drift_thrust_reverse",
	"drift_rotate_left",
	"drift_rotate_right",
	"drift_fire_primary",
	"drift_fire_secondary",
	"drift_modifier_ability",
	"drift_ability_stealth",
	"drift_ability_cloak",
	"drift_ability_xradar",
	"drift_ability_antiwarp",
	"drift_toggle_pause_menu",
	"drift_help_toggle",
	"drift_help_next",
	"drift_menu_connect",
	"drift_menu_offline",
	"drift_open_map_editor",
	"drift_open_tilemap_editor",
	"ui_escape_menu",
]

const ACTION_LABELS: Dictionary = {
	"drift_thrust_forward": "Thrust Forward",
	"drift_thrust_reverse": "Thrust Reverse",
	"drift_rotate_left": "Rotate Left",
	"drift_rotate_right": "Rotate Right",
	"drift_fire_primary": "Fire Primary",
	"drift_fire_secondary": "Fire Secondary",
	"drift_modifier_ability": "Afterburner / Modifier",
	"drift_ability_stealth": "Ability: Stealth",
	"drift_ability_cloak": "Ability: Cloak",
	"drift_ability_xradar": "Ability: X-Radar",
	"drift_ability_antiwarp": "Ability: Antiwarp",
	"drift_toggle_pause_menu": "Menu",
	"drift_help_toggle": "Help Toggle",
	"drift_help_next": "Help Next",
	"drift_menu_connect": "Menu: Connect",
	"drift_menu_offline": "Menu: Offline",
	"drift_open_map_editor": "Open Map Editor",
	"drift_open_tilemap_editor": "Open Tilemap Editor",
	"ui_escape_menu": "Back / Close Menu",
}

# Stable keycode integers (Godot 4) used by project defaults.
# For letter keys, this matches ASCII and the physical_keycode used in project.godot.
const SHIFT_KEYCODE: int = 4194325
const CTRL_KEYCODE: int = 4194324
const ESCAPE_KEYCODE: int = 4194305
const ENTER_KEYCODE: int = 4194309

# Keycodes used by the current project defaults (as set in project.godot).
const DEFAULT_W: int = 87
const DEFAULT_A: int = 65
const DEFAULT_S: int = 83
const DEFAULT_D: int = 68
const DEFAULT_SPACE: int = 32
const DEFAULT_Z: int = 90
const DEFAULT_X: int = 88
const DEFAULT_C: int = 67
const DEFAULT_V: int = 86
const DEFAULT_O: int = 79
const DEFAULT_T: int = 84

static var DEFAULT_BINDINGS: Dictionary = _build_default_bindings()


static func build_default_inputmap() -> void:
	# Clears/rebuilds ONLY the actions listed in REBINDABLE_ACTIONS.
	# Does not touch other project/editor actions.
	for action in REBINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(StringName(action))
		InputMap.action_erase_events(StringName(action))

		var evs_any: Variant = DEFAULT_BINDINGS.get(action, [])
		if typeof(evs_any) != TYPE_ARRAY:
			continue
		var evs: Array = evs_any
		for ev_any in evs:
			var ev: InputEvent = ev_any
			if ev == null:
				continue
			# Duplicate so the InputMap owns its own event instances.
			InputMap.action_add_event(StringName(action), ev.duplicate())


static func debug_probe_keycode() -> int:
	# Debug-only helper. Kept here so gameplay code doesn't hardcode a key name.
	return int(OS.find_keycode_from_string("F8"))


static func _build_default_bindings() -> Dictionary:
	return {
		"drift_thrust_forward": [_key_ev(0, DEFAULT_W)],
		"drift_thrust_reverse": [_key_ev(0, DEFAULT_S)],
		"drift_rotate_left": [_key_ev(0, DEFAULT_A)],
		"drift_rotate_right": [_key_ev(0, DEFAULT_D)],
		"drift_fire_primary": [_key_ev(0, DEFAULT_SPACE)],
		"drift_fire_secondary": [_key_ev(0, CTRL_KEYCODE)],
		"drift_modifier_ability": [_key_ev(0, SHIFT_KEYCODE)],
		"drift_ability_stealth": [_key_ev(0, DEFAULT_Z)],
		"drift_ability_cloak": [_key_ev(0, DEFAULT_X)],
		"drift_ability_xradar": [_key_ev(0, DEFAULT_C)],
		"drift_ability_antiwarp": [_key_ev(0, DEFAULT_V)],
		"drift_toggle_pause_menu": [_key_ev(0, ESCAPE_KEYCODE)],
		"drift_help_next": [_key_ev(0, 4194332)],
		"drift_help_toggle": [_key_ev(0, 4194337)],
		"drift_menu_connect": [_key_ev(0, ENTER_KEYCODE)],
		"drift_menu_offline": [_key_ev(0, DEFAULT_O)],
		"drift_open_map_editor": [_key_ev(0, 4194322)],
		"drift_open_tilemap_editor": [_key_ev(0, DEFAULT_T)],
		"ui_escape_menu": [_key_ev(ESCAPE_KEYCODE, 0)],
	}


static func _key_ev(keycode: int, physical_keycode: int, shift := false, ctrl := false, alt := false, meta := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.device = -1
	ev.keycode = int(keycode)
	ev.physical_keycode = int(physical_keycode)
	ev.shift_pressed = bool(shift)
	ev.ctrl_pressed = bool(ctrl)
	ev.alt_pressed = bool(alt)
	ev.meta_pressed = bool(meta)
	ev.pressed = false
	return ev
