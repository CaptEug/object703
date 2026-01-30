extends Powerpack

const HITPOINT:float = 800
const WEIGHT:float = 2000
const BLOCK_NAME:String = 'maybach HL 250'
const TYPE:= "Mobility"
const SIZE:= Vector2(1, 3)
const MAX_POWER:float = 180.0
const INPUTS:Dictionary[String, float] = {"petroleum": 2.0}
const POWER_CHANGE_RATE: float = 60

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
	inputs = INPUTS
	power_change_rate = POWER_CHANGE_RATE
