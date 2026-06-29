extends CanvasLayer

signal save_bug_report_requested
signal disconnect_requested

const OptionsMenuScene: PackedScene = preload("res://client/ui/options_menu.tscn")

var _is_open: bool = false
var _options_open: bool = false

@onready var _backdrop: ColorRect = $Root/Backdrop
@onready var _panel: PanelContainer = $Root/MenuPanel


func _ready() -> void:
	visible = false
	_is_open = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	($Root as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_open() -> bool:
	return _is_open


func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true


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

	# While options sub-menu is open, let all input fall through to it.
	if _options_open:
		return

	if event.is_action_pressed("ui_escape_menu"):
		close()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		close()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if not _panel.get_global_rect().has_point(mb.position):
			close()
			get_viewport().set_input_as_handled()
			return
		get_viewport().set_input_as_handled()
		return


func _on_resume_pressed() -> void:
	close()


func _on_options_pressed() -> void:
	var opts = OptionsMenuScene.instantiate()
	var layer := CanvasLayer.new()
	layer.layer = 201
	layer.add_child(opts)
	add_child(layer)
	_panel.visible = false
	_options_open = true
	opts.back_requested.connect(func():
		_options_open = false
		_panel.visible = true
		layer.queue_free()
	)


func _on_bug_report_pressed() -> void:
	save_bug_report_requested.emit()


func _on_disconnect_pressed() -> void:
	close()
	disconnect_requested.emit()


func _on_quit_pressed() -> void:
	get_tree().quit()
