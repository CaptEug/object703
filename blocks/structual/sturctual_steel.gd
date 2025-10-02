extends Block

const HITPOINT:float = 400
const WEIGHT:float = 100
const BLOCK_NAME:String = 'structual steel'
const SIZE:= Vector2(1, 1)
const COST:= [
	{"scrap": 4},
	{"metal": 1}
	]

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
