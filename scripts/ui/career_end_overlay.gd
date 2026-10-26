extends CanvasLayer

signal main_menu_requested
signal leaderboard_requested

@onready var _title: Label = $Center/Panel/VBox/TitleLabel
@onready var _callsign: Label = $Center/Panel/VBox/CallsignLabel
@onready var _reason: Label = $Center/Panel/VBox/ReasonLabel
@onready var _profit: Label = $Center/Panel/VBox/ProfitLabel
@onready var _worth: Label = $Center/Panel/VBox/WorthLabel
@onready var _time: Label = $Center/Panel/VBox/TimeLabel
@onready var _background: ColorRect = $Background

const FADE_IN_SEC := 0.6


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	$Center/Panel/VBox/LeaderboardButton.pressed.connect(_on_leaderboard_pressed)
	$Center/Panel/VBox/MainMenuButton.pressed.connect(_on_main_menu_pressed)


func open(session: GameSession, catalog: Catalog) -> void:
	if session == null:
		return
	_title.text = "Career ended"
	_callsign.text = session.callsign
	_reason.text = "Ship destroyed."
	_profit.text = "Nett profit: %s" % CareerStatsFormat.format_credits(session.career.nett_profit())
	if catalog != null:
		_worth.text = "Nett worth: %s" % CareerStatsFormat.format_credits(
			CareerWorth.nett_worth(session, catalog)
		)
		_worth.visible = true
	else:
		_worth.visible = false
	_time.text = "Career time: %s" % CareerStatsFormat.format_flight_time(session.career.played_seconds)
	var backdrop := _background.color
	_background.color = Color(backdrop.r, backdrop.g, backdrop.b, 0.0)
	visible = true
	var tween := create_tween()
	tween.tween_property(_background, "color", backdrop, FADE_IN_SEC).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_OUT
	)


func close() -> void:
	visible = false
	if _background != null:
		_background.color = Color(_background.color.r, _background.color.g, _background.color.b, 0.92)


func _on_leaderboard_pressed() -> void:
	AudioService.play_ui("click")
	leaderboard_requested.emit()


func _on_main_menu_pressed() -> void:
	AudioService.play_ui("click")
	main_menu_requested.emit()
