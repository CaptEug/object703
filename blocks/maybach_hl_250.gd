extends Powerpack

const HITPOINT:int = 200
const WEIGHT:float = 1.0
const BLOCK_NAME:String = 'maybach HL 250'
const SIZE:= Vector2(1, 1)
const POWER:float = 2000.0

func _init():
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = 'maybach HL 250'
	size = SIZE
	power = POWER
	linear_damp = 5.0
	angular_damp = 1.0
