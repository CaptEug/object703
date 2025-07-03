extends Command

const HITPOINT:int = 300
const WEIGHT:float = 1000
const BLOCK_NAME:String = 'command cupola'
const SIZE:= Vector2(1, 1)
const TYPE:= 'Command'

func _init():
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	type = TYPE
	control = manual_control
	linear_damp = 5.0
	angular_damp = 1.0

func manual_control():
	var forward_input = Input.get_action_strength("FORWARD") - Input.get_action_strength("BACKWARD")
	var turn_input = Input.get_action_strength("PIVOT_RIGHT") - Input.get_action_strength("PIVOT_LEFT")
	var control_input = [
		forward_input,
		turn_input
	]
	return control_input
