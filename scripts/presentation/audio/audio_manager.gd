extends Node

const CROSSFADE_SEC := 1.2

var _library: AudioLibrary
var _gates := AudioGates.new()
var _rng := RandomNumberGenerator.new()
var _volumes: Dictionary = {}

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active: AudioStreamPlayer
var _music_fade_from: AudioStreamPlayer
var _music_fade_to: AudioStreamPlayer
var _music_fade_t := 0.0
var _music_fade_duration := 0.0
var _music_fade_immediate := false

var _amb_a: AudioStreamPlayer
var _amb_b: AudioStreamPlayer
var _amb_active: AudioStreamPlayer
var _amb_fade_from: AudioStreamPlayer
var _amb_fade_to: AudioStreamPlayer
var _amb_fade_t := 0.0
var _amb_fade_duration := 0.0

var _sfx_players: Array[AudioStreamPlayer] = []
var _ui_players: Array[AudioStreamPlayer] = []
var _positional_players: Array[AudioStreamPlayer2D] = []

var _engine_player: AudioStreamPlayer2D
var _engine_playing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_library = AudioLibrary.load_default()
	_rng.randomize()
	_volumes = AudioSettings.read_volumes()
	_apply_all_bus_volumes()
	_build_players()
	AudioService.bind_manager(self)


func _exit_tree() -> void:
	AudioService.unbind_manager(self)


func _build_players() -> void:
	_music_a = _make_stream_player("Music", true)
	_music_b = _make_stream_player("Music", true)
	_music_active = _music_a

	_amb_a = _make_stream_player("Ambience", true)
	_amb_b = _make_stream_player("Ambience", true)
	_amb_active = _amb_a

	for i in 8:
		_sfx_players.append(_make_stream_player("SFX", false))
	for i in 4:
		_ui_players.append(_make_stream_player("UI", true))
	for i in 4:
		var p := AudioStreamPlayer2D.new()
		p.bus = "SFX"
		p.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(p)
		_positional_players.append(p)

	_engine_player = AudioStreamPlayer2D.new()
	_engine_player.bus = "SFX"
	_engine_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_engine_player)
	var thruster_path := _library.sfx_variant_path("ship.thruster", _rng)
	_load_loop_into_player(_engine_player, thruster_path)


