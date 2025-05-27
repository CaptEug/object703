class_name Vehicle
extends Node2D

const GRID_SIZE:int = 16
const FORCE_CHANGE_RATE := 1.0
const MAX_DISTANCE_INFLUENCE := 0.2 
const DISTANCE_POWER := 1.5  
const MIN_DISTANCE_FACTOR := 0.6
const STEERING_CHANGE_RATE := 3.0

var move_state:String
var total_power:float
var total_weight:int
var bluepirnt:Dictionary
var grid:= {}
var blocks:= []
var _avg_error := 0.0
var power_increase = 0.0 #测试用用
var speed_of_increase = 0.05
var direction = Vector2(0, -1)
var rotation_power := 0.5
# Called when the node enters the scene tree for the first time.
var track_target_forces := {}  # 存储每个履带的目标力
var track_current_forces := {} # 存储当前实际施加的力
var steering_input := 0.0  # 转向输入值(-1到1)
var target_steering := 0.0 # 目标转向值
var current_steering := 0.0
var is_pure_steering := false

func _ready():
	for block in blocks:
		block.add_to_group("blocks")
	connect_blocks()
	for track in get_tree().get_nodes_in_group("tracks"):
		track_target_forces[track] = 0.0
		track_current_forces[track] = 0.0
	pass # Replace with function body.

func _process(delta):
	update_tracks_state(delta)
	print(direction)

func _update_direction_from_velocity():
	var com_velocity = get_physics_com_velocity()
	if com_velocity.length() > 0: 
		direction = Vector2.UP.rotated($Bridge.global_rotation).normalized()
		if move_state == "backward":
			direction *= -1

func connect_blocks():
	for block in get_tree().get_nodes_in_group('blocks'):
		var snapped_pos = snap_block_to_grid(block)
		grid[snapped_pos] = block
		connect_adjacent_blocks(snapped_pos, block)

func get_total_engine_power() -> float:
	var total_power := 0.0
	for engine in get_tree().get_nodes_in_group('engines'):
		if engine.is_inside_tree() and is_instance_valid(engine):
			total_power += engine.power
	return total_power * power_increase

func update_tracks_state(delta):
	var forward_input = Input.get_action_strength("FORWARD") - Input.get_action_strength("BACKWARD")
	steering_input = Input.get_action_strength("PIVOT_LEFT") - Input.get_action_strength("PIVOT_RIGHT")
	target_steering = steering_input
	current_steering = lerp(current_steering, target_steering, STEERING_CHANGE_RATE * delta)
	is_pure_steering = (forward_input == 0.0 and steering_input != 0.0)
	if Input.is_action_just_released("PIVOT_LEFT") or Input.is_action_just_released("PIVOT_RIGHT"):
		_update_direction_from_velocity()
	
	if Input.is_action_pressed("FORWARD"): 
		move_state = 'forward'
	elif Input.is_action_pressed("BACKWARD"):
		move_state = 'backward'
	else:
		move_state = 'idle'
	
	target_steering = steering_input
	current_steering = lerp(current_steering, target_steering, STEERING_CHANGE_RATE * delta)
	
	update_tracks_force(delta)
	apply_smooth_track_forces(delta)
	_power_increase()

func _power_increase():
	if move_state != 'idle':
		if power_increase < 1:
			power_increase += speed_of_increase
	else:
		if power_increase > 0:
			power_increase -= speed_of_increase

func snap_block_to_grid(block:Block) -> Vector2i:
	var world_pos = block.global_position
	var snapped_pos = Vector2(
		floor(world_pos.x / GRID_SIZE),
		floor(world_pos.y / GRID_SIZE)
	)
	block.global_position = snapped_pos * GRID_SIZE + block.size/2 * GRID_SIZE
	return snapped_pos  # useful for tracking in a grid dictionary

func connect_adjacent_blocks(pos:Vector2i, block:Block):
	var directions = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for dir in directions:
		var neighbor_pos = pos + dir
		if grid.has(neighbor_pos):
			var neighbor = grid[neighbor_pos]
			connect_with_joint(block, neighbor, dir)

func connect_with_joint(a:Block, b:Block, dir):
	var joint = PinJoint2D.new()
	joint.node_a = a.get_path()
	joint.node_b = b.get_path()
	# Place joint in the middle of the two blocks
	if dir == Vector2i.LEFT:
		joint.position.x = - a.size.x * GRID_SIZE / 2.0
	if dir == Vector2i.RIGHT:
		joint.position.x = a.size.x * GRID_SIZE / 2.0
	if dir == Vector2i.UP:
		joint.position.y = - a.size.y * GRID_SIZE / 2.0
	if dir == Vector2i.DOWN:
		joint.position.y = a.size.y * GRID_SIZE / 2.0
	joint.disable_collision = false
	a.add_child(joint)
	
func calculate_center_of_mass() -> Vector2:
	var total_mass := 0.0
	var weighted_sum := Vector2.ZERO
	for grid_pos in grid:
		var body: RigidBody2D = grid[grid_pos]
		var rid = body.get_rid()
		var local_com = PhysicsServer2D.body_get_param(rid, PhysicsServer2D.BODY_PARAM_CENTER_OF_MASS)
		var global_com: Vector2 = body.to_global(local_com)
		weighted_sum += global_com * body.mass
		total_mass += body.mass
	return weighted_sum / total_mass if total_mass > 0 else Vector2.ZERO
	
