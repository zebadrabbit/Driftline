## Music jukebox: shuffled autoplay of all tracks in res://client/audio/music/.
## Add as a child node of the scene tree; it self-manages.
extends Node

const MUSIC_DIR: String = "res://client/audio/music/"
const BUS_NAME: String = "Music"
const FADE_SECS: float = 2.0

var _player_a: AudioStreamPlayer = null
var _player_b: AudioStreamPlayer = null
var _incoming: AudioStreamPlayer = null  # non-null while crossfading
var _outgoing: AudioStreamPlayer = null

var _playlist: Array = []
var _cursor: int = 0
var _fade_t: float = 0.0


func _ready() -> void:
	_player_a = _make_player("MusicA")
	_player_b = _make_player("MusicB")
	_build_playlist()
	if _playlist.size() > 0:
		_start_track(_player_a)


func skip_next() -> void:
	_advance()
	_crossfade_to(_other(_outgoing if _outgoing != null else _incoming))


func _make_player(pname: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = pname
	p.bus = BUS_NAME
	p.volume_db = -80.0
	add_child(p)
	return p


func _other(p: AudioStreamPlayer) -> AudioStreamPlayer:
	return _player_b if p == _player_a else _player_a


func _build_playlist() -> void:
	_playlist.clear()
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and (fname.ends_with(".wav") or fname.ends_with(".ogg") or fname.ends_with(".mp3")):
			_playlist.append(MUSIC_DIR + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	_playlist.shuffle()


func _start_track(player: AudioStreamPlayer) -> void:
	var stream = load(_playlist[_cursor])
	if not (stream is AudioStream):
		_advance()
		return
	player.stream = stream
	player.volume_db = 0.0
	player.play()
	if not player.finished.is_connected(_on_finished):
		player.finished.connect(_on_finished)
	_incoming = null
	_outgoing = null


func _on_finished() -> void:
	_advance()
	var current: AudioStreamPlayer = _player_a if (_incoming == null and _player_a.playing) or _incoming == _player_a else _player_b
	_crossfade_to(_other(current))


func _advance() -> void:
	_cursor = (_cursor + 1) % _playlist.size()
	if _cursor == 0:
		_playlist.shuffle()


func _crossfade_to(target: AudioStreamPlayer) -> void:
	if _incoming != null:
		# Already fading; just let it finish.
		return
	var stream = load(_playlist[_cursor])
	if not (stream is AudioStream):
		return
	target.stream = stream
	target.volume_db = -80.0
	target.play()
	if not target.finished.is_connected(_on_finished):
		target.finished.connect(_on_finished)
	_outgoing = _other(target)
	_incoming = target
	_fade_t = 0.0


func _process(delta: float) -> void:
	if _incoming == null:
		return
	_fade_t = minf(_fade_t + delta / FADE_SECS, 1.0)
	_incoming.volume_db = lerpf(-80.0, 0.0, _fade_t)
	if _outgoing != null:
		_outgoing.volume_db = lerpf(0.0, -80.0, _fade_t)
		if _fade_t >= 1.0:
			_outgoing.stop()
	if _fade_t >= 1.0:
		_incoming = null
		_outgoing = null
