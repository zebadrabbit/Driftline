extends Control

# Client-only: do not modify shared/ sim state here.

signal back_requested

const KeybindsMenuScene: PackedScene = preload("res://client/ui/keybinds_menu.tscn")

@onready var _master_slider: HSlider = $Root/Panel/VBox/Sliders/MasterRow/MasterSlider
@onready var _sfx_slider: HSlider = $Root/Panel/VBox/Sliders/SfxRow/SfxSlider
@onready var _music_slider: HSlider = $Root/Panel/VBox/Sliders/MusicRow/MusicSlider
@onready var _ui_slider: HSlider = $Root/Panel/VBox/Sliders/UiRow/UiSlider

@onready var _keybinds_btn: Button = $Root/Panel/VBox/Buttons/KeybindsButton
@onready var _reset_btn: Button = $Root/Panel/VBox/Buttons/ResetButton
@onready var _back_btn: Button = $Root/Panel/VBox/Buttons/BackButton

@onready var _panel: Control = $Root/Panel

var _refreshing: bool = false
var _keybinds_menu_instance: Control = null


func _ready() -> void:
	_keybinds_btn.disabled = false
	_keybinds_btn.pressed.connect(_on_keybinds_pressed)
	_master_slider.value_changed.connect(_on_slider_changed)
	_sfx_slider.value_changed.connect(_on_slider_changed)
	_music_slider.value_changed.connect(_on_slider_changed)
	_ui_slider.value_changed.connect(_on_slider_changed)
	_reset_btn.pressed.connect(_on_reset_pressed)
	_back_btn.pressed.connect(_on_back_pressed)
	_refresh_from_settings()


func _refresh_from_settings() -> void:
	_refreshing = true
	var settings_ok: bool = (typeof(Settings) != TYPE_NIL and Settings != null and Settings.current != null)
	if settings_ok:
		_master_slider.value = float(Settings.current.master_db)
		_sfx_slider.value = float(Settings.current.sfx_db)
		_music_slider.value = float(Settings.current.music_db)
		_ui_slider.value = float(Settings.current.ui_db)
	else:
		_master_slider.value = 0.0
		_sfx_slider.value = 0.0
		_music_slider.value = 0.0
		_ui_slider.value = 0.0
	_refreshing = false


func _on_slider_changed(_value: float) -> void:
	if _refreshing:
		return
	if typeof(Settings) == TYPE_NIL or Settings == null:
		return
	if Settings.current == null:
		Settings.load_settings()
	if Settings.current == null:
		return

	Settings.current.master_db = float(_master_slider.value)
	Settings.current.sfx_db = float(_sfx_slider.value)
	Settings.current.music_db = float(_music_slider.value)
	Settings.current.ui_db = float(_ui_slider.value)
	Settings.apply_audio()
	Settings.save_settings()


func _on_reset_pressed() -> void:
	if typeof(Settings) == TYPE_NIL or Settings == null:
		return
	Settings.reset_to_defaults()
	_refresh_from_settings()


func _on_back_pressed() -> void:
	back_requested.emit()
	queue_free()


func _on_keybinds_pressed() -> void:
	if _keybinds_menu_instance != null:
		return
	_keybinds_menu_instance = KeybindsMenuScene.instantiate()
	add_child(_keybinds_menu_instance)
	if _keybinds_menu_instance.has_signal("back_requested"):
		_keybinds_menu_instance.connect("back_requested", _on_keybinds_back_requested)
	if _panel != null:
		_panel.visible = false


func _on_keybinds_back_requested() -> void:
	_keybinds_menu_instance = null
	if _panel != null:
		_panel.visible = true
