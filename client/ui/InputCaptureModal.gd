extends Control

# Client-only: do not modify shared/ sim state here.

class_name InputCaptureModal

signal captured(event: InputEvent)
signal capture_cancelled

@export var accept_mouse_wheel: bool = false
@export var joy_axis_deadzone: float = 0.5

@onready var _label: Label = get_node_or_null("Panel/Label")

var _active: bool = false
var _modifier_keycodes: Dictionary = {}


func _ready() -> void:
	# Full-screen overlay that blocks clicks behind it.
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_hide_internal()

	# Avoid hardcoded key constants (repo policy). Resolve via OS helper.
	_modifier_keycodes = {
		int(OS.find_keycode_from_string("Shift")): true,
		int(OS.find_keycode_from_string("Ctrl")): true,
		int(OS.find_keycode_from_string("Alt")): true,
		int(OS.find_keycode_from_string("Meta")): true,
	}


func begin(prompt: String = "Press a key... (Esc cancels)") -> void:
	_active = true
	visible = true
	set_process_unhandled_input(true)
	grab_focus()
	if _label != null:
		_label.text = String(prompt)


func cancel() -> void:
	if not _active:
		return
	_active = false
	emit_signal("capture_cancelled")
	_hide_internal()


func _hide_internal() -> void:
	visible = false
	set_process_unhandled_input(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event == null:
		return

	# Cancel via standard UI cancel action (Escape by default).
	if event.is_action_pressed("ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()
		return

	# Ignore mouse motion.
	if event is InputEventMouseMotion:
		return

	var captured_ev: InputEvent = _capture_event_for_binding(event)
	if captured_ev == null:
		return

	_active = false
	emit_signal("captured", captured_ev)
	_hide_internal()
	get_viewport().set_input_as_handled()


func _capture_event_for_binding(event: InputEvent) -> InputEvent:
	# Keyboard.
	if event is InputEventKey:
		var k: InputEventKey = event
		if not k.pressed or k.echo:
			return null
		if _is_pure_modifier_key(k):
			return null
		var nk := InputEventKey.new()
		nk.device = int(k.device)
		nk.keycode = int(k.keycode)
		nk.physical_keycode = int(k.physical_keycode)
		nk.shift_pressed = bool(k.shift_pressed)
		nk.ctrl_pressed = bool(k.ctrl_pressed)
		nk.alt_pressed = bool(k.alt_pressed)
		nk.meta_pressed = bool(k.meta_pressed)
		nk.pressed = false
		return nk

	# Mouse buttons.
	if event is InputEventMouseButton:
		var m: InputEventMouseButton = event
		if not m.pressed:
			return null
		if not accept_mouse_wheel and _is_mouse_wheel_button(int(m.button_index)):
			return null
		var nm := InputEventMouseButton.new()
		nm.device = int(m.device)
		nm.button_index = int(m.button_index)
		nm.shift_pressed = bool(m.shift_pressed)
		nm.ctrl_pressed = bool(m.ctrl_pressed)
		nm.alt_pressed = bool(m.alt_pressed)
		nm.meta_pressed = bool(m.meta_pressed)
		nm.pressed = false
		return nm

	# Joypad buttons.
	if event is InputEventJoypadButton:
		var jb: InputEventJoypadButton = event
		if not jb.pressed:
			return null
		var nj := InputEventJoypadButton.new()
		nj.device = int(jb.device)
		nj.button_index = int(jb.button_index)
		nj.pressed = false
		return nj

	# Joypad axes.
	if event is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = event
		var v := float(jm.axis_value)
		if absf(v) < maxf(0.0, joy_axis_deadzone):
			return null
		var nmj := InputEventJoypadMotion.new()
		nmj.device = int(jm.device)
		nmj.axis = int(jm.axis)
		nmj.axis_value = 1.0 if v > 0.0 else -1.0
		return nmj

	return null


func _is_pure_modifier_key(k: InputEventKey) -> bool:
	var kc: int = int(k.keycode)
	var pkc: int = int(k.physical_keycode)
	if kc != 0 and _modifier_keycodes.has(kc):
		return true
	if pkc != 0 and _modifier_keycodes.has(pkc):
		return true
	return false


func _is_mouse_wheel_button(button_index: int) -> bool:
	return button_index == MOUSE_BUTTON_WHEEL_UP \
		or button_index == MOUSE_BUTTON_WHEEL_DOWN \
		or button_index == MOUSE_BUTTON_WHEEL_LEFT \
		or button_index == MOUSE_BUTTON_WHEEL_RIGHT
