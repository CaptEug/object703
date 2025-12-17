extends Node

@onready var window_root := get_tree().get_root().get_node("Main/UI/WindowRoot")

var opened_windows := {}

func open_window(window_scene: PackedScene, data):
	var win = window_scene.instantiate()
	window_root.add_child(win)
	opened_windows[win.get_class()] = win
	win.open(data)

func close_window(window_class_name: String):
	if opened_windows.has(window_class_name):
		opened_windows[window_class_name].close()
		opened_windows[window_class_name].queue_free()
		opened_windows.erase(window_class_name)
