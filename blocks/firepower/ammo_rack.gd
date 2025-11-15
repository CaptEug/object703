extends Ammorack

const HITPOINT:float = 600
const WEIGHT:float = 500
const BLOCK_NAME:String = 'ammo rack'
const SIZE:= Vector2(1, 1)
const TYPE:= "Firepower"
const AMMO_CAPACITY:float = 100.0

var description := ""

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	type = TYPE
	ammo_storage = AMMO_CAPACITY
