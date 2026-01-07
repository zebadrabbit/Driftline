extends Control

# Client-only: do not modify shared/ sim state here.

signal back_requested

const DriftActions = preload("res://client/input/actions.gd")
const InputCaptureModal = preload("res://client/ui/InputCaptureModal.gd")

@onready var _master_slider: HSlider = $Root/Panel/VBox/Sliders/MasterRow/MasterSlider
@onready var _sfx_slider: HSlider = $Root/Panel/VBox/Sliders/SfxRow/SfxSlider
@onready var _music_slider: HSlider = $Root/Panel/VBox/Sliders/MusicRow/MusicSlider
@onready var _ui_slider: HSlider = $Root/Panel/VBox/Sliders/UiRow/UiSlider

@onready var _show_minimap_toggle: CheckBox = $Root/Panel/VBox/Buttons/UiToggles/ShowMinimapToggle
@onready var _help_ticker_toggle: CheckBox = $Root/Panel/VBox/Buttons/UiToggles/HelpTickerToggle

@onready var _keybinds_btn: Button = $Root/Panel/VBox/Buttons/KeybindsButton
@onready var _reset_btn: Button = $Root/Panel/VBox/Buttons/ResetButton
@onready var _apply_btn: Button = $Root/Panel/VBox/Buttons/ApplyButton
@onready var _close_btn: Button = $Root/Panel/VBox/Buttons/CloseButton

@onready var _panel: Control = $Root/Panel

@onready var _keybinds_panel: Control = $Root/KeybindsPanel
@onready var _keybinds_rows: VBoxContainer = $Root/KeybindsPanel/VBox/Scroll/Rows
@onready var _keybinds_reset_all_btn: Button = $Root/KeybindsPanel/VBox/Buttons/ResetAllButton
@onready var _keybinds_back_btn: Button = $Root/KeybindsPanel/VBox/Buttons/BackButton

@onready var _capture_modal: InputCaptureModal = $Root/CaptureOverlay

@onready var _rebind_conflict_dialog: ConfirmationDialog = $RebindConflictDialog

var _refreshing: bool = false

var _kb_row_refs: Dictionary = {} # action -> {"bind1": Label, "bind2": Label}

var _pending_capture_action: String = ""
var _pending_capture_slot: int = 0

var _pending_capture_event: InputEvent = null
var _pending_conflict_action: String = ""


func _ready() -> void:
	_keybinds_btn.disabled = false
	_keybinds_btn.pressed.connect(_on_keybinds_pressed)
	_master_slider.value_changed.connect(_on_slider_changed)
	_sfx_slider.value_changed.connect(_on_slider_changed)
	_music_slider.value_changed.connect(_on_slider_changed)
	_ui_slider.value_changed.connect(_on_slider_changed)
	_show_minimap_toggle.toggled.connect(_on_ui_toggle_changed)
	_help_ticker_toggle.toggled.connect(_on_ui_toggle_changed)
	_reset_btn.pressed.connect(_on_reset_pressed)
	_apply_btn.pressed.connect(_on_apply_pressed)
	_close_btn.pressed.connect(_on_close_pressed)
	_keybinds_back_btn.pressed.connect(_on_keybinds_back_pressed)
	_keybinds_reset_all_btn.pressed.connect(_on_reset_all_keybinds_pressed)
	if _capture_modal != null:
		_capture_modal.captured.connect(_on_capture_modal_captured)
		_capture_modal.capture_cancelled.connect(_on_capture_modal_cancelled)
	if _rebind_conflict_dialog != null:
		_rebind_conflict_dialog.confirmed.connect(_on_rebind_conflict_confirmed)
		_rebind_conflict_dialog.canceled.connect(_on_rebind_conflict_canceled)
	_refresh_from_settings()


