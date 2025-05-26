class_name Map
extends Node

func _ready():
	add_to_group('maps')
	pass
	
func stop_liner_damp_():
	var liner_damp = get_liner_damp()
	return liner_damp

func get_liner_damp() -> float:
	return 0.0
