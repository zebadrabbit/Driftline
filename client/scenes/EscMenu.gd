extends CanvasLayer

## SubSpace-style Esc menu.
##
## Layout and key assignments follow the original (original_content/controls.txt plus the
## Continuum menu screen): a two-column keyed list, options on the left, ship selection on
## the right, and "any other key" resumes.
##
## Entries whose feature does not exist in Driftline yet are listed but dimmed and inert,
## so the menu reads like the original without pretending the key does something.

signal save_bug_report_requested
signal disconnect_requested
signal ship_change_requested(ship_type: int)
signal spectate_requested
signal toggle_requested(what: StringName)
signal stat_box_size_requested(delta: int)

const OptionsMenuScene: PackedScene = preload("res://client/ui/options_menu.tscn")

const SHIP_NAMES: Array[String] = [
	"Warbird", "Javelin", "Spider", "Leviathan", "Terrier", "Weasel", "Lancaster", "Shark",
]

const COL_TITLE := "#7fe07f"
const COL_KEY := "#d8d8d8"
const COL_VAL := "#7fe07f"
const COL_SHIPS := "#e06c6c"
const COL_DIM := "#6d6d6d"
const COL_FOOT := "#e0c060"

var _is_open: bool = false
var _options_open: bool = false

@onready var _backdrop: ColorRect = $Root/Backdrop
@onready var _panel: PanelContainer = $Root/MenuPanel
var _body: RichTextLabel = null


func _ready() -> void:
	visible = false
	_is_open = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	($Root as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_body()


func _build_body() -> void:
	# Replace the old Resume/Options/Quit button list with the original's keyed menu.
	var vbox := get_node_or_null("Root/MenuPanel/VBox") as VBoxContainer
	if vbox == null:
		return
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.custom_minimum_size = Vector2(460.0, 0.0)
	_body.add_theme_font_size_override("normal_font_size", 14)
	_body.add_theme_font_size_override("mono_font_size", 14)
	vbox.add_child(_body)
	_refresh_text()


func _entry(key_text: String, label: String, available: bool = true) -> String:
	if not available:
		return "[color=%s]%s = %s[/color]" % [COL_DIM, key_text.rpad(2), label]
	return "[color=%s]%s[/color] = [color=%s]%s[/color]" % [COL_KEY, key_text.rpad(2), COL_VAL, label]


func _refresh_text() -> void:
	if _body == null:
		return
	var left: Array[String] = [
		_entry("Q", "Quit"),
		_entry("F1", "Help"),
		_entry("F2", "Stat box"),
		_entry("F3", "Name tags"),
		_entry("F4", "Radar"),
		_entry("F5", "Messages"),
		_entry("F6", "Help ticker"),
		_entry("F8", "Engine sounds"),
		_entry("C", "Options"),
		_entry("R", "Bug report"),
		_entry("A", "Arena list", false),
		_entry("B", "Set banner", false),
		_entry("I", "Ignore macros", false),
	]
	var right: Array[String] = ["[color=%s]Ships[/color]" % COL_SHIPS]
	for i in range(SHIP_NAMES.size()):
		right.append(_entry(str(i + 1), SHIP_NAMES[i]))
	right.append(_entry("S", "Spectator"))

	var t := "[center][color=%s]-= Menu =-[/color][/center]\n" % COL_TITLE
	var rows: int = maxi(left.size(), right.size())
	for i in range(rows):
		var l: String = left[i] if i < left.size() else ""
		var r: String = right[i] if i < right.size() else ""
		# Two columns via a table-free fixed indent; RichTextLabel strips trailing space,
		# so pad the visible left cell with the raw label length, not the BBCode length.
		var pad: int = maxi(0, 26 - _visible_len(l))
		t += "%s%s%s\n" % [l, " ".repeat(pad), r]
	t += "\n%s\n" % _entry("PgUp/PgDn", "Adjust stat box")
	t += "[center][color=%s]Any other key to resume game[/color][/center]" % COL_FOOT
	_body.text = t


static func _visible_len(bb: String) -> int:
	# Length of a BBCode string with its tags removed.
	var out: int = 0
	var in_tag: bool = false
	for i in range(bb.length()):
		var c: String = bb[i]
		if c == "[":
			in_tag = true
		elif c == "]":
			in_tag = false
		elif not in_tag:
			out += 1
	return out


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

	# While the options sub-menu is open, let all input fall through to it.
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
		var code: int = int(k.physical_keycode) if int(k.physical_keycode) != 0 else int(k.keycode)
		get_viewport().set_input_as_handled()

		# Ship selection is 1-8 in the original; Driftline used Esc+F1-F8 before.
		if code >= KEY_1 and code <= KEY_8:
			ship_change_requested.emit(code - KEY_1)
			close()
			return
		match code:
			KEY_Q:
				close()
				disconnect_requested.emit()
			KEY_S:
				spectate_requested.emit()
				close()
			KEY_C:
				_open_options()
			KEY_R:
				save_bug_report_requested.emit()
			KEY_F1:
				toggle_requested.emit(&"help")
			KEY_F2:
				toggle_requested.emit(&"stat_box")
			KEY_F3:
				toggle_requested.emit(&"name_tags")
			KEY_F4:
				toggle_requested.emit(&"radar")
			KEY_F5:
				toggle_requested.emit(&"messages")
			KEY_F6:
				toggle_requested.emit(&"help_ticker")
			KEY_F8:
				toggle_requested.emit(&"engine_sounds")
			KEY_PAGEUP:
				stat_box_size_requested.emit(1)
			KEY_PAGEDOWN:
				stat_box_size_requested.emit(-1)
			KEY_A, KEY_B, KEY_I:
				# Listed but not implemented. Swallow rather than fall through to
				# "any other key", which would close the menu and look like a no-op.
				pass
			_:
				close()
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


func _open_options() -> void:
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
