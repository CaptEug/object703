class_name Track
extends Block

@export var drive_force : float = 1000
@export var grip : float = 0.8
@export var slip_threshold : float = 120.0


func _physics_process(delta):
	pass


func apply_track_force():
	var forward = -global_transform.y
	var vehicle_vel = vehicle.linear_velocity
	# lateral slip (sideways movement)
	var sideways_speed = vehicle_vel.dot(global_transform.x)
	var slip_factor = clamp(1.0 - abs(sideways_speed) / slip_threshold, 0.2, 1.0)
	var traction = grip * slip_factor
	var force = forward * drive_force  * traction
	vehicle.apply_force(force, position)


func apply_side_friction():
	var sideways = global_transform.x
	var vel = vehicle.linear_velocity
	var side_speed = vel.dot(sideways)
	var friction_force = -sideways * side_speed * grip * 50.0
	vehicle.apply_force(friction_force, position)
