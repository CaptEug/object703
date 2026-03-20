class_name Track
extends Block


var drive_force : float = 0.0
@export var max_force : float = 100.0
@export var grip : float = 0.8
@export var slip_threshold : float = 100.0


func _physics_process(_delta):
	if vehicle:
		if absf(drive_force) > 0.0001:
			apply_drive_force()
		apply_side_friction()


func apply_drive_force():
	var forward = -global_transform.y
	var vehicle_vel = vehicle.linear_velocity
	# lateral slip (sideways movement)
	var sideways_speed = vehicle_vel.dot(global_transform.x)
	var slip_factor = clamp(1.0 - abs(sideways_speed) / slip_threshold, 0.2, 1.0)
	var traction = grip * slip_factor
	var force = forward * drive_force  * traction
	var offset := global_position - vehicle.global_position
	vehicle.apply_force(force, offset)


func apply_side_friction():
	var sideways = global_transform.x
	var vel = vehicle.linear_velocity
	var side_speed = vel.dot(sideways)
	var friction_force = -sideways * side_speed * grip
	vehicle.apply_force(friction_force, position)
