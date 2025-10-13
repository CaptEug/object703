extends Fueltank

const HITPOINT:float = 400
const WEIGHT:float = 200
const BLOCK_NAME:String = 'fuel tank'
const TYPE:= "Mobility"
const SIZE:= Vector2(1, 1)
const FUEL_CAPACITY:= 100000000

var description := ""

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	type = TYPE
	size = SIZE
	fuel_storage = FUEL_CAPACITY
