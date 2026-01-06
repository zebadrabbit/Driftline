extends Control

# Client-only: do not modify shared/ sim state here.

signal back_requested

const ACTIONS_ORDER: Array[String] = [
	"thrust_forward",
	"thrust_backward",
	"turn_left",
	"turn_right",
	"fire_primary",
	"fire_secondary",
	"afterburner",
	"drift_help_toggle",
	"drift_help_next",
]

const ACTION_LABELS: Dictionary = {
	"thrust_forward": "Thrust Forward",
	"thrust_backward": "Thrust Backward",
	"turn_left": "Turn Left",
	"turn_right": "Turn Right",
	"fire_primary": "Fire Primary",
	"fire_secondary": "Fire Secondary",
	"afterburner": "Afterburner",
	"drift_help_toggle": "Help Toggle",
	"drift_help_next": "Help Next",
}

@onready var _rows: VBoxContainer = $Root/Panel/VBox/Rows
@onready var _status: Label = $Root/Panel/VBox/Status
@onready var _back_btn: Button = $Root/Panel/VBox/Buttons/BackButton

@onready var _conflict_dialog: ConfirmationDialog = $ConflictDialog

var _action_buttons: Dictionary = {} # Dictionary[String, Button]

var _listening_action: String = ""
var _pending_conflict_action: String = ""
var _pending_event: InputEvent = null


func _ready() -> void:
	_back_btn.pressed.connect(_on_back_pressed)
	_conflict_dialog.confirmed.connect(_on_conflict_replace_confirmed)
	_conflict_dialog.canceled.connect(_on_conflict_replace_canceled)
	_build_rows()
	_refresh_all()


func _build_rows() -> void:
	# Clear existing children (if any).
	for c in _rows.get_children():
		c.queue_free()
	_action_buttons.clear()

	for action in ACTIONS_ORDER:
		if not InputMap.has_action(action):
			continue

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rows.add_child(row)

		var label := Label.new()
		label.text = str(ACTION_LABELS.get(action, action))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var btn := Button.new()
		btn.text = ""
		btn.pressed.connect(_on_action_button_pressed.bind(action))
		row.add_child(btn)

		_action_buttons[action] = btn


func _refresh_all() -> void:
	for action_any in _action_buttons.keys():
		var action: String = str(action_any)
		_refresh_action(action)
	_update_status_text()


func _refresh_action(action: String) -> void:
	var btn_any: Variant = _action_buttons.get(action, null)
	if btn_any == null:
		return
	var btn: Button = btn_any

	var ev: InputEvent = _get_primary_event_for_action(action)
	if ev == null:
		btn.text = "Unbound"
	else:
		btn.text = pretty_event(ev)

	btn.disabled = (_listening_action != "" and _listening_action != action)


func _update_status_text() -> void:
	if _listening_action == "":
		_status.text = "Click an action, then press a key or mouse button. (Esc cancels)"
		return
	_status.text = "Listening for: %s (Esc cancels)" % [str(ACTION_LABELS.get(_listening_action, _listening_action))]


func _on_action_button_pressed(action: String) -> void:
	if _listening_action == action:
		_cancel_listening()
		return
	_listening_action = action
	_update_status_text()
	_refresh_all()


func _unhandled_input(event: InputEvent) -> void:
	if _listening_action == "":
		return

	# Cancel listening using the built-in UI cancel action (Escape by default).
	if event.is_action_pressed("ui_cancel"):
		_cancel_listening()
		get_viewport().set_input_as_handled()
		return

	var captured: InputEvent = _capture_event_for_binding(event)
	if captured == null:
		return

	# Check conflicts.
	var conflict: String = _find_conflicting_action(_listening_action, captured)
	if conflict != "":
		_pending_conflict_action = conflict
		_pending_event = captured
		_conflict_dialog.title = "Keybind Conflict"
		_conflict_dialog.ok_button_text = "Replace"
		_conflict_dialog.cancel_button_text = "Cancel"
		_conflict_dialog.dialog_text = "This input is already bound to '%s'. Replace it?" % [str(ACTION_LABELS.get(conflict, conflict))]
		_conflict_dialog.popup_centered()
		get_viewport().set_input_as_handled()
		return

	_apply_binding(_listening_action, captured)
	_cancel_listening()
	get_viewport().set_input_as_handled()


func _capture_event_for_binding(event: InputEvent) -> InputEvent:
	# Keyboard.
	if event is InputEventKey:
		var k: InputEventKey = event
		if not k.pressed or k.echo:
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
		var nm := InputEventMouseButton.new()
		nm.device = int(m.device)
		nm.button_index = int(m.button_index)
		nm.shift_pressed = bool(m.shift_pressed)
		nm.ctrl_pressed = bool(m.ctrl_pressed)
		nm.alt_pressed = bool(m.alt_pressed)
		nm.meta_pressed = bool(m.meta_pressed)
		nm.pressed = false
		return nm

	return null


