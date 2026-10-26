class_name AudioService
extends RefCounted

## Static entry points for presentation and UI. Avoids referencing the AudioManager autoload
## global so per-script --check-only passes without loading project autoloads.

static var _manager: Node = null


static func bind_manager(manager: Node) -> void:
	_manager = manager


static func unbind_manager(manager: Node) -> void:
	if _manager == manager:
		_manager = null


static func _mgr() -> Node:
	if _manager != null and is_instance_valid(_manager):
		return _manager
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		return (tree as SceneTree).root.get_node_or_null("AudioManager")
	return null


static func play_music(context: String, immediate: bool = false) -> void:
	var mgr := _mgr()
	if mgr != null:
		mgr.call("play_music", context, immediate)


static func stop_music(immediate: bool = false) -> void:
	var mgr := _mgr()
	if mgr != null:
		mgr.call("stop_music", immediate)


static func play_ambience(context: String, immediate: bool = false) -> void:
	var mgr := _mgr()
	if mgr != null:
		mgr.call("play_ambience", context, immediate)


static func stop_ambience(immediate: bool = false) -> void:
	var mgr := _mgr()
	if mgr != null:
		mgr.call("stop_ambience", immediate)


static func play_ui(suffix: String) -> void:
	var mgr := _mgr()
	if mgr != null:
		mgr.call("play_ui", suffix)


static func play_sfx(sound_id: String) -> void:
	var mgr := _mgr()
	if mgr != null:
		mgr.call("play_sfx", sound_id)


static func play_sfx_at(sound_id: String, world_position: Vector2) -> void:
	var mgr := _mgr()
	if mgr != null:
		mgr.call("play_sfx_at", sound_id, world_position)


static func set_ship_thrust(factor: float, boosting: bool, world_position: Vector2) -> void:
	var mgr := _mgr()
	if mgr != null:
		mgr.call("set_ship_thrust", factor, boosting, world_position)


static func get_volume(bus_key: String) -> float:
	var mgr := _mgr()
	if mgr != null:
		return float(mgr.call("get_volume", bus_key))
	var volumes := AudioSettings.read_volumes()
	return float(volumes.get(bus_key, AudioSettings.DEFAULT_VOLUMES.get(bus_key, 1.0)))


static func set_volume(bus_key: String, linear: float) -> void:
	var mgr := _mgr()
	if mgr != null:
		mgr.call("set_volume", bus_key, linear)
		return
	var volumes := AudioSettings.read_volumes()
	volumes[bus_key] = clampf(linear, 0.0, 1.0)
	if not AudioSettings.write_volumes(volumes):
		push_warning("AudioService: failed to persist audio settings without AudioManager.")


static func get_music_context() -> String:
	var mgr := _mgr()
	if mgr == null:
		return ""
	return String(mgr.call("get_music_context"))


static func get_ambience_context() -> String:
	var mgr := _mgr()
	if mgr == null:
		return ""
	return String(mgr.call("get_ambience_context"))


static func is_engine_playing() -> bool:
	var mgr := _mgr()
	if mgr == null:
		return false
	return bool(mgr.call("is_engine_playing"))