func _make_stream_player(bus: String, always: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.process_mode = Node.PROCESS_MODE_ALWAYS if always else Node.PROCESS_MODE_PAUSABLE
	add_child(p)
	return p


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_apply_all_bus_volumes()


func _process(delta: float) -> void:
	if _music_fade_duration > 0.0:
		_music_fade_t += delta
		var t := 1.0 if _music_fade_immediate else clampf(_music_fade_t / _music_fade_duration, 0.0, 1.0)
		if _music_fade_from != null:
			_music_fade_from.volume_db = lerpf(0.0, -80.0, t)
		if _music_fade_to != null:
			_music_fade_to.volume_db = lerpf(-80.0, 0.0, t)
		if _music_fade_t >= _music_fade_duration:
			_finish_music_fade()

	if _amb_fade_duration > 0.0:
		_amb_fade_t += delta
		var t_amb := clampf(_amb_fade_t / _amb_fade_duration, 0.0, 1.0)
		if _amb_fade_from != null:
			_amb_fade_from.volume_db = lerpf(0.0, -80.0, t_amb)
		if _amb_fade_to != null:
			_amb_fade_to.volume_db = lerpf(-80.0, 0.0, t_amb)
		if _amb_fade_t >= _amb_fade_duration:
			_finish_ambience_fade()


func get_music_context() -> String:
	return _gates.music_context


func get_ambience_context() -> String:
	return _gates.ambience_context


func is_engine_playing() -> bool:
	return _engine_playing


func get_volume(bus_key: String) -> float:
	return float(_volumes.get(bus_key, AudioSettings.DEFAULT_VOLUMES.get(bus_key, 1.0)))


func set_volume(bus_key: String, linear: float) -> void:
	if not AudioSettings.DEFAULT_VOLUMES.has(bus_key):
		return
	_volumes[bus_key] = clampf(linear, 0.0, 1.0)
	_apply_bus_volume(bus_key)
	if not AudioSettings.write_volumes(_volumes):
		push_warning("AudioManager: failed to persist audio settings.")


func play_music(context: String, immediate: bool = false) -> void:
	if not _library.has_music_context(context):
		push_warning("AudioManager: unknown music context '%s'" % context)
		return
	if not _gates.request_music(context):
		return
	var path := _library.music_track_for_context(context)
	var stream := _load_stream(path, true)
	if stream == null:
		return
	_start_music_crossfade(stream, immediate)


func stop_music(immediate: bool = false) -> void:
	_gates.clear_music()
	if _music_active == null or not _music_active.playing:
		return
	if immediate:
		_music_active.stop()
		_music_active.volume_db = 0.0
		_music_fade_duration = 0.0
		return
	_music_fade_from = _music_active
	_music_fade_to = null
	_music_fade_t = 0.0
	_music_fade_duration = CROSSFADE_SEC
	_music_fade_immediate = false


func play_ambience(context: String, immediate: bool = false) -> void:
	if not _library.has_ambience_context(context):
		push_warning("AudioManager: unknown ambience context '%s'" % context)
		return
	if not _gates.request_ambience(context):
		return
	var path := _library.ambience_track_for_context(context)
	var stream := _load_stream(path, true)
	if stream == null:
		return
	_start_ambience_crossfade(stream, immediate)


func stop_ambience(immediate: bool = false) -> void:
	_gates.clear_ambience()
	if _amb_active == null or not _amb_active.playing:
		return
	if immediate:
		_amb_active.stop()
		_amb_active.volume_db = 0.0
		_amb_fade_duration = 0.0
		return
	_amb_fade_from = _amb_active
	_amb_fade_to = null
	_amb_fade_t = 0.0
	_amb_fade_duration = CROSSFADE_SEC


## Drop stream refs on bus players (headless smoke / process exit).
func release_playback_streams() -> void:
	stop_music(true)
	stop_ambience(true)
	_music_fade_from = null
	_music_fade_to = null
	_music_fade_duration = 0.0
	_amb_fade_from = null
	_amb_fade_to = null
	_amb_fade_duration = 0.0
	for player in [_music_a, _music_b, _amb_a, _amb_b]:
		if player != null:
			player.stop()
			player.stream = null
	if _engine_player != null:
		_engine_player.stop()
		_engine_player.stream = null
	_engine_playing = false


func play_ui(suffix: String) -> void:
	play_sfx("ui.%s" % suffix)


func play_sfx(sound_id: String) -> void:
	_play_sfx_internal(sound_id, null)


func play_sfx_at(sound_id: String, world_position: Vector2) -> void:
	_play_sfx_internal(sound_id, world_position)


func set_ship_thrust(factor: float, boosting: bool, world_position: Vector2) -> void:
	if _engine_player == null:
		return
	_engine_player.global_position = world_position
	var thrusting := factor > 0.001
	if not thrusting:
		if _engine_playing:
			_engine_player.stop()
			_engine_playing = false
		return
	if not _engine_playing:
		_engine_player.play()
		_engine_playing = true
	var f := clampf(factor, 0.0, 1.0)
	var pitch := lerpf(0.85, 1.15, f)
	if boosting:
		pitch *= 1.08
	_engine_player.pitch_scale = pitch
	_engine_player.volume_db = lerpf(-18.0, -2.0, f) + (-2.0 if boosting else 0.0)


func _play_sfx_internal(sound_id: String, world_position: Variant) -> void:
	if not _library.has_sfx(sound_id):
		push_warning("AudioManager: unknown sfx '%s'" % sound_id)
		return
	var entry := _library.sfx_entry(sound_id)
	var min_interval := float(entry.get("min_interval_sec", 0.0))
	if not _gates.allow_sfx(sound_id, min_interval, Time.get_ticks_msec()):
		return
	var path := _library.sfx_variant_path(sound_id, _rng)
	var loop := bool(entry.get("loop", false))
	var stream := _load_stream(path, loop)
	if stream == null:
		return
	var bus := String(entry.get("bus", "SFX"))
	var jitter_pitch := 1.0 if loop else _rng.randf_range(0.97, 1.03)
	var jitter_vol := 0.0 if loop else _rng.randf_range(-1.0, 1.0)

	if world_position != null:
		var player := _acquire_positional_player()
		if player == null:
			return
		player.stream = stream
		player.bus = bus
		player.global_position = world_position
		player.pitch_scale = jitter_pitch
		player.volume_db = jitter_vol
		player.play()
		return

	var pool := _ui_players if bus == "UI" else _sfx_players
	var player2 := _acquire_player(pool)
	if player2 == null:
		return
	player2.stream = stream
	player2.bus = bus
	player2.pitch_scale = jitter_pitch
	player2.volume_db = jitter_vol
	if loop:
		player2.play()
	else:
		player2.play()


func _acquire_player(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for p in pool:
		if not p.playing:
			return p
	return pool[0]


func _acquire_positional_player() -> AudioStreamPlayer2D:
	for p in _positional_players:
		if not p.playing:
			return p
	return _positional_players[0]


func _start_music_crossfade(stream: AudioStream, immediate: bool) -> void:
	var inactive := _music_b if _music_active == _music_a else _music_a
	inactive.stream = stream
	inactive.volume_db = -80.0 if not immediate else 0.0
	inactive.play()
	_music_fade_from = _music_active if _music_active.playing else null
	_music_fade_to = inactive
	_music_active = inactive
	_music_fade_t = 0.0
	_music_fade_duration = 0.0 if immediate else CROSSFADE_SEC
	_music_fade_immediate = immediate
	if immediate:
		if _music_fade_from != null:
			_music_fade_from.stop()
			_music_fade_from.volume_db = 0.0
		_music_fade_to.volume_db = 0.0
		_music_fade_duration = 0.0
	elif _music_fade_from == null:
		_music_fade_to.volume_db = 0.0
		_music_fade_duration = 0.0


func _finish_music_fade() -> void:
	if _music_fade_from != null:
		_music_fade_from.stop()
		_music_fade_from.volume_db = 0.0
	if _music_fade_to != null:
		_music_fade_to.volume_db = 0.0
	else:
		_music_active = _music_a
	_music_fade_from = null
	_music_fade_to = null
	_music_fade_t = 0.0
	_music_fade_duration = 0.0
	_music_fade_immediate = false


func _start_ambience_crossfade(stream: AudioStream, immediate: bool) -> void:
	var inactive := _amb_b if _amb_active == _amb_a else _amb_a
	inactive.stream = stream
	inactive.volume_db = -80.0 if not immediate else 0.0
	inactive.play()
	_amb_fade_from = _amb_active if _amb_active.playing else null
	_amb_fade_to = inactive
	_amb_active = inactive
	_amb_fade_t = 0.0
	_amb_fade_duration = 0.0 if immediate else CROSSFADE_SEC
	if immediate:
		if _amb_fade_from != null:
			_amb_fade_from.stop()
		_amb_fade_to.volume_db = 0.0
		_amb_fade_duration = 0.0
	elif _amb_fade_from == null:
		_amb_fade_to.volume_db = 0.0
		_amb_fade_duration = 0.0


func _finish_ambience_fade() -> void:
	if _amb_fade_from != null:
		_amb_fade_from.stop()
		_amb_fade_from.volume_db = 0.0
	if _amb_fade_to != null:
		_amb_fade_to.volume_db = 0.0
	_amb_fade_from = null
	_amb_fade_to = null
	_amb_fade_t = 0.0
	_amb_fade_duration = 0.0


func _load_stream(path: String, loop: bool) -> AudioStream:
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: missing stream %s" % path)
		return null
	var stream: AudioStream = load(path)
	if stream == null:
		return null
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = (
			AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		)
	return stream


func _load_loop_into_player(player: AudioStreamPlayer2D, path: String) -> void:
	var stream := _load_stream(path, true)
	if stream != null:
		player.stream = stream


func _apply_all_bus_volumes() -> void:
	for key in AudioSettings.DEFAULT_VOLUMES.keys():
		_apply_bus_volume(key)


func _apply_bus_volume(bus_key: String) -> void:
	var bus_name := _bus_name_for_key(bus_key)
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var linear := get_volume(bus_key)
	AudioServer.set_bus_volume_db(idx, AudioSettings.linear_to_bus_db(linear))
	AudioServer.set_bus_mute(idx, linear <= 0.0)


func _bus_name_for_key(bus_key: String) -> String:
	match bus_key:
		"master":
			return "Master"
		"music":
			return "Music"
		"sfx":
			return "SFX"
		"ambience":
			return "Ambience"
		"ui":
			return "UI"
		_:
			return "Master"
