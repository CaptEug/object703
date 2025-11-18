extends TurretRing

const HITPOINT:float = 1600
const WEIGHT:float = 2000
const BLOCK_NAME:String = 'TurretRing1800mm'
const SIZE:= Vector2(3, 3)
const ROATAION_SPEED:float = deg_to_rad(60)
const COST:= [{"metal": 10}]

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	rotation_speed = ROATAION_SPEED
