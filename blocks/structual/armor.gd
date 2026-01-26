extends Block

const HITPOINT:float = 1000
const WEIGHT:float = 1000
const BLOCK_NAME:String = 'armor'
const SIZE:= Vector2(1, 1)
const COST:= {"metal": 2}
const KINETIC_ABSORB:= 0.9
const EXPLOSIVE_ABSORB:= 0.5


func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	cost = COST
	kinetic_absorb = KINETIC_ABSORB
	explosice_absorb = EXPLOSIVE_ABSORB
