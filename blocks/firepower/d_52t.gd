extends Weapon

const HITPOINT:float = 800
const WEIGHT:float = 2500
const BLOCK_NAME:String = '122mm D-52T cannon'
const SIZE:= Vector2(1, 8)
const TYPE:= "Firepower"
const RANGE:= 900
const RELOAD:float = 5.0
const AMMO_COST:float= 2.0
const MUZZLE_ENERGY:float = 25
const SPREAD:float = 0.05

var description := ""
var outline_tex := preload("res://assets/outlines/d52t_outline.png")

const SHELLS = ["122mmAPHE", "122mmHE"]

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
	shells = SHELLS
	center_of_mass_offset = Vector2(0, 32)
