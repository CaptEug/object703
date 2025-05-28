class_name Vehicle
extends Node2D

const GRID_SIZE:int = 16
const FORCE_CHANGE_RATE := 1.0

var move_state:String
var total_power:float
var total_weight:int
var bluepirnt:Dictionary
var grid:= {}
var blocks:= []
var speed_of_increase = 0.05
var direction = Vector2(0, -1)
var track_target_forces := {}  # 存储每个履带的目标力
var track_current_forces := {} # 存储当前实际施加的力
var balanced_forces := {} # 存储直线行驶时的理想出力分布

var debug_draw := true
var com_marker_color := Color(1, 0, 0, 0.7)  # 半透明红色
var com_marker_size := 10.0
var force_vector_color := Color(0, 1, 0, 0.5)  # 半透明绿色
var force_vector_width := 2.0

func _ready():
	for block in blocks:
		block.add_to_group("blocks")
	connect_blocks()
	for track in get_tree().get_nodes_in_group("tracks"):
		track_target_forces[track] = 0.0
		track_current_forces[track] = 0.0
		balanced_forces[track] = 0.0
	# 计算初始平衡力
	calculate_balanced_forces()
	pass # Replace with function body.

func _process(delta):
	update_tracks_state(delta)

func calculate_balanced_forces():
	# 计算直线行驶时各履带的理想出力分布
	var com = calculate_center_of_mass()
	var active_tracks = get_tree().get_nodes_in_group("tracks")
	var total_power = 20
	
	# 1. 计算每个履带到质心的距离
	var distances := {}
	var total_inverse_distance := 0.0
	for track in active_tracks:
		print(track.global_position, com)
		var dist = (track.global_position - com).length()
		# 避免除以零
		distances[track] = max(dist, 0.1)
		total_inverse_distance += 1.0 / distances[track]
	
	# 2. 根据距离分配力 (距离越远出力越大)
	for track in active_tracks:
		var dist_factor = (1.0 / distances[track]) / total_inverse_distance
		balanced_forces[track] = total_power * dist_factor
	
	# 3. 标准化使总力等于引擎功率
	var total_force := 0.0
	for track in active_tracks:
		total_force += balanced_forces[track]
	
	if total_force > 0:
		var scale_factor = total_power / total_force
		for track in active_tracks:
			balanced_forces[track] *= scale_factor

func update_tracks_state(delta):
	var forward_input = Input.get_action_strength("FORWARD") - Input.get_action_strength("BACKWARD")
	
	if Input.is_action_pressed("FORWARD"): 
		move_state = 'forward'
	elif Input.is_action_pressed("BACKWARD"):
		move_state = 'backward'
	else:
		move_state = 'idle'
	
	# 根据平衡力设置目标力
	for track in balanced_forces:
		if move_state == 'forward':
			track_target_forces[track] = balanced_forces[track]
		elif move_state == 'backward':
			track_target_forces[track] = -balanced_forces[track]
		else:
			track_target_forces[track] = 0.0
	
	apply_smooth_track_forces(delta)


func connect_blocks():
	for block in get_tree().get_nodes_in_group('blocks'):
		var size = block.size
		var grid_pos = snap_block_to_grid(block)
		for x in size.x:
			for y in size.y:
				var cell = grid_pos + Vector2i(x, y)
				grid[cell] = block
				connect_adjacent_blocks(cell, grid[cell])

func snap_block_to_grid(block:Block) -> Vector2i:
	var world_pos = block.global_position
	var snapped_pos = Vector2(
		floor(world_pos.x / GRID_SIZE),
		floor(world_pos.y / GRID_SIZE)
	)
	block.global_position = snapped_pos * GRID_SIZE + block.size/2 * GRID_SIZE
	return snapped_pos

func connect_adjacent_blocks(pos:Vector2i, block:Block):
	var directions = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for dir in directions:
		var neighbor_pos = pos + dir
		if grid.has(neighbor_pos) and grid[neighbor_pos] != block:
			var neighbor = grid[neighbor_pos]
			var joint_pos = 8 * dir
			connect_with_joint(block, neighbor, joint_pos)

func connect_with_joint(a:Block, b:Block, joint_pos:Vector2):
	var joint = PinJoint2D.new()
	joint.node_a = a.get_path()
	joint.node_b = b.get_path()
	joint.position = joint_pos
	joint.disable_collision = false
	a.add_child(joint)
	
func calculate_center_of_mass() -> Vector2:
	var total_mass := 0.0
	var weighted_sum := Vector2.ZERO
	var has_calculated := {}
	for grid_pos in grid:
		var body: RigidBody2D = grid[grid_pos]
		if has_calculated.get(body.get_instance_id(), false):
			continue
		var rid = body.get_rid()
		var local_com = PhysicsServer2D.body_get_param(rid, PhysicsServer2D.BODY_PARAM_CENTER_OF_MASS)
		var global_com: Vector2 = body.to_global(local_com)
		weighted_sum += global_com * body.mass
		total_mass += body.mass
		has_calculated[body.get_instance_id()] = true
	return weighted_sum / total_mass if total_mass > 0 else Vector2.ZERO

func get_total_engine_power() -> float:
	var total_power := 0.0
	for engine in get_tree().get_nodes_in_group('engines'):
		if engine.is_inside_tree() and is_instance_valid(engine):
			total_power += engine.power
	return total_power

func apply_smooth_track_forces(delta):
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
