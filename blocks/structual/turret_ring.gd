class_name TurretRing
extends Block

var load:float
var turret:RigidBody2D
var traverse:Array
var max_torque:float = 1000
var damping:float = 100

func _ready():
	super._ready()
	turret = find_child("Turret") as RigidBody2D

func _physics_process(_delta):
	aim(get_global_mouse_position())

func aim(target_pos):
	var target_angle = (target_pos - global_position).angle() - rotation + deg_to_rad(90)
	var angle_diff = wrapf(target_angle - turret.rotation, -PI, PI)
	
	if traverse:
		var min_angle = deg_to_rad(traverse[0])
		var max_angle = deg_to_rad(traverse[1])
		turret.rotation = clamp(turret.rotation, min_angle, max_angle)
	
	var torque = angle_diff * max_torque - turret.angular_velocity * damping
	
	if abs(angle_diff) > deg_to_rad(1): 
		turret.apply_torque(torque)
	
	# return true if aimed
	return abs(angle_diff) < deg_to_rad(1)
