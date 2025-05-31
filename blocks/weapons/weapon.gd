class_name Weapon
extends Block

var reload:float
var rotation_speed:float  # rads per second
var muzzle_energy:float
var turret:Sprite2D 
var muzzle:Marker2D
var spread:float

# Called when the node enters the scene tree for the first time.
func _ready():
	super._ready()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass

func aim(delta, target_pos):
	var target_angle = (target_pos - global_position).angle() - rotation + deg_to_rad(90)
	var angle_diff = wrapf(target_angle - turret.rotation, -PI, PI)
	turret.rotation += clamp(angle_diff, -rotation_speed * delta, rotation_speed * delta)

func fire(shell_scene:PackedScene):
	var shell = shell_scene.instantiate()
	var shell_rotation = muzzle.global_rotation
	get_tree().current_scene.add_child(shell)
	shell.global_position = muzzle.global_position
	shell.apply_impulse(Vector2.UP.rotated(shell_rotation).rotated(randf_range(-spread, spread)) * muzzle_energy)
