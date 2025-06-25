extends Weapon

const HITPOINT:int = 800
const WEIGHT:float = 7000
const BLOCK_NAME:String = '7.5cm Kwak 45 L/70'
const SIZE:= Vector2(2, 2)
const RELOAD:float = 0.5
const ROTATION_SPEED:float = deg_to_rad(200)  # rads per second
const MUZZLE_ENERGY:float = 1000
const SPREAD:float = 0.02

@export var ap_shell = preload("res://blocks/weapons/pzgr75.tscn")

func init():
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	reload = RELOAD
	rotation_speed = ROTATION_SPEED
	muzzle_energy = MUZZLE_ENERGY
	turret = $Turret
	muzzle = $Turret/Muzzle
	animplayer = $Turret/AnimationPlayer
	spread = SPREAD
	linear_damp = 5.0
	angular_damp = 1.0


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	aim(delta, get_global_mouse_position())
	if Input.is_action_pressed("FIRE_MAIN"):
		fire(ap_shell)
	pass
