extends Cargo

const HITPOINT:float = 400
const WEIGHT:float = 100
const BLOCK_NAME:String = 'small cargo'
const SIZE:= Vector2(1, 1)
const MAX_LOAD:float = 2000
const TYPE:= 'Auxiliary'
const ACCEPT:= ["ALL"]


func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	accept = ACCEPT
	size = SIZE
	type = TYPE
