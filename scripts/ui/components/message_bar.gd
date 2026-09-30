class_name MessageBar
extends PanelContainer

const SEPARATOR := "  ·  "
const SCROLL_PX_PER_SEC := 48.0
const LOG_GAP_PX := 32.0
const PENDING_PLACE_META := &"pending_place"

enum DisplayMode { IDLE, STATUS_LABELS, FEED_LOOP }

var _tag: Label
var _clip: Control
var _feed_track: RichTextLabel

var _mode: DisplayMode = DisplayMode.IDLE
var _use_bbcode: bool = false
var _body_text: String = ""
var _scroll_offset: float = 0.0
var _segment_width: float = 0.0
var _last_enqueued_log: String = ""

var _log_labels: Array[Label] = []


func _ready() -> void:
	_bind_nodes()
	_apply_feed_track_theme()
	_feed_track.scroll_active = false
	_feed_track.autowrap_mode = TextServer.AUTOWRAP_OFF
	_feed_track.fit_content = true
	_feed_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed_track.visible = false
	if not _clip.resized.is_connected(_on_clip_resized):
		_clip.resized.connect(_on_clip_resized)
	set_process(false)


func _apply_feed_track_theme() -> void:
	_bind_nodes()
	var muted_color := get_theme_color("text_muted", "Cartel")
	_feed_track.add_theme_color_override("default_color", muted_color)
	var font := get_theme_font("font", &"Muted")
	if font != null:
		_feed_track.add_theme_font_override("normal_font", font)
	var font_size := get_theme_font_size("font_size", &"Muted")
	if font_size > 0:
		_feed_track.add_theme_font_size_override("normal_font_size", font_size)


func _process(delta: float) -> void:
	match _mode:
		DisplayMode.STATUS_LABELS:
			_advance_log_labels(delta)
		DisplayMode.FEED_LOOP:
			_scroll_offset += SCROLL_PX_PER_SEC * delta
			if _segment_width > 0.0:
				_scroll_offset = fmod(_scroll_offset, _segment_width)
			_feed_track.position.x = -_scroll_offset


func _bind_nodes() -> void:
	if _tag != null:
		return
	_tag = $HBox/Tag
	_clip = $HBox/Clip
	_feed_track = $HBox/Clip/Track


func set_tag(text: String) -> void:
	_bind_nodes()
	_tag.text = text
	_tag.visible = not text.is_empty()


## Queue one log line: enters from the right (or after the previous tail + gap) and scrolls off once.
func play_line(text: String) -> void:
	_bind_nodes()
	var line := text.strip_edges()
	if line.is_empty():
		return
	if line == _last_enqueued_log:
		return
	_last_enqueued_log = line

	if _mode == DisplayMode.FEED_LOOP:
		_clear_feed()

	var label := _create_log_label(line)
	label.set_meta(PENDING_PLACE_META, true)
	label.visible = false
	_clip.add_child(label)
	_log_labels.append(label)
	_mode = DisplayMode.STATUS_LABELS
	_feed_track.visible = false
	_resolve_pending_placements()
	set_process(true)


func set_feed(items: Array, loop: bool = true) -> void:
	_bind_nodes()
	_clear_log_labels()
	if not loop:
		push_warning("MessageBar set_feed requires loop=true for wire tickers")
	_use_bbcode = true
	_feed_track.visible = true
	_feed_track.bbcode_enabled = true
	_body_text = _feed_to_bbcode(items)
	_last_enqueued_log = ""
	if _body_text.is_empty():
		_clear_feed()
		return
	_mode = DisplayMode.FEED_LOOP
	_scroll_offset = 0.0
	_apply_feed_layout()
	set_process(true)


func _create_log_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Muted"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _resolve_pending_placements() -> void:
	var clip_w := _clip.size.x
	if clip_w <= 0.0:
		return
	for i in range(_log_labels.size()):
		var label: Label = _log_labels[i]
		if not label.has_meta(PENDING_PLACE_META):
			continue
		label.remove_meta(PENDING_PLACE_META)
		label.visible = true
		if i == 0:
			label.position.x = clip_w
		else:
			var prev: Label = _log_labels[i - 1]
			var tail: float = prev.position.x + _label_width(prev) + LOG_GAP_PX
			label.position.x = maxf(clip_w, tail)
		label.position.y = 1.0


