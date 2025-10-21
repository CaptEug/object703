extends Cargo

const HITPOINT:float = 2000
const WEIGHT:float = 500
const BLOCK_NAME:String = 'large cargo'
const SIZE:= Vector2(2, 2)
const MAX_LOAD:float = 8000
const TYPE:= 'Auxiliary'
const ACCEPT:= ["ALL"]


func _init():
	max_hp = HITPOINT
	slot_count = 36
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	accept = ACCEPT
	size = SIZE
	type = TYPE
