extends RigidBody2D

var rotation_speed = deg_to_rad(360)

func _physics_process(delta):
	#rotation += delta *100
	aim(delta,get_global_mouse_position())

	#apply_torque(100)

func aim(delta, target_pos):
	var target_angle = (target_pos - global_position).angle() + deg_to_rad(90)
	var angle_diff = wrapf(target_angle - global_rotation, -PI, PI)
	var rotation_step = rotation_speed * delta
	
	rotation += clamp(angle_diff, -rotation_step, rotation_step)
