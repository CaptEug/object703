extends Node

const WORLD_VERSION := 0

var current_gamescene:GameScene
var saving_dir:String = "res://saves/"
var world_path:String
var world_gen_data:Dictionary

signal save_started
signal save_finished(success: bool)

var mainmenu_path := "res://ui/mainmenu/mainmenu.tscn"
var gamescene_path := "res://scene/gamescene.tscn"


func _process(_delta: float) -> void:
	pass


func to_mainmenu():
	save_game()
	get_tree().change_scene_to_file(mainmenu_path)


func save_game():
	save_started.emit()
	var success := false
	world_path = saving_dir + current_gamescene.world_name + "/"
	var dir := DirAccess.open(world_path)
	if dir == null:
		var make_error := DirAccess.make_dir_recursive_absolute(world_path)
		if make_error != OK:
			push_error("Could not create world save folder.")
			save_finished.emit(false)
			return
	success = current_gamescene.save_world(world_path)
	save_finished.emit(success)


func load_game(world_folder:String):
	var validation := inspect_world(world_folder)
	if not validation["ok"]:
		push_error(validation["error"])
		return
	world_gen_data.clear()
	world_path = saving_dir + world_folder + "/"
	get_tree().change_scene_to_file(gamescene_path)


func world_gen(world_name:String, world_seed:String):
	# 1. Prepare the folder
	world_path = saving_dir + world_name + "/"
	var dir := DirAccess.open(world_path)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(world_path)
	
	# 2. Store seed & name in a temporary dictionary
	world_gen_data = {
		"name": world_name,
		"seed": world_seed
	}
	
	# 3. Switch to GameScene
	get_tree().change_scene_to_file(gamescene_path)


func inspect_world(world_folder: String) -> Dictionary:
	var directory := saving_dir + world_folder + "/"
	var header := _read_json_dictionary(directory + "header.json")
	if header.is_empty():
		return _world_error(world_folder, "missing or invalid header.json")
	if int(header.get("version", -1)) != WORLD_VERSION:
		return _world_error(world_folder, "unsupported world version")
	var saved_name_value: Variant = header.get("name")
	var seed_value: Variant = header.get("seed")
	if not saved_name_value is String or str(saved_name_value).is_empty():
		return _world_error(world_folder, "invalid world name")
	if not seed_value is String:
		return _world_error(world_folder, "invalid world seed")

	return {
		"ok": true,
		"folder": world_folder,
		"name": str(saved_name_value),
		"seed": str(seed_value),
		"last_played": float(header.get("last_played", 0.0)),
	}


func _read_json_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _world_error(world_folder: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"error": "World '%s' is not loadable: %s." % [world_folder, reason],
	}
