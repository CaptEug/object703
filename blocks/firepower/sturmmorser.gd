extends Weapon

const HITPOINT:float = 4000
const WEIGHT:float = 12000
const BLOCK_NAME:String = '38cm sturmmorser'
const SIZE:= Vector2(3, 3)
const TYPE:= "Firepower"
const RANGE:= 900
const RELOAD:float = 1.0
const AMMO_COST:float= 10.0
const ROTATION_SPEED:float = deg_to_rad(10)  # rads per second
const TRAVERSE:= [-5, 5] #degree
const MUZZLE_ENERGY:float = 35000
const SPREAD:float = 0.05

var description := ""

var rocket = preload("res://blocks/firepower/shells/rocket_380_mm.tscn")

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
	shell_scene = rocket
