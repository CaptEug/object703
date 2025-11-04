extends Block

const HITPOINT:float = 200
const WEIGHT:float = 100
const BLOCK_NAME:String = 'search light'
const SIZE:= Vector2(1, 1)
const COST:= [
	{"metal": 2}
	]

@onready var turret: Sprite2D = $Turret
var rotation_speed:float = deg_to_rad(90)
var on:bool

func _init():
	max_hp = HITPOINT
	current_hp = HITPOINT
	weight = WEIGHT
	block_name = BLOCK_NAME
	size = SIZE

func _process(delta):
	super._process(delta)
	aim(delta, get_global_mouse_position())

func aim(delta, target_pos):
	var target_angle = (target_pos - global_position).angle() - global_rotation + deg_to_rad(90)
	var angle_diff = wrapf(target_angle, -PI, PI)
	angle_diff = wrapf(target_angle - turret.rotation, -PI, PI)
	turret.rotation += clamp(angle_diff, -rotation_speed * delta, rotation_speed * delta)
	return abs(angle_diff) < deg_to_rad(1)
	# return true if aimeda
	return abs(angle_diff) < deg_to_rad(2)
