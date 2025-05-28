extends Block

const HITPOINT:int = 800
const WEIGHT:int = 7000
var block_name:String = '7.5cm Kwak 45 L/70'
var size:= Vector2(2, 2)
var rotation_speed:float = 3.0  # rads per second
var muzzle_energy:float = 800

@export var ap_shell = preload("res://blocks/weapons/shells/ap75mm.tscn")

func init():
	mass = WEIGHT
	current_hp = HITPOINT
	linear_damp = 5.0
# Called when the node enters the scene tree for the first time.
func _ready():
	super._ready()
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	aim(delta, get_global_mouse_position())
	if Input.is_action_just_pressed("FIRE_MAIN"):
		fire(ap_shell)
	pass

func aim(delta, target_pos):
	var target_angle = (target_pos - global_position).angle() - rotation + deg_to_rad(90)
	var angle_diff = wrapf(target_angle - $Turret.rotation, -PI, PI)
	$Turret.rotation += clamp(angle_diff, -rotation_speed * delta, rotation_speed * delta)

func fire(shell_scene:PackedScene):
	var muzzle = $Turret/Muzzle
	var shell = shell_scene.instantiate()
	var shell_rotation = muzzle.global_rotation
	get_tree().current_scene.add_child(shell)
	shell.global_position = muzzle.global_position
	shell.apply_impulse(Vector2.UP.rotated(shell_rotation) * muzzle_energy)
	
