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
	"drift_lay_mine",
	"drift_modifier_ability",
	"drift_ability_stealth",
	"drift_ability_cloak",
	"drift_ability_xradar",
	"drift_ability_antiwarp",
	"drift_item_repel",
	"drift_item_burst",
	"drift_item_warp",
	"drift_item_thor",
	"drift_item_rocket",
	"drift_item_decoy",
	"drift_item_brick",
	"drift_item_portal",
	"drift_toggle_multifire",
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
	"drift_lay_mine": "Lay Mine",
	"drift_modifier_ability": "Afterburner / Modifier",
	"drift_ability_stealth": "Ability: Stealth",
	"drift_ability_cloak": "Ability: Cloak",
	"drift_ability_xradar": "Ability: X-Radar",
	"drift_ability_antiwarp": "Ability: Antiwarp",
	"drift_item_repel": "Item: Repel",
	"drift_item_burst": "Item: Burst",
	"drift_item_warp": "Item: Warp",
	"drift_item_thor": "Item: Thor",
	"drift_item_rocket": "Item: Rocket",
	"drift_item_decoy": "Item: Decoy",
	"drift_item_brick": "Item: Brick",
	"drift_item_portal": "Item: Portal",
	"drift_toggle_multifire": "Toggle Multifire",
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
const ESCAPE_KEYCODE: int = 4194305
const ENTER_KEYCODE: int = 4194309
const TAB_KEYCODE: int = 4194306

# Keycodes for the menu-only actions (connect screen).
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
	# Original SubSpace 1.34 layout (original_content/controls.txt + ticker.txt).
	# Shift is the modifier for the paired actions: the unshifted half is suppressed while
	# Shift is held, in DriftClientMain._collect_input_cmd(). Godot action matching is not
	# exact by default, so Shift+HOME fires both drift_ability_stealth and _cloak; that
	# suppression is what disambiguates them.
	return {
		"drift_thrust_forward": [_key_ev(0, KEY_UP)],
		"drift_thrust_reverse": [_key_ev(0, KEY_DOWN)],
		"drift_rotate_left": [_key_ev(0, KEY_LEFT)],
		"drift_rotate_right": [_key_ev(0, KEY_RIGHT)],
		# Guns: Ctrl. Repel: Shift+Ctrl.
		"drift_fire_primary": [_key_ev(0, KEY_CTRL)],
		"drift_item_repel": [_key_ev(0, KEY_CTRL, true)],
		# Bombs: Tab. Mine: Shift+Tab.
		"drift_fire_secondary": [_key_ev(0, TAB_KEYCODE)],
		"drift_lay_mine": [_key_ev(0, TAB_KEYCODE, true)],
		# Shift alone is the afterburner (Shift+thrust).
		"drift_modifier_ability": [_key_ev(0, SHIFT_KEYCODE)],
		# Stealth: Home. Cloak: Shift+Home.
		"drift_ability_stealth": [_key_ev(0, KEY_HOME)],
		"drift_ability_cloak": [_key_ev(0, KEY_HOME, true)],
		# XRadar: End. Antiwarp: Shift+End.
		"drift_ability_xradar": [_key_ev(0, KEY_END)],
		"drift_ability_antiwarp": [_key_ev(0, KEY_END, true)],
		# Multifire: Del. Burst: Shift+Del.
		"drift_toggle_multifire": [_key_ev(0, KEY_DELETE)],
		"drift_item_burst": [_key_ev(0, KEY_DELETE, true)],
		# Warp: Insert. Portal drop/return: Shift+Insert.
		"drift_item_warp": [_key_ev(0, KEY_INSERT)],
		"drift_item_portal": [_key_ev(0, KEY_INSERT, true)],
		"drift_item_rocket": [_key_ev(0, KEY_F3)],
		"drift_item_brick": [_key_ev(0, KEY_F4)],
		"drift_item_decoy": [_key_ev(0, KEY_F5)],
		"drift_item_thor": [_key_ev(0, KEY_F6)],
		"drift_toggle_pause_menu": [_key_ev(0, ESCAPE_KEYCODE)],
		# F1 pages the help ticker; F6 toggles it, but only as the Esc+F6 chord, so plain
		# F6 stays free for Thor above.
		"drift_help_next": [_key_ev(0, KEY_F1)],
		"drift_help_toggle": [_key_ev(0, KEY_F6)],
		"drift_menu_connect": [_key_ev(0, ENTER_KEYCODE)],
		"drift_menu_offline": [_key_ev(0, DEFAULT_O)],
		# Connect-screen only. Was the Down arrow, which is now thrust-reverse.
		"drift_open_map_editor": [_key_ev(0, KEY_F10)],
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
