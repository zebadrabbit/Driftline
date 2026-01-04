## Client-only team/friendliness color mapping.
##
## Requirements:
## - Friendliness derived from replicated ship.freq.
## - Client never applies freq from UI or set-freq result packets.

class_name DriftTeamColors

# SpriteFontLabel palette indices (see client/SpriteFontLabel.gd):
# [white, green, light blue, red, orange, purple, dark orange, pink]
const NAMEPLATE_FRIENDLY_COLOR_INDEX: int = 1 # green
const NAMEPLATE_ENEMY_COLOR_INDEX: int = 3 # red

# Bitmask flags for role/condition-based overrides.
const FLAG_OBJECTIVE_CARRIER: int = 1 << 0
const FLAG_DEAD: int = 1 << 1
const FLAG_SAFE: int = 1 << 2
const FLAG_SPAWN_PROTECT: int = 1 << 3

# Reserved priority color for high-salience roles (e.g., objective carrier).
# Chosen to be uncommon in current HUD/nameplate usage.
const NAMEPLATE_PRIORITY_COLOR_INDEX: int = 5 # purple

# Radar/minimap marker shape hints.
# Rendering should ensure the local player is visually distinct by shape, not just color.
const RADAR_SHAPE_DOT: int = 0
const RADAR_SHAPE_TRIANGLE: int = 1
const RADAR_SHAPE_RING: int = 2

const RADAR_PRIORITY_MARKER_COLOR: Color = Color(0.70, 0.35, 1.0, 1.0) # readable "purple" on dark backgrounds

static func is_friendly(my_freq: int, other_freq: int) -> bool:
	return int(other_freq) == int(my_freq)

static func get_nameplate_color_index(my_freq: int, other_freq: int, flags := 0) -> int:
	var flags_i: int = int(flags)
	if (flags_i & FLAG_OBJECTIVE_CARRIER) != 0:
		return NAMEPLATE_PRIORITY_COLOR_INDEX
	return NAMEPLATE_FRIENDLY_COLOR_INDEX if is_friendly(my_freq, other_freq) else NAMEPLATE_ENEMY_COLOR_INDEX

static func nameplate_color_index(my_freq: int, other_freq: int) -> int:
	# Back-compat wrapper: callers without flags keep the original behavior.
	return get_nameplate_color_index(my_freq, other_freq, 0)

static func ship_marker_color(my_freq: int, other_freq: int) -> Color:
	# Colors are chosen to be readable against arena background.
	if is_friendly(my_freq, other_freq):
		return Color(0.35, 1.0, 0.55, 1.0)
	return Color(1.0, 0.25, 0.25, 1.0)

static func get_radar_dot_color(my_freq: int, other_freq: int, flags := 0) -> Color:
	var flags_i: int = int(flags)
	if (flags_i & FLAG_OBJECTIVE_CARRIER) != 0:
		return RADAR_PRIORITY_MARKER_COLOR
	return ship_marker_color(my_freq, other_freq)

static func get_radar_shape(is_self: bool, flags := 0) -> int:
	# Self must be distinguishable by shape.
	if is_self:
		return RADAR_SHAPE_RING
	return RADAR_SHAPE_DOT

static func radar_self_should_blink() -> bool:
	return true
