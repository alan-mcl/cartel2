extends SceneTree

func _init() -> void:
	for bus_name in ["Music", "SFX", "Ambience", "UI"]:
		AudioServer.add_bus()
		var idx := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")
	var path := "res://audio/default_bus_layout.tres"
	var err := ResourceSaver.save(AudioServer.generate_bus_layout(), path)
	if err != OK:
		push_error("Failed to save bus layout: %s" % error_string(err))
		quit(1)
	print("Saved ", path)
	quit(0)
