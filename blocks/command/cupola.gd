extends Command

const HITPOINT:float = 500
const FUNCTION_HP = 125
const WEIGHT:float = 1000
const BLOCK_NAME:String = 'command cupola'
const SIZE:= Vector2(1, 1)
const TYPE:= 'Command'
const DETECT_RANGE:float = 800

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	detect_range = DETECT_RANGE
	size = SIZE
	type = TYPE


func manual_control():
	var forward_input = Input.get_action_strength("FORWARD") - Input.get_action_strength("BACKWARD")
	var turn_input = Input.get_action_strength("PIVOT_RIGHT") - Input.get_action_strength("PIVOT_LEFT")
	var control_input = [
		forward_input,
		turn_input
	]
	return control_input

func AI_control():
	return [0,0]