func _refresh_from_settings() -> void:
	_refreshing = true
	var settings_ok: bool = (typeof(Settings) != TYPE_NIL and Settings != null)
	if settings_ok:
		_master_slider.value = float(Settings.get_value("audio.master_db", 0.0))
		_sfx_slider.value = float(Settings.get_value("audio.sfx_db", 0.0))
		_music_slider.value = float(Settings.get_value("audio.music_db", 0.0))
		_ui_slider.value = float(Settings.get_value("audio.ui_db", 0.0))
		_show_minimap_toggle.button_pressed = bool(Settings.get_value("ui.show_minimap", true))
		_help_ticker_toggle.button_pressed = bool(Settings.get_value("ui.help_ticker_enabled", true))
	else:
		_master_slider.value = 0.0
		_sfx_slider.value = 0.0
		_music_slider.value = 0.0
		_ui_slider.value = 0.0
		_show_minimap_toggle.button_pressed = true
		_help_ticker_toggle.button_pressed = true
	_refreshing = false


func _on_slider_changed(_value: float) -> void:
	if _refreshing:
		return
	if typeof(Settings) == TYPE_NIL or Settings == null:
		return
	Settings.set_value("audio.master_db", float(_master_slider.value))
	Settings.set_value("audio.sfx_db", float(_sfx_slider.value))
	Settings.set_value("audio.music_db", float(_music_slider.value))
	Settings.set_value("audio.ui_db", float(_ui_slider.value))
	Settings.apply_audio()


func _on_ui_toggle_changed(_pressed: bool) -> void:
	if _refreshing:
		return
	if typeof(Settings) == TYPE_NIL or Settings == null:
		return
	Settings.set_value("ui.show_minimap", bool(_show_minimap_toggle.button_pressed))
	Settings.set_value("ui.help_ticker_enabled", bool(_help_ticker_toggle.button_pressed))


func _on_reset_pressed() -> void:
	if typeof(Settings) == TYPE_NIL or Settings == null:
		return
	Settings.reset_to_defaults()
	_refresh_from_settings()
	_refresh_keybinds_from_inputmap()


func _on_apply_pressed() -> void:
	if typeof(Settings) == TYPE_NIL or Settings == null:
		return
	# SettingsManager already queues saves on change; Apply forces an immediate flush.
	Settings.save_settings()


func _on_close_pressed() -> void:
	if typeof(Settings) != TYPE_NIL and Settings != null:
		# Match "save-on-change" semantics, but flush once before closing.
		Settings.save_settings()
	back_requested.emit()
	queue_free()


func _on_keybinds_pressed() -> void:
	if _panel != null:
		_panel.visible = false
	if _keybinds_panel != null:
		_keybinds_panel.visible = true
	_build_keybinds_rows_if_needed()
	_refresh_keybinds_from_inputmap()


func _on_keybinds_back_pressed() -> void:
	_cancel_capture()
	if _keybinds_panel != null:
		_keybinds_panel.visible = false
	if _panel != null:
		_panel.visible = true


func _build_keybinds_rows_if_needed() -> void:
	if _keybinds_rows == null:
		return
	if _keybinds_rows.get_child_count() > 0:
		return
	_kb_row_refs.clear()

	for action in DriftActions.REBINDABLE_ACTIONS:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_keybinds_rows.add_child(row)

		var label := Label.new()
		label.text = str(DriftActions.ACTION_LABELS.get(action, action))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var bind1 := Label.new()
		bind1.custom_minimum_size = Vector2(110, 0)
		row.add_child(bind1)

		var bind2 := Label.new()
		bind2.custom_minimum_size = Vector2(110, 0)
		row.add_child(bind2)

		var rb1 := Button.new()
		rb1.text = "Rebind #1"
		rb1.pressed.connect(_on_rebind_pressed.bind(action, 0))
		row.add_child(rb1)

		var rb2 := Button.new()
		rb2.text = "Rebind #2"
		rb2.pressed.connect(_on_rebind_pressed.bind(action, 1))
		row.add_child(rb2)

		var clear_btn := Button.new()
		clear_btn.text = "Clear"
		clear_btn.pressed.connect(_on_clear_action_pressed.bind(action))
		row.add_child(clear_btn)

		var reset_btn := Button.new()
		reset_btn.text = "Reset action"
		reset_btn.pressed.connect(_on_reset_action_pressed.bind(action))
		row.add_child(reset_btn)

		_kb_row_refs[action] = {"bind1": bind1, "bind2": bind2}


