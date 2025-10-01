extends Block

const HITPOINT:float = 500
const WEIGHT:float = 1000
const BLOCK_NAME:String = 'armor'
const SIZE:= Vector2(1, 1)
const COST:= [
	{"metal": 2}
	]


func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
