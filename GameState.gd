extends Node

var current_gamescene:GameScene
var saving_dir:String = "res://saves/"
var world_path:String

signal save_started
signal save_finished(success: bool)

func _process(delta: float) -> void:
	pass

func to_mainmenu():
	save_game()
	get_tree().change_scene_to_file("res://ui/mainmenu/mainmenu.tscn")

func save_game():
	save_started.emit()
	var success:bool = true
	world_path = saving_dir + current_gamescene.world_name + "/"
	var dir := DirAccess.open(world_path)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(world_path)
	current_gamescene.save_world(world_path)
	save_finished.emit(success)

func load_game(world_folder:String):
	world_path = saving_dir + world_folder + "/"
	get_tree().change_scene_to_file("res://scenes/gamescene.tscn")


func _write_json(path: String, data: Dictionary):
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var result = JSON.parse_string(text)
	if typeof(result) != TYPE_DICTIONARY:
		return {}
	return result