func _refresh_keybinds_from_inputmap() -> void:
	for action_any in _kb_row_refs.keys():
		var action: String = str(action_any)
		var refs: Dictionary = _kb_row_refs.get(action, {})
		var b1: Label = refs.get("bind1", null)
		var b2: Label = refs.get("bind2", null)
		if b1 == null or b2 == null:
			continue
		var events: Array = InputMap.action_get_events(action)
		var ev1: InputEvent = events[0] if events.size() > 0 and (events[0] is InputEvent) else null
		var ev2: InputEvent = events[1] if events.size() > 1 and (events[1] is InputEvent) else null
		b1.text = format_input_event(ev1)
		b2.text = "" if ev2 == null else format_input_event(ev2)


func _on_rebind_pressed(action: String, slot: int) -> void:
	_pending_capture_action = String(action)
	_pending_capture_slot = int(slot)
	if _capture_modal != null:
		_capture_modal.begin("Press a key... (Esc cancels)")


func _on_clear_action_pressed(action: String) -> void:
	if typeof(Settings) == TYPE_NIL or Settings == null:
		return
	var bindings_any: Variant = Settings.get_value("controls.bindings", {})
	var bindings: Dictionary = {}
	if typeof(bindings_any) == TYPE_DICTIONARY:
		bindings = Dictionary(bindings_any).duplicate(true)
	# Explicit empty array means "unbound" (no default fallback).
	bindings[action] = []
	Settings.set_value("controls.bindings", bindings)
	Settings.reapply_bindings_from_settings()
	_refresh_keybinds_from_inputmap()


func _on_reset_action_pressed(action: String) -> void:
	if typeof(Settings) == TYPE_NIL or Settings == null:
		return
	var bindings_any: Variant = Settings.get_value("controls.bindings", {})
	var bindings: Dictionary = {}
	if typeof(bindings_any) == TYPE_DICTIONARY:
		bindings = Dictionary(bindings_any).duplicate(true)
	bindings[action] = _serialized_default_bindings_for_action(action)
	Settings.set_value("controls.bindings", bindings)
	Settings.reapply_bindings_from_settings()
	_refresh_keybinds_from_inputmap()


func _on_reset_all_keybinds_pressed() -> void:
	if typeof(Settings) == TYPE_NIL or Settings == null:
		return
	var bindings: Dictionary = {}
	for action in DriftActions.REBINDABLE_ACTIONS:
		bindings[String(action)] = _serialized_default_bindings_for_action(String(action))
	Settings.set_value("controls.bindings", bindings)
	Settings.reapply_bindings_from_settings()
	_refresh_keybinds_from_inputmap()


func _serialized_default_bindings_for_action(action: String) -> Array:
	var out: Array = []
	var def_any: Variant = DriftActions.DEFAULT_BINDINGS.get(action, [])
	if typeof(def_any) != TYPE_ARRAY:
		return out
	var def_events: Array = def_any
	for ev_any in def_events:
		var ev: InputEvent = ev_any
		if ev == null:
			continue
		out.append(SettingsManager.serialize_input_event(ev))
	return out


func _cancel_capture() -> void:
	_pending_capture_action = ""
	_pending_capture_slot = 0
	if _capture_modal != null:
		_capture_modal.cancel()


func _on_capture_modal_cancelled() -> void:
	_pending_capture_action = ""
	_pending_capture_slot = 0
	_pending_capture_event = null
	_pending_conflict_action = ""


func _on_capture_modal_captured(ev: InputEvent) -> void:
	if _pending_capture_action == "":
		return
	var conflict: String = _find_conflicting_action(_pending_capture_action, ev)
	if conflict != "":
		_pending_capture_event = ev
		_pending_conflict_action = conflict
		if _rebind_conflict_dialog != null:
			var a_label := str(DriftActions.ACTION_LABELS.get(_pending_capture_action, _pending_capture_action))
			var b_label := str(DriftActions.ACTION_LABELS.get(conflict, conflict))
			_rebind_conflict_dialog.dialog_text = "This input is currently bound to %s. Reassign to %s?" % [b_label, a_label]
			_rebind_conflict_dialog.popup_centered()
		else:
			# No dialog available; default to cancel.
			_pending_capture_action = ""
			_pending_capture_slot = 0
			_pending_capture_event = null
			_pending_conflict_action = ""
		return

	_apply_captured_binding(_pending_capture_action, _pending_capture_slot, ev)
	_pending_capture_action = ""
	_pending_capture_slot = 0
	_pending_capture_event = null
	_pending_conflict_action = ""


