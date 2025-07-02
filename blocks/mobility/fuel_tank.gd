extends Block

const HITPOINT:int = 200
const WEIGHT:float = 2000
const BLOCK_NAME:String = 'fuel tank'
const TYPE:= "Mobility"
const SIZE:= Vector2(1, 1)
var fuel_capacity:= 100
var icons:Dictionary = {"normal":"res://assets/icons/engine_icon.png","selected":"res://assets/icons/engine_icon_n.png"}

var description := ""

func _init():
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	type = TYPE
	size = SIZE
	linear_damp = 5.0
	angular_damp = 1.0
