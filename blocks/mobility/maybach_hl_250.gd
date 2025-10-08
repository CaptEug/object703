extends Powerpack

const HITPOINT:float = 600
const WEIGHT:float = 2000
const BLOCK_NAME:String = 'maybach HL 250'
const TYPE:= "Mobility"
const SIZE:= Vector2(1, 3)
const MAX_POWER:float = 200.0
const ROTATING_POWER: float = 0.2
const POWER_CHANGE_RATE: float = 100

var description := ""
var outline_tex := preload("res://assets/outlines/maybach_outline.png")

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