func _on_rebind_conflict_confirmed() -> void:
	if typeof(Settings) == TYPE_NIL or Settings == null:
		_on_rebind_conflict_canceled()
		return
	if _pending_capture_action == "" or _pending_conflict_action == "" or _pending_capture_event == null:
		_on_rebind_conflict_canceled()
		return

	# Update settings for BOTH actions, then rebuild bindings.
	var bindings_any: Variant = Settings.get_value("controls.bindings", {})
	var bindings: Dictionary = {}
	if typeof(bindings_any) == TYPE_DICTIONARY:
		bindings = Dictionary(bindings_any).duplicate(true)

	# Remove equivalent binding from conflict action.
	_remove_equivalent_event_from_bindings(bindings, _pending_conflict_action, _pending_capture_event)

	# Apply to target action at requested slot.
	_apply_captured_binding_with_bindings_dict(bindings, _pending_capture_action, _pending_capture_slot, _pending_capture_event)

	Settings.set_value("controls.bindings", bindings)
	Settings.reapply_bindings_from_settings()
	_refresh_keybinds_from_inputmap()

	_pending_capture_action = ""
	_pending_capture_slot = 0
	_pending_capture_event = null
	_pending_conflict_action = ""


func _on_rebind_conflict_canceled() -> void:
	_pending_capture_action = ""
	_pending_capture_slot = 0
	_pending_capture_event = null
	_pending_conflict_action = ""


func _find_conflicting_action(target_action: String, ev: InputEvent) -> String:
	for a in DriftActions.REBINDABLE_ACTIONS:
		var action := String(a)
		if action == target_action:
			continue
		if not InputMap.has_action(action):
			continue
		var events: Array = InputMap.action_get_events(action)
		for existing_any in events:
			var existing: InputEvent = existing_any
			if existing == null:
				continue
			if _events_equivalent(existing, ev):
				return action
	return ""


