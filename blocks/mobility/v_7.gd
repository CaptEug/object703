extends Powerpack

const HITPOINT:float = 600
const WEIGHT:float = 2000
const BLOCK_NAME:String = 'V-7'
const TYPE:= "Mobility"
const SIZE:= Vector2(1, 2)
const MAX_POWER:float = 120.0
const ROTATING_POWER: float = 0.5
const POWER_CHANGE_RATE: float = 40

var description := ""

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	type = TYPE
	size = SIZE
	max_power = MAX_POWER
	rotate_power_ratio = ROTATING_POWER
	power_change_rate = POWER_CHANGE_RATE
