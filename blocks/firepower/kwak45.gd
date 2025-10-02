extends Weapon

const HITPOINT:float = 1500
const WEIGHT:float = 7000
const BLOCK_NAME:String = '7.5cm Kwak 45 L/70'
const SIZE:= Vector2(2, 2)
const TYPE:= "Firepower"
const RANGE:= 800
const RELOAD:float = 0.5
const AMMO_COST:float= 1.0
const ROTATION_SPEED:float = deg_to_rad(200)  # rads per second
const MUZZLE_ENERGY:float = 10
const SPREAD:float = 0.02

var description := ""

var ap_shell = preload("res://blocks/firepower/shells/pzgr_75.tscn")

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
	muzzle_energy = MUZZLE_ENERGY
	spread = SPREAD
	shell_scene = ap_shell
