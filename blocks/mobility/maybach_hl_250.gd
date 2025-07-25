extends Powerpack

const HITPOINT:float = 200
const WEIGHT:float = 2000
const BLOCK_NAME:String = 'maybach HL 250'
const TYPE:= "Mobility"
const SIZE:= Vector2(1, 1)
const MAX_POWER:float = 200000.0

var description := ""

func _init():
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	type = TYPE
	size = SIZE
	max_power = MAX_POWER
	linear_damp = 5.0
	angular_damp = 1.0
