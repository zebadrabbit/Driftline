extends CanvasLayer

signal save_replay_requested

@export var menu_actions: PackedStringArray = [
	"ui_escape_menu",
]

var _is_open: bool = false

@onready var _root: Control = $Root
@onready var _backdrop: ColorRect = $Root/Backdrop
@onready var _panel: Control = $Root/MenuPanel
@onready var _bindings: RichTextLabel = $Root/MenuPanel/VBox/Bindings


func _ready() -> void:
	visible = false
	_is_open = false

	# Ensure the menu panel blocks clicks inside it.
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Backdrop must not consume clicks; click-away dismissal is handled in _unhandled_input.
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_open() -> bool:
	return _is_open


func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	_update_bindings_text()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return

	# While open, ONLY registered menu actions are allowed to execute.
	# Any other key/mouse button dismisses the menu.
	if event.is_action_pressed("ui_escape_menu"):
		close()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if _event_matches_any_menu_action(event):
			get_viewport().set_input_as_handled()
			return
		close()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return

		# Click-away dismissal: any mouse press outside the menu panel closes.
		var panel_rect := _panel.get_global_rect()
		if not panel_rect.has_point(mb.position):
			close()
			get_viewport().set_input_as_handled()
			return

		# If the click is inside the panel but still reached _unhandled_input,
		# treat it as consumed so it doesn't dismiss or leak to gameplay.
		get_viewport().set_input_as_handled()
		return


func _event_matches_any_menu_action(event: InputEvent) -> bool:
	for action in menu_actions:
		if action.is_empty():
			continue
		if not InputMap.has_action(action):
			continue
		if InputMap.action_has_event(action, event):
			return true
	return false


func _update_bindings_text() -> void:
	if _bindings == null:
		return

	var lines: Array[String] = []
	lines.append("Bindings:")
	for action in menu_actions:
		if action.is_empty():
			continue
		if not InputMap.has_action(action):
			lines.append("- %s: (missing action)" % action)
			continue
		var evs: Array = InputMap.action_get_events(action)
		var parts: Array[String] = []
		for ev in evs:
			if ev is InputEvent:
				var t := (ev as InputEvent).as_text()
				if not t.is_empty():
					parts.append(t)
		var joined := ", ".join(parts) if parts.size() > 0 else "(unbound)"
		lines.append("- %s: %s" % [action, joined])

	_bindings.text = "\n".join(lines)


func _on_resume_pressed() -> void:
	close()


func _on_save_replay_pressed() -> void:
	save_replay_requested.emit()