func _advance_log_labels(delta: float) -> void:
	var step := SCROLL_PX_PER_SEC * delta
	var to_remove: Array[Label] = []
	for label in _log_labels:
		if label.has_meta(PENDING_PLACE_META):
			continue
		label.position.x -= step
		if label.position.x + _label_width(label) < 0.0:
			to_remove.append(label)
	for label in to_remove:
		_log_labels.erase(label)
		label.queue_free()
	if _log_labels.is_empty():
		_mode = DisplayMode.IDLE
		set_process(false)


func _clear_log_labels() -> void:
	for label in _log_labels:
		if is_instance_valid(label):
			label.queue_free()
	_log_labels.clear()


func _clear_feed() -> void:
	_mode = DisplayMode.IDLE
	_body_text = ""
	_feed_track.text = ""
	_feed_track.visible = false
	_feed_track.position.x = 0.0
	_scroll_offset = 0.0
	set_process(false)


func _feed_to_bbcode(items: Array) -> String:
	var chunks: PackedStringArray = PackedStringArray()
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			chunks.append(str(item))
			continue
		var entry: Dictionary = item
		var chunk_text := str(entry.get("text", "")).strip_edges()
		if chunk_text.is_empty():
			continue
		var tone := str(entry.get("tone", ""))
		if tone.is_empty():
			chunks.append(chunk_text)
		else:
			chunks.append("[color=%s]%s[/color]" % [_color_hex_for_tone(tone), chunk_text])
	return SEPARATOR.join(chunks)


func _color_hex_for_tone(tone: String) -> String:
	match tone:
		"positive":
			return get_theme_color("positive", "Cartel").to_html(false)
		"negative":
			return get_theme_color("negative", "Cartel").to_html(false)
		"warning":
			return get_theme_color("warning", "Cartel").to_html(false)
		"info":
			return get_theme_color("info", "Cartel").to_html(false)
		_:
			return get_theme_color("text", "Cartel").to_html(false)


func _on_clip_resized() -> void:
	if _mode == DisplayMode.FEED_LOOP:
		call_deferred("_apply_feed_layout")
	elif _mode == DisplayMode.STATUS_LABELS:
		_resolve_pending_placements()


func _apply_feed_layout() -> void:
	_bind_nodes()
	if _body_text.is_empty():
		return
	_segment_width = _measure_feed_width(_body_text)
	var viewport_w := _clip.size.x
	if viewport_w > 1.0 and _segment_width > viewport_w + 1.0:
		_feed_track.text = _body_text + SEPARATOR + _body_text
	else:
		_feed_track.text = _body_text
		_scroll_offset = 0.0
		_feed_track.position.x = 0.0
	_feed_track.position.y = 0.0


func _label_width(label: Label) -> float:
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	if font == null:
		return float(label.text.length()) * 8.0
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _measure_feed_width(text: String) -> float:
	var font := _feed_track.get_theme_font("normal_font")
	var font_size := _feed_track.get_theme_font_size("normal_font")
	if font == null:
		return float(text.length()) * 8.0
	var plain := text
	if _use_bbcode:
		plain = _strip_bbcode(text)
	return font.get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _strip_bbcode(text: String) -> String:
	var re := RegEx.new()
	re.compile("\\[color=[^\\]]+\\](.*?)\\[/color\\]")
	var result := text
	while true:
		var match := re.search(result)
		if match == null:
			break
		result = result.replace(match.get_string(), match.get_string(1))
	return result


func get_log_label_count_for_tests() -> int:
	return _log_labels.size()


func get_log_label_text_for_tests(index: int) -> String:
	if index < 0 or index >= _log_labels.size():
		return ""
	return _log_labels[index].text


func get_log_label_x_for_tests(index: int) -> float:
	if index < 0 or index >= _log_labels.size():
		return 0.0
	return _log_labels[index].position.x


func get_track_text_for_tests() -> String:
	_bind_nodes()
	return _feed_track.text


func get_last_enqueued_log_for_tests() -> String:
	return _last_enqueued_log
