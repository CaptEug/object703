extends Block

const HITPOINT:int = 400
const WEIGHT:int = 7000
var block_name:String = '7.5cm Kwak 45 L/70'
var size:= Vector2(2, 2)
var rotation_speed:float = 3.0  # rads per second
var muzzle_energy:float = 100

func init():
	mass = WEIGHT
	current_hp = HITPOINT

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	aim(delta, get_global_mouse_position())
	pass

func aim(delta, target_pos):
	var target_angle = (target_pos - global_position).angle() - rotation + deg_to_rad(90)
	var angle_diff = wrapf(target_angle - $Turret.rotation, -PI, PI)
	$Turret.rotation += clamp(angle_diff, -rotation_speed * delta, rotation_speed * delta)

func fire(shell:Shell):
	pass
