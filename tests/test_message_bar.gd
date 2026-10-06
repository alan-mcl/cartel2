class_name TestMessageBar
extends RefCounted

const MESSAGE_BAR := preload("res://scenes/ui/patterns/message_bar.tscn")


static func run(runner: TestRunner, tree: SceneTree = null) -> void:
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	_test_play_line(runner, tree)
	_test_play_line_dedupe(runner, tree)
	_test_play_line_queue(runner, tree)
	_test_play_line_scroll_off(runner, tree)
	_test_play_line_reenters_from_right(runner, tree)
	_test_clear_queued_lines(runner, tree)
	_test_set_feed(runner, tree)


static func _test_play_line(runner: TestRunner, tree: SceneTree) -> void:
	var bar := _spawn_bar(runner, tree)
	if bar == null:
		return
	bar.play_line("Installed module.")
	runner.check_eq(bar.get_log_label_count_for_tests(), 1, "message bar: play_line creates one label")
	runner.check_eq(
		bar.get_log_label_text_for_tests(0),
		"Installed module.",
		"message bar: play_line sets label text"
	)
	runner.check_eq(
		bar.get_log_label_x_for_tests(0),
		440.0,
		"message bar: play_line starts at clip right edge"
	)
	bar.get_parent().queue_free()


static func _test_play_line_dedupe(runner: TestRunner, tree: SceneTree) -> void:
	var bar := _spawn_bar(runner, tree)
	if bar == null:
		return
	bar.play_line("Alpha")
	bar.play_line("Alpha")
	runner.check_eq(
		bar.get_last_enqueued_log_for_tests(),
		"Alpha",
		"message bar: play_line skips duplicate announcement"
	)
	runner.check_eq(bar.get_log_label_count_for_tests(), 1, "message bar: dedupe does not duplicate labels")
	bar.get_parent().queue_free()


static func _test_play_line_queue(runner: TestRunner, tree: SceneTree) -> void:
	var bar := _spawn_bar(runner, tree)
	if bar == null:
		return
	bar.play_line("First message")
	var first_x := bar.get_log_label_x_for_tests(0)
	bar.play_line("Second message")
	runner.check_eq(bar.get_log_label_count_for_tests(), 2, "message bar: queue adds second label")
	runner.check_eq(
		bar.get_log_label_x_for_tests(0),
		first_x,
		"message bar: queue does not move first label"
	)
	runner.check(
		bar.get_log_label_x_for_tests(1) > first_x,
		"message bar: second label starts after first with gap"
	)
	bar.get_parent().queue_free()


static func _test_play_line_scroll_off(runner: TestRunner, tree: SceneTree) -> void:
	var bar := _spawn_bar(runner, tree)
	if bar == null:
		return
	bar.play_line("Short")
	bar.play_line("Tail")
	runner.check_eq(bar.get_log_label_count_for_tests(), 2, "message bar: two labels before scroll")
	var steps := 0
	while bar.get_log_label_count_for_tests() > 1 and steps < 500:
		bar._process(0.05)
		steps += 1
	runner.check_eq(bar.get_log_label_count_for_tests(), 1, "message bar: front label removed after scrolling off")
	bar.get_parent().queue_free()


static func _test_play_line_reenters_from_right(runner: TestRunner, tree: SceneTree) -> void:
	var bar := _spawn_bar(runner, tree)
	if bar == null:
		return
	bar.play_line("First message")
	var clip := bar.get_node("HBox/Clip") as Control
	var clip_w := clip.size.x
	for _i in range(500):
		if bar.get_log_label_count_for_tests() == 0:
			runner.check(false, "message bar: first status line still on screen")
			break
		if bar.log_tail_x() + 32.0 <= clip_w:
			break
		bar._process(0.05)
	bar.play_line("Second message")
	runner.check_eq(bar.get_log_label_count_for_tests(), 2, "message bar: status queue keeps prior line")
	runner.check_eq(
		bar.get_log_label_x_for_tests(1),
		clip_w,
		"message bar: new status line enters from clip right edge"
	)
	bar.get_parent().queue_free()


static func _test_clear_queued_lines(runner: TestRunner, tree: SceneTree) -> void:
	var bar := _spawn_bar(runner, tree)
	if bar == null:
		return
	bar.play_line("Docked at terminal.")
	bar.play_line("Purchased fuel.")
	runner.check_eq(bar.get_log_label_count_for_tests(), 2, "message bar: clear has queued labels")
	bar.clear_queued_lines()
	runner.check_eq(bar.get_log_label_count_for_tests(), 0, "message bar: clear removes queued labels")
	bar.play_line("Launched.")
	runner.check_eq(bar.get_log_label_count_for_tests(), 1, "message bar: play_line after clear")
	_flush_bar(bar)


static func _test_set_feed(runner: TestRunner, tree: SceneTree) -> void:
	var bar := _spawn_bar(runner, tree)
	if bar == null:
		return
	bar.set_feed([{"text": "Ticker headline", "tone": "info"}], true)
	_flush_bar(bar)
	runner.check(
		bar.get_track_text_for_tests().contains("Ticker headline"),
		"message bar: set_feed renders item text"
	)
	bar.get_parent().queue_free()


static func _spawn_bar(runner: TestRunner, tree: SceneTree) -> MessageBar:
	if tree == null or tree.root == null:
		runner.check(false, "message bar: SceneTree available")
		return null
	var host := Control.new()
	tree.root.add_child(host)
	host.set_size(Vector2(480, 32))
	var bar: MessageBar = MESSAGE_BAR.instantiate()
	host.add_child(bar)
	bar._ready()
	bar.set_size(Vector2(480, 28))
	var clip := bar.get_node("HBox/Clip") as Control
	clip.set_size(Vector2(440, 20))
	return bar


static func _flush_bar(bar: MessageBar) -> void:
	bar.call("_apply_feed_layout")
