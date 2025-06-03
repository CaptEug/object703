extends Weapon

const HITPOINT:int = 1000
const WEIGHT:float = 10.0
const BLOCK_NAME:String = 'D-52s'
const SIZE:= Vector2(2, 2)
const RELOAD:float = 10
const ROTATION_SPEED:float = deg_to_rad(10)  # rads per second
const GUIDANCE:= [-8, 8] #degree
const MUZZLE_ENERGY:float = 1000
const SPREAD:float = 0.05

func init():
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE
	reload = RELOAD
	rotation_speed = ROTATION_SPEED
	guidance = GUIDANCE
	muzzle_energy = MUZZLE_ENERGY
	turret = $Gun
	muzzle = $Gun/Muzzle
	spread = SPREAD
	linear_damp = 5.0
	angular_damp = 1.0


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	aim(delta, get_global_mouse_position())
