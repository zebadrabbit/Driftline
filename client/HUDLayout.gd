extends CanvasLayer

## Pure layout helper for SubSpace-style HUD islands.
## No gameplay logic here.
##
## Toggle `debug_show_bounds` to draw visible panel outlines/backgrounds
## so you can verify anchors/margins quickly.

@export var debug_show_bounds: bool = true

const PADDING_PX := 8


func _ready() -> void:
	if debug_show_bounds:
		_apply_debug_style()


func _apply_debug_style() -> void:
	var root := get_node_or_null("Root")
	if root == null:
		return

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.12, 0.55)
	style.border_color = Color(0.35, 0.75, 1.0, 0.9)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1

	for n in root.get_children():
		if n is Panel:
			(n as Panel).add_theme_stylebox_override("panel", style)
			(n as Panel).self_modulate = Color(1, 1, 1, 1)
		else:
			# If you wrap panels in Controls (like TopRightStack), style their Panel children.
			for c in n.get_children():
				if c is Panel:
					(c as Panel).add_theme_stylebox_override("panel", style)
					(c as Panel).self_modulate = Color(1, 1, 1, 1)
