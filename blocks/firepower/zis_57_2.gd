extends Weapon

const HITPOINT:float = 600
const WEIGHT:float = 5000
const BLOCK_NAME:String = '57mm duel barrel gun Zis-57-2'
const SIZE:= Vector2(2, 2)
const TYPE:= "Firepower"
const DETECT_RANGE:= 600
const RELOAD:float = 0.2
const AMMO_COST:float= 0.25
const ROTATION_SPEED:float = deg_to_rad(200)  # rads per second
const MUZZLE_ENERGY:float = 900
const SPREAD:float = 0.03

var description := ""

var ap_shell = preload("res://blocks/firepower/shells/br_273_p.tscn")

func _init():
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	type = TYPE
	detect_range = DETECT_RANGE
	reload = RELOAD
	ammo_cost = AMMO_COST
	rotation_speed = ROTATION_SPEED
	muzzle_energy = MUZZLE_ENERGY
	spread = SPREAD
	shell_scene = ap_shell
