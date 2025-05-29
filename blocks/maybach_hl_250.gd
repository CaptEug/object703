extends Powerpack

const HITPOINT:int = 200
const WEIGHT:float = 1.0

func _init():
	block_name = "standard_engine"
	size = Vector2(1, 1)
	power = 2000
	hitpoint = HITPOINT
	weight = WEIGHT
	linear_damp = 5.0
	angular_damp = 1.0
