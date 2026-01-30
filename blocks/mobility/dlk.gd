extends Powerpack

const HITPOINT:float = 300
const WEIGHT:float = 1000
const BLOCK_NAME:String = 'Daimler-littleknight'
const TYPE:= "Mobility"
const SIZE:= Vector2(1, 1)
const MAX_POWER:float = 50.0
const INPUTS:Dictionary[String, float] = {"petroleum": 0.5}
const POWER_CHANGE_RATE: float = 10

var description := ""

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	type = TYPE
	size = SIZE
	max_power = MAX_POWER
	inputs = INPUTS
	power_change_rate = POWER_CHANGE_RATE
