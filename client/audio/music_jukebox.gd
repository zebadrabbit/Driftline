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
	if _playlist.is_empty():
		return
	_advance()
	_crossfade_to(_other(_current_player()))


func _current_player() -> AudioStreamPlayer:
	## Whichever player owns the audible track right now. While crossfading that is the
	## incoming one; otherwise it is whichever is actually playing.
	if _incoming != null:
		return _incoming
	return _player_a if _player_a.playing else _player_b


func _make_player(pname: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = pname
	p.bus = BUS_NAME
	p.volume_db = -80.0
	add_child(p)
	return p


func _other(p: AudioStreamPlayer) -> AudioStreamPlayer:
	return _player_b if p == _player_a else _player_a


static func scan_music_paths() -> PackedStringArray:
	## Every playable track in MUSIC_DIR, sorted, deduplicated.
	##
	## In the editor the raw "Track.ogg" is on disk. In an exported build only
	## "Track.ogg.import" is listed, so the suffix has to be stripped -- without that the
	## playlist comes back empty in a shipped game and the music is silently missing.
	var found: Dictionary = {}
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		push_warning("[Music] Cannot open %s" % MUSIC_DIR)
		return PackedStringArray()
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var base: String = fname.trim_suffix(".import") if fname.ends_with(".import") else fname
			if base.ends_with(".ogg") or base.ends_with(".wav") or base.ends_with(".mp3"):
				found[MUSIC_DIR + base] = true
		fname = dir.get_next()
	dir.list_dir_end()
	var out: Array = found.keys()
	out.sort()
	return PackedStringArray(out)


func _build_playlist() -> void:
	_playlist.clear()
	for path in scan_music_paths():
		_playlist.append(path)
	if _playlist.is_empty():
		push_warning("[Music] No tracks found in %s -- the game will run silent." % MUSIC_DIR)
	else:
		print("[Music] %d tracks loaded" % _playlist.size())
	_playlist.shuffle()


func _start_track(player: AudioStreamPlayer) -> void:
	# Skip past unloadable tracks instead of giving up: one bad file used to leave the
	# game silent for the whole session. Bounded by the playlist length so an entirely
	# broken library fails loudly rather than looping forever.
	var stream: Variant = null
	for _attempt in range(_playlist.size()):
		stream = load(_playlist[_cursor])
		if stream is AudioStream:
			break
		push_warning("[Music] Skipping unplayable track: %s" % _playlist[_cursor])
		stream = null
		_advance()
	if not (stream is AudioStream):
		push_warning("[Music] No playable tracks in %s" % MUSIC_DIR)
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
	_crossfade_to(_other(_current_player()))


func _advance() -> void:
	if _playlist.is_empty():
		return  # modulo by zero otherwise
	_cursor = (_cursor + 1) % _playlist.size()
	if _cursor == 0:
		_playlist.shuffle()


func _crossfade_to(target: AudioStreamPlayer) -> void:
	if _incoming != null:
		# Already fading; just let it finish.
		return
	if _playlist.is_empty():
		return
	# Same skip-the-bad-file behaviour as _start_track.
	var stream: Variant = null
	for _attempt in range(_playlist.size()):
		stream = load(_playlist[_cursor])
		if stream is AudioStream:
			break
		push_warning("[Music] Skipping unplayable track: %s" % _playlist[_cursor])
		stream = null
		_advance()
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
