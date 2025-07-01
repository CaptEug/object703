extends Weapon

const HITPOINT:int = 1000
const WEIGHT:float = 9000
const BLOCK_NAME:String = '122mm D-52S cannon'
const SIZE:= Vector2(2, 2)
const TYPE:= "Firepower"
const RANGE:= 900
const RELOAD:float = 5.0
const AMMO_COST:float= 2.0
const ROTATION_SPEED:float = deg_to_rad(15)  # rads per second
const TRAVERSE:= [-8, 8] #degree
const MUZZLE_ENERGY:float = 1000
const SPREAD:float = 0.05

const DESCRIPTION := ""

var sap_shell = preload("res://blocks/firepower/shells/br_473.tscn")

func init():
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	description = DESCRIPTION
	size = SIZE
	type = TYPE
	range = RANGE
	reload = RELOAD
	ammo_cost = AMMO_COST
	rotation_speed = ROTATION_SPEED
	traverse = TRAVERSE
	muzzle_energy = MUZZLE_ENERGY
	turret = $Gun
	muzzles.append($Gun/Muzzle)
	animplayer = $Gun/AnimationPlayer
	spread = SPREAD
	linear_damp = 5.0
	angular_damp = 1.0


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	aim(delta, get_global_mouse_position())
	if Input.is_action_pressed("FIRE_MAIN"):
		fire(sap_shell)
