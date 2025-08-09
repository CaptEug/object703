extends Fueltank

const HITPOINT:float = 200
const WEIGHT:float = 2000
const BLOCK_NAME:String = 'fuel tank'
const TYPE:= "Mobility"
const SIZE:= Vector2(1, 1)
const FUEL_CAPACITY:= 10000000
var icons:Dictionary = {"normal":"res://assets/icons/engine_icon.png","selected":"res://assets/icons/engine_icon_n.png"}

var description := ""

func _init():
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	type = TYPE
	size = SIZE
	fuel_storage = FUEL_CAPACITY
	linear_damp = 5.0
	angular_damp = 1.0
