class_name TestGameScreen
extends RefCounted


static func run(runner: TestRunner, tree: SceneTree = null) -> void:
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	_test_session_changed_lifecycle(runner, tree)
	runner.check(
		load("res://scripts/ui/shipyard_screen.gd").get_global_name() == &"ShipyardScreen",
		"ShipyardScreen global class name"
	)
	runner.check(
		load("res://scripts/ui/shipyard_refit_screen.gd").get_global_name() == &"ShipyardRefitScreen",
		"ShipyardRefitScreen global class name"
	)


static func _test_session_changed_lifecycle(runner: TestRunner, tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		runner.check(false, "GameScreen: SceneTree available")
		return
	var host := Control.new()
	tree.root.add_child(host)
	var screen := GameScreen.new()
	host.add_child(screen)
	var session_a := GameSession.new()
	var ctx := UiContext.new()
	ctx.session = session_a
	screen.bind(ctx)
	var handler := Callable(screen, "_on_session_changed")
	runner.check(
		session_a.changed.is_connected(handler),
		"GameScreen bind connects session.changed"
	)
	var session_b := GameSession.new()
	var ctx_b := UiContext.new()
	ctx_b.session = session_b
	screen.bind(ctx_b)
	runner.check(
		not session_a.changed.is_connected(handler),
		"GameScreen rebind disconnects previous session"
	)
	runner.check(
		session_b.changed.is_connected(handler),
		"GameScreen rebind connects new session"
	)
	screen.free()
	runner.check(
		not session_b.changed.is_connected(handler),
		"GameScreen exit tree disconnects session.changed"
	)
	host.queue_free()
