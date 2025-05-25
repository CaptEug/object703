class_name Vehicle
extends Node2D

var move_state:String
var total_power:float
var total_weight:int
# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):

	update_tracks_state(delta)
	pass

func get_total_engine_power() -> float:
	var total_power := 0.0
	for engine in get_tree().get_nodes_in_group("engines"):
		if engine.is_inside_tree() and is_instance_valid(engine):
			total_power += engine.power
	return total_power

func update_tracks_state(delta):
	if Input.is_action_pressed("FORWARD"): 
		move_state = 'forward'
	elif Input.is_action_pressed("BACKWARD"):
		move_state = 'backward'
	else:
		move_state = 'idle'
