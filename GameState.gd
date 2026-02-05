extends Node

var current_gamescene:Node2D
var world_file:String

func load_game(save_file:String):
	world_file = save_file
	get_tree().change_scene_to_file("res://scenes/gamescene.tscn")
