extends Block

const HITPOINT:float = 250
const WEIGHT:float = 500
const BLOCK_NAME:String = 'pike armor'
const SIZE:= Vector2(1, 1)

func _init():
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	linear_damp = 5.0
	angular_damp = 1.0