func _events_equivalent(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false
	if a.get_class() != b.get_class():
		return false

	if a is InputEventKey and b is InputEventKey:
		var ak: InputEventKey = a
		var bk: InputEventKey = b
		var acode: int = int(ak.physical_keycode) if int(ak.physical_keycode) != 0 else int(ak.keycode)
		var bcode: int = int(bk.physical_keycode) if int(bk.physical_keycode) != 0 else int(bk.keycode)
		return acode == bcode \
			and bool(ak.shift_pressed) == bool(bk.shift_pressed) \
			and bool(ak.ctrl_pressed) == bool(bk.ctrl_pressed) \
			and bool(ak.alt_pressed) == bool(bk.alt_pressed) \
			and bool(ak.meta_pressed) == bool(bk.meta_pressed)

	if a is InputEventMouseButton and b is InputEventMouseButton:
		var am: InputEventMouseButton = a
		var bm: InputEventMouseButton = b
		return int(am.button_index) == int(bm.button_index)

	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		var aj: InputEventJoypadButton = a
		var bj: InputEventJoypadButton = b
		return int(aj.button_index) == int(bj.button_index)

	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		var ajm: InputEventJoypadMotion = a
		var bjm: InputEventJoypadMotion = b
		return int(ajm.axis) == int(bjm.axis) and _axis_sign(ajm) == _axis_sign(bjm)

	return false


func _axis_sign(jm: InputEventJoypadMotion) -> int:
	var v := float(jm.axis_value)
	if v > 0.0:
		return 1
	if v < 0.0:
		return -1
	return 0


func _remove_equivalent_event_from_bindings(bindings: Dictionary, action: String, ev: InputEvent) -> void:
	var list_any: Variant = bindings.get(action, [])
	if typeof(list_any) != TYPE_ARRAY:
		return
	var list: Array = list_any
	var filtered: Array = []
	for d_any in list:
		if typeof(d_any) != TYPE_DICTIONARY:
			continue
		var existing: InputEvent = SettingsManager.deserialize_input_event(Dictionary(d_any))
		if existing != null and _events_equivalent(existing, ev):
			continue
		filtered.append(d_any)
	bindings[action] = filtered


func _apply_captured_binding_with_bindings_dict(bindings: Dictionary, action: String, slot: int, ev: InputEvent) -> void:
	# Keep current action events (from InputMap) as baseline.
	var current_events: Array = InputMap.action_get_events(action)
	var a0: InputEvent = current_events[0] if current_events.size() > 0 and (current_events[0] is InputEvent) else null
	var a1: InputEvent = current_events[1] if current_events.size() > 1 and (current_events[1] is InputEvent) else null

	if int(slot) == 0:
		a0 = ev
		if a1 != null and _events_equivalent(a1, ev):
			a1 = null
	else:
		a1 = ev
		if a0 != null and _events_equivalent(a0, ev):
			a0 = null

	var out: Array = []
	if a0 != null:
		out.append(SettingsManager.serialize_input_event(a0))
	if a1 != null:
		out.append(SettingsManager.serialize_input_event(a1))
	bindings[action] = out


func _apply_captured_binding(action: String, slot: int, ev: InputEvent) -> void:
	if typeof(Settings) == TYPE_NIL or Settings == null:
		return
	var bindings_any: Variant = Settings.get_value("controls.bindings", {})
	var bindings: Dictionary = {}
	if typeof(bindings_any) == TYPE_DICTIONARY:
		bindings = Dictionary(bindings_any).duplicate(true)
	_apply_captured_binding_with_bindings_dict(bindings, action, slot, ev)
	Settings.set_value("controls.bindings", bindings)
	Settings.reapply_bindings_from_settings()
	_refresh_keybinds_from_inputmap()


func format_input_event(ev: InputEvent) -> String:
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
		var key_text := ""
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
		parts2.append(_mouse_button_short_name(int(m.button_index)))
		return "+".join(parts2)

	if ev is InputEventJoypadButton:
		var jb: InputEventJoypadButton = ev
		return "Joy %s" % _joy_button_name(int(jb.button_index))

	if ev is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = ev
		var sign := "+" if float(jm.axis_value) > 0.0 else ("-" if float(jm.axis_value) < 0.0 else "")
		return "Joy Axis %d %s" % [int(jm.axis), sign]

	return str(ev)


func _mouse_button_short_name(idx: int) -> String:
	match idx:
		MOUSE_BUTTON_LEFT:
			return "Mouse1"
		MOUSE_BUTTON_RIGHT:
			return "Mouse2"
		MOUSE_BUTTON_MIDDLE:
			return "Mouse3"
		MOUSE_BUTTON_WHEEL_UP:
			return "WheelUp"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "WheelDown"
		MOUSE_BUTTON_WHEEL_LEFT:
			return "WheelLeft"
		MOUSE_BUTTON_WHEEL_RIGHT:
			return "WheelRight"
		MOUSE_BUTTON_XBUTTON1:
			return "MouseX1"
		MOUSE_BUTTON_XBUTTON2:
			return "MouseX2"
		_:
			return "Mouse%d" % idx


func _joy_button_name(idx: int) -> String:
	match idx:
		JOY_BUTTON_A:
			return "A"
		JOY_BUTTON_B:
			return "B"
		JOY_BUTTON_X:
			return "X"
		JOY_BUTTON_Y:
			return "Y"
		JOY_BUTTON_LEFT_SHOULDER:
			return "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "RB"
		JOY_BUTTON_BACK:
			return "Back"
		JOY_BUTTON_START:
			return "Start"
		JOY_BUTTON_LEFT_STICK:
			return "LStick"
		JOY_BUTTON_RIGHT_STICK:
			return "RStick"
		JOY_BUTTON_DPAD_UP:
			return "DPadUp"
		JOY_BUTTON_DPAD_DOWN:
			return "DPadDown"
		JOY_BUTTON_DPAD_LEFT:
			return "DPadLeft"
		JOY_BUTTON_DPAD_RIGHT:
			return "DPadRight"
		_:
			return "Btn%d" % idx