func _find_conflicting_action(target_action: String, ev: InputEvent) -> String:
	var ev_d: Dictionary = SettingsManager.event_to_dict(ev)
	for a_any in _action_buttons.keys():
		var action: String = str(a_any)
		if action == target_action:
			continue
		var events: Array = InputMap.action_get_events(action)
		for existing_any in events:
			var existing: InputEvent = existing_any
			if existing == null:
				continue
			if SettingsManager.event_to_dict(existing) == ev_d:
				return action
	return ""


func _apply_binding(action: String, ev: InputEvent) -> void:
	var settings: Node = get_node_or_null("/root/Settings")
	if settings == null:
		return
	if settings.current == null:
		settings.load_settings()
	if settings.current == null:
		return

	if typeof(settings.current.keybinds) != TYPE_DICTIONARY:
		settings.current.keybinds = {}

	settings.current.keybinds[action] = [SettingsManager.event_to_dict(ev)]
	settings.apply_keybinds()
	settings.save_settings()
	_refresh_action(action)


func _remove_binding_event(action: String, ev: InputEvent) -> void:
	var settings: Node = get_node_or_null("/root/Settings")
	if settings == null or settings.current == null:
		return
	if typeof(settings.current.keybinds) != TYPE_DICTIONARY:
		return

	var list_any: Variant = settings.current.keybinds.get(action, [])
	if typeof(list_any) != TYPE_ARRAY:
		return
	var list: Array = list_any

	var ev_d: Dictionary = SettingsManager.event_to_dict(ev)
	var filtered: Array = []
	for d_any in list:
		if typeof(d_any) != TYPE_DICTIONARY:
			continue
		if Dictionary(d_any) == ev_d:
			continue
		filtered.append(d_any)
	settings.current.keybinds[action] = filtered


func _on_conflict_replace_confirmed() -> void:
	if _pending_event == null:
		_cancel_listening()
		return
	# Remove the event from the other action, then bind it to the listening action.
	_remove_binding_event(_pending_conflict_action, _pending_event)
	_apply_binding(_listening_action, _pending_event)
	_pending_conflict_action = ""
	_pending_event = null
	_cancel_listening()


func _on_conflict_replace_canceled() -> void:
	_pending_conflict_action = ""
	_pending_event = null
	_cancel_listening()


func _cancel_listening() -> void:
	_listening_action = ""
	_update_status_text()
	_refresh_all()


func _on_back_pressed() -> void:
	back_requested.emit()
	queue_free()


func _get_primary_event_for_action(action: String) -> InputEvent:
	var events: Array = InputMap.action_get_events(action)
	if events.size() <= 0:
		return null
	var ev_any: Variant = events[0]
	if ev_any is InputEvent:
		return ev_any
	return null


func pretty_event(ev: InputEvent) -> String:
	if ev == null:
		return "Unbound"

	if ev is InputEventKey:
		var k: InputEventKey = ev
		var parts: Array[String] = []
		if k.ctrl_pressed:
			parts.append("Ctrl")
		if k.alt_pressed:
			parts.append("Alt")
		if k.shift_pressed:
			parts.append("Shift")
		if k.meta_pressed:
			parts.append("Meta")
		var key_text: String = ""
		if int(k.keycode) != 0:
			key_text = OS.get_keycode_string(int(k.keycode))
		elif int(k.physical_keycode) != 0:
			key_text = OS.get_keycode_string(int(k.physical_keycode))
		else:
			key_text = "(Key)"
		parts.append(key_text)
		return "+".join(parts)

	if ev is InputEventMouseButton:
		var m: InputEventMouseButton = ev
		var parts2: Array[String] = []
		if m.ctrl_pressed:
			parts2.append("Ctrl")
		if m.alt_pressed:
			parts2.append("Alt")
		if m.shift_pressed:
			parts2.append("Shift")
		if m.meta_pressed:
			parts2.append("Meta")
		parts2.append(_mouse_button_name(int(m.button_index)))
		return "+".join(parts2)

	return str(ev)


func _mouse_button_name(idx: int) -> String:
	match idx:
		MOUSE_BUTTON_LEFT:
			return "Mouse Left"
		MOUSE_BUTTON_RIGHT:
			return "Mouse Right"
		MOUSE_BUTTON_MIDDLE:
			return "Mouse Middle"
		MOUSE_BUTTON_WHEEL_UP:
			return "Wheel Up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Wheel Down"
		MOUSE_BUTTON_WHEEL_LEFT:
			return "Wheel Left"
		MOUSE_BUTTON_WHEEL_RIGHT:
			return "Wheel Right"
		MOUSE_BUTTON_XBUTTON1:
			return "Mouse X1"
		MOUSE_BUTTON_XBUTTON2:
			return "Mouse X2"
		_:
			return "Mouse %d" % idx
