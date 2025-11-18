extends Weapon

const HITPOINT:float = 1800
const WEIGHT:float = 9000
const BLOCK_NAME:String = '122mm D-52S cannon'
const SIZE:= Vector2(2, 8)
const TYPE:= "Firepower"
const RANGE:= 900
const RELOAD:float = 5.0
const AMMO_COST:float= 2.0
const ROTATION_SPEED:float = deg_to_rad(15)  # rads per second
const TRAVERSE:= [-10, 10] #degree
const MUZZLE_ENERGY:float = 25
const SPREAD:float = 0.05

var description := ""
var outline_tex := preload("res://assets/outlines/d52s_outline.png")

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
	rotation_speed = ROTATION_SPEED
	traverse = TRAVERSE
	muzzle_energy = MUZZLE_ENERGY
	spread = SPREAD
	shells = SHELLS

func _process(delta):
	super._process(delta)
	$RangeFinder.rotation = $Turret.rotation
