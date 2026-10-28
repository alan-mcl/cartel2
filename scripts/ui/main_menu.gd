extends CanvasLayer

signal new_game_requested
signal load_requested
signal leaderboard_requested
signal exit_requested
signal audio_settings_requested

const TOP_UP_MAX_TRIES := MenuHeadlineTape.TOP_UP_MAX_TRIES

@onready var _load_button: Button = $Center/Panel/VBox/LoadButton
@onready var _version_label: Label = $Center/Panel/VBox/VersionLabel
@onready var _headline_tape: MessageBar = $BottomTape/HeadlineTape

var _catalog: Catalog
var _messages: MessageSubsystem
var _scratch_session: GameSession
var _tape_rng := RandomNumberGenerator.new()
var _tape_active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_catalog = Catalog.load_default()
	_messages = MessageSubsystem.new()
	_scratch_session = GameSession.new()
	_scratch_session.run_seed = 1
	if _headline_tape != null:
		_headline_tape.set_tag("")
		_headline_tape.theme_type_variation = &"HudTicker"
	if _version_label != null:
		_version_label.text = GameVersion.VERSION
	$Center/Panel/VBox/NewGameButton.pressed.connect(_on_new_game_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	$Center/Panel/VBox/LeaderboardButton.pressed.connect(_on_leaderboard_pressed)
	$Center/Panel/VBox/AudioButton.pressed.connect(_on_audio_pressed)
	$Center/Panel/VBox/ExitButton.pressed.connect(_on_exit_pressed)
	set_process(false)


func open() -> void:
	visible = true
	_refresh_load_button()
	_start_headline_tape()


func close() -> void:
	visible = false
	_stop_headline_tape()


func _process(_delta: float) -> void:
	if not _tape_active or not visible:
		return
	_top_up_headline_tape()


func _start_headline_tape() -> void:
	if _headline_tape == null:
		return
	_headline_tape.clear_queued_lines()
	_tape_rng.randomize()
	_tape_active = true
	set_process(true)
	_headline_tape.play_line(
		"Cartel 2, version '%s'" % GameVersion.VERSION,
		true,
		true
	)
	_top_up_headline_tape()


func _stop_headline_tape() -> void:
	_tape_active = false
	set_process(false)


func _enqueue_headline_line() -> bool:
	if _headline_tape == null or _messages == null or _scratch_session == null or _catalog == null:
		return false
	var line := MenuHeadlineTape.next_headline(_messages, _scratch_session, _catalog, _tape_rng)
	if line.is_empty():
		return false
	return _headline_tape.play_line(line, true, true)


func _top_up_headline_tape() -> void:
	if _headline_tape == null:
		return
	var tries := 0
	while _headline_tape.wants_more_log_lines() and tries < TOP_UP_MAX_TRIES:
		if not _enqueue_headline_line():
			break
		tries += 1


func _refresh_load_button() -> void:
	var has_save := false
	for slot_info in SaveStore.list_slots():
		if bool(slot_info.get("occupied", false)):
			has_save = true
			break
	_load_button.disabled = not has_save


func _on_new_game_pressed() -> void:
	_ui_click()
	new_game_requested.emit()


func _on_load_pressed() -> void:
	_ui_click()
	load_requested.emit()


func _on_leaderboard_pressed() -> void:
	_ui_click()
	leaderboard_requested.emit()


func _on_audio_pressed() -> void:
	_ui_click()
	audio_settings_requested.emit()


func _on_exit_pressed() -> void:
	_ui_click()
	exit_requested.emit()


func _ui_click() -> void:
	AudioService.play_ui("click")
