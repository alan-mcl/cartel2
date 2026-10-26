class_name AudioGates
extends RefCounted

var music_context: String = ""
var ambience_context: String = ""
var _sfx_last_msec: Dictionary = {}


func request_music(context: String) -> bool:
	if context == music_context:
		return false
	music_context = context
	return true


func request_ambience(context: String) -> bool:
	if context == ambience_context:
		return false
	ambience_context = context
	return true


func clear_music() -> void:
	music_context = ""


func clear_ambience() -> void:
	ambience_context = ""


func allow_sfx(sound_id: String, min_interval_sec: float, now_msec: int) -> bool:
	if min_interval_sec <= 0.0:
		return true
	var last: int = int(_sfx_last_msec.get(sound_id, -999999))
	if now_msec - last < int(min_interval_sec * 1000.0):
		return false
	_sfx_last_msec[sound_id] = now_msec
	return true
