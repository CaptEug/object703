extends Weapon

const HITPOINT:float = 800
const WEIGHT:float = 2000
const BLOCK_NAME:String = 'QF 6-pounder gun'
const SIZE:= Vector2(1, 2)
const TYPE:= "Firepower"
const RANGE:= 500
const RELOAD:float = 2.0
const AMMO_COST:float= 1
const ROTATION_SPEED:float = deg_to_rad(20)  # rads per second
const TRAVERSE:= [0, 100] #degree
const MUZZLE_ENERGY:float = 2
const SPREAD:float = 0.05

var description := ""

const SHELLS = ["57mmAP"]

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	type = TYPE
	range = RANGE
	reload = RELOAD
	ammo_cost = AMMO_COST
	rotation_speed = ROTATION_SPEED
	traverse = TRAVERSE
	muzzle_energy = MUZZLE_ENERGY
	spread = SPREAD
	shells = SHELLS
