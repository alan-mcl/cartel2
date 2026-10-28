class_name HyperdriveCalcHudChit
extends PanelContainer

signal cancel_requested

@onready var _title: Label = $VBox/TitleLabel
@onready var _detail: Label = $VBox/DetailLabel
@onready var _progress: ProgressBar = $VBox/ProgressBar
@onready var _cancel: Button = $VBox/CancelButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_cancel.pressed.connect(func() -> void: cancel_requested.emit())


func update_from_session(session: GameSession, catalog: Catalog) -> void:
	if not is_node_ready():
		return
	if session == null or not HyperdriveSolution.is_active(session):
		visible = false
		return
	var calc := session.player.hyperdrive_calc if session.player != null else {}
	var target := str(calc.get("target", ""))
	var n := int(calc.get("n", 4))
	var remaining := float(calc.get("remaining_seconds", 0.0))
	var total := float(calc.get("total_seconds", remaining))
	var progress := 0.0 if total <= 0.0 else clampf(1.0 - remaining / total, 0.0, 1.0)
	visible = true
	_title.text = "Hyperdrive compute"
	var dest_label := target
	if catalog != null and not target.is_empty():
		dest_label = TranslationNav.destination_display_label(catalog, target)
	_detail.text = "%d-space → %s · %s left" % [
		n,
		dest_label,
		GalacticCalendar.format_duration(remaining),
	]
	_progress.value = progress
