extends Track

const HITPOINT:int = 200
const WEIGHT:float = 2.0
const FRICTION:float = 5.0

func _init():
	block_name = "standard_track"
	size = Vector2(1, 1)
	max_force = 500
	hitpoint = HITPOINT
	weight = WEIGHT
	friction = FRICTION
