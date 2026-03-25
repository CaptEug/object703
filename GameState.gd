extends Node

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
	var success:bool = true
	world_path = saving_dir + current_gamescene.world_name + "/"
	var dir := DirAccess.open(world_path)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(world_path)
	current_gamescene.save_world(world_path)
	save_finished.emit(success)


func load_game(world_folder:String):
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
