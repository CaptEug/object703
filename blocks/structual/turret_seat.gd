class_name TurretSeat
extends Block

var load:float
var turret:RigidBody2D
var traverse:Array
var torque:float

func _ready():
	turret = find_child("Turret") as RigidBody2D

func aim(delta, target_pos):
	var target_angle = (target_pos - global_position).angle() - rotation + deg_to_rad(90)
	var angle_diff = wrapf(target_angle - turret.rotation, -PI, PI)
	if traverse:
		var min_angle = deg_to_rad(traverse[0])
		var max_angle = deg_to_rad(traverse[1])
		turret.rotation = clamp(turret.rotation, min_angle, max_angle)
	
	# return true if aimed
	return abs(angle_diff) < deg_to_rad(1)
