extends Powerpack

const HITPOINT:float = 200
const WEIGHT:float = 2000
const BLOCK_NAME:String = 'maybach HL 250'
const TYPE:= "Mobility"
const SIZE:= Vector2(1, 1)
const MAX_POWER:float = 200000.0
const ROTATING_POWER: float = 0.2
const POWER_CHANGE_RATE: float = 100000

var description := ""

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	type = TYPE
	size = SIZE
	max_power = MAX_POWER
	rotating_power = ROTATING_POWER
	power_change_rate = POWER_CHANGE_RATE
