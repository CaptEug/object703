extends Weapon

const HITPOINT:float = 800
const FUNCTION_HP:float = 200
const WEIGHT:float = 5000
const BLOCK_NAME:String = '57mm duel barrel gun Zis-57-2'
const SIZE:= Vector2(2, 2)
const TYPE:= "Firepower"
const RANGE:= 600
const RELOAD:float = 0.2
const AMMO_COST:float= 0.25
const ROTATION_SPEED:float = deg_to_rad(200)  # rads per second
const MUZZLE_ENERGY:float = 900
const SPREAD:float = 0.03

var description := ""

var ap_shell = preload("res://blocks/firepower/shells/br_273_p.tscn")

func _init():
	current_hp = HITPOINT
	function_hp = FUNCTION_HP
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	type = TYPE
	range = RANGE
	reload = RELOAD
	ammo_cost = AMMO_COST
	rotation_speed = ROTATION_SPEED
	muzzle_energy = MUZZLE_ENERGY
	spread = SPREAD
	shell_scene = ap_shell