func get_physics_com_velocity() -> Vector2:
	var total_mass := 0.0
	var momentum_sum := Vector2.ZERO
	for grid_pos in grid:
		var body: RigidBody2D = grid[grid_pos]
		var rid = body.get_rid()
		var state = PhysicsServer2D.body_get_state(rid, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
		momentum_sum += state * body.mass
		total_mass += body.mass
	return momentum_sum / total_mass

func _get_heading_error() -> float:
	var mass_linear_velocity = get_physics_com_velocity()
	if mass_linear_velocity.length() < 0.5:
		return 0.0
	var current_dir = mass_linear_velocity.normalized()
	var target_dir = direction
	if move_state == 'backward':
		target_dir *= -1
	var error = current_dir.angle_to(target_dir)
	_avg_error = 0.9 * _avg_error + 0.1 * abs(error)
	return error

func apply_smooth_track_forces(delta):
	"""
	平滑地将当前力过渡到目标力
	使用线性插值(lerp)实现力的渐变效果
	"""
	for track in track_target_forces:
		var target = track_target_forces[track]
		var current = track_current_forces[track]
		
		# 使用lerp平滑过渡
		var new_force = lerp(current, target, FORCE_CHANGE_RATE * delta)
		
		# 只有当力足够大时才施加
		if abs(new_force) > 0:
			track.set_state_force(move_state, new_force)
			track_current_forces[track] = new_force
		else:
			track.set_state_force('idle', 0)
			track_current_forces[track] = 0.0

func update_tracks_force(delta):
	var total_power = get_total_engine_power()
	var active_tracks = get_tree().get_nodes_in_group("tracks")
	var com = calculate_center_of_mass()
	var min_distance = INF
	var max_distance = 0.0
	
	if is_pure_steering:
		# 纯转向模式 - 两侧履带施加相反的力
		var total_force = 0.0
		for track in active_tracks:
			var track_pos = track.global_position
			var force_dir = Vector2.UP.rotated($Bridge.global_rotation)
			var steering_side = sign((track_pos - com).cross(force_dir))
			
			# 确定力的大小和方向
			var force_magnitude = min(total_power * rotation_power * abs(current_steering), total_power * 0.5)
			var force_direction = -sign(steering_side) * sign(current_steering)
			
			# 设置目标力（内侧和外侧履带力方向相反）
			track_target_forces[track] = force_magnitude * force_direction
			total_force += force_magnitude
		
		# 确保总力不超过引擎功率
		if total_force > total_power:
			var scale_factor = total_power / total_force
			for track in active_tracks:
				track_target_forces[track] *= scale_factor
		return
	
	var steering_diff = current_steering * rotation_power * (1.0 + power_increase)
	for track in active_tracks:
		var dist = (track.global_position - com).length()
		min_distance = min(min_distance, dist)
		max_distance = max(max_distance, dist)
	var distance_range = max(max_distance - min_distance, 1.0)
	var total_weight := 0.0
	var heading_error := _get_heading_error()

	# 计算总权重
	for track in active_tracks:
		var dist = (track.global_position - com).length()
		var normalized_dist = (dist - min_distance) / distance_range
		var distance_factor = 1.0 - MAX_DISTANCE_INFLUENCE * pow(normalized_dist, DISTANCE_POWER)
		distance_factor = max(distance_factor, MIN_DISTANCE_FACTOR)
		total_weight += track.size.x * track.size.y * distance_factor

	# 为每个履带计算目标力（包含改进的距离因素）
	var total_force_applied = 0.0
	for track in active_tracks:
		var track_pos = track.global_position
		var force_dir = Vector2.UP.rotated($Bridge.global_rotation)
		var dist = (track_pos - com).length()
		var normalized_dist = (dist - min_distance) / distance_range
		var distance_factor = 1.0 - MAX_DISTANCE_INFLUENCE * pow(normalized_dist, DISTANCE_POWER)
		distance_factor = max(distance_factor, MIN_DISTANCE_FACTOR)
		
		var area_weight = track.size.x * track.size.y
		var steering_side = sign((track_pos - com).cross(force_dir))
		var differential_factor = 1.0 - steering_side * steering_diff * 2.0
		var base_force = total_power * (area_weight * distance_factor / total_weight)
		var directional_force = base_force * differential_factor
		
		# 前进/后退修正
		if move_state == 'forward':
			directional_force = abs(directional_force)
		elif move_state == 'backward':
			directional_force = -abs(directional_force)
		
		# 转向因子（距离敏感的转向修正）
		var steering_factor = 1.0
		if abs(heading_error) > 0:
			var track_side = sign((track_pos - com).cross(force_dir))
			if move_state == 'backward':
				track_side *= -1
			
			# 距离越远的履带转向修正影响越大
			var distance_sensitivity = 1.0 + normalized_dist * 0.5
			var correction_strength = 10.0 * distance_sensitivity
			
			if _avg_error > 0.2:
				correction_strength *= 1.1
				
			steering_factor = clamp(1.0 - track_side * heading_error * correction_strength * delta, 0.7, 1.3)
		
		var final_force = directional_force * steering_factor
		track_target_forces[track] = final_force
		total_force_applied += abs(final_force)
	
	# 确保总施加力不超过引擎功率
	if total_force_applied > total_power:
		var scale_factor = total_power / total_force_applied
		for track in active_tracks:
			track_target_forces[track] *= scale_factor

func get_track_side(track_position: Vector2, com: Vector2) -> float:
	var force_dir = Vector2.UP.rotated($Bridge.global_rotation)
	return sign((track_position - com).cross(force_dir))
