extends RigidBody2D

var rotation_speed = deg_to_rad(3600)
var pin_joints_created = false

var n = 0

func _physics_process(delta):
	#aim(delta, get_global_mouse_position())
	rotation += delta * 5
	position += Vector2(1, 0)
	n += 1

func aim(delta, target_pos):
	var target_angle = (target_pos - global_position).angle() + deg_to_rad(90)
	var angle_diff = wrapf(target_angle - global_rotation, -PI, PI)
	var rotation_step = rotation_speed * delta
	
	#rotation += clamp(angle_diff, -rotation_speed * delta, rotation_speed * delta)
	apply_torque(1000)
	apply_force(Vector2(100,0))
	#apply_torque(clamp(angle_diff, -rotation_step, rotation_step)* 1000) 
	#var rid = get_rid()
	#PhysicsServer2D.body_set_state(rid,PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY,1)
