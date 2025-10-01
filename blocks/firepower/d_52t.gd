extends Weapon

const HITPOINT:float = 400
const WEIGHT:float = 2500
const BLOCK_NAME:String = '122mm D-52T cannon'
const SIZE:= Vector2(1, 2)
const TYPE:= "Firepower"
const RANGE:= 900
const RELOAD:float = 5.0
const AMMO_COST:float= 2.0
const MUZZLE_ENERGY:float = 25000
const SPREAD:float = 0.05

var description := ""

var sap_shell = preload("res://blocks/firepower/shells/br_473.tscn")

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
	muzzle_energy = MUZZLE_ENERGY
	spread = SPREAD
	shell_scene = sap_shell
