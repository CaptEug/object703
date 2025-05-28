class_name Vehicle
extends Node2D

const GRID_SIZE:int = 16
const FORCE_CHANGE_RATE := 5.0

var move_state:String
var total_power:float
var total_weight:int
var bluepirnt:Dictionary
var grid:= {}
var blocks:= []
var powerpacks:= []
var tracks:= []
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
	connect_blocks()
	for track in tracks:
		track_target_forces[track] = 0.0
		track_current_forces[track] = 0.0
		balanced_forces[track] = 0.0
	# 计算初始平衡力
	calculate_balanced_forces()
	print(balanced_forces)
	pass # Replace with function body.

func _process(delta):
	update_tracks_state(delta)

func calculate_balanced_forces():
	var com = calculate_center_of_mass()
	var active_tracks = tracks
	var total_power = get_total_engine_power()
	
	# 准备推力点数据
	var thrust_points = []
	for track in active_tracks:
		var dir = Vector2.UP.rotated(track.rotation) # 履带前进方向
		thrust_points.append({
			"position": track.global_position - global_position, # 相对位置
			"direction": dir,
			"track": track
		})
	
	# 计算各点出力
	var thrusts = calculate_thrust_distribution(
		thrust_points, 
		com - global_position, # 相对质心
		total_power, 
		direction # 目标方向
	)
	
	# 分配结果
	for point in thrust_points:
		balanced_forces[point.track] = thrusts[point.track]

# 最小二乘解法计算推力分布
func calculate_thrust_distribution(thrust_points: Array, com: Vector2, total_thrust: float, target_dir: Vector2) -> Dictionary:
	var num_points = thrust_points.size()
	if num_points == 0:
		return {}
	
	# 构建矩阵A和向量b
	var A = []
	var b = []
	
	# 1. 合力方程 (x和y方向)
	var eq_force_x = []
	var eq_force_y = []
	for point in thrust_points:
		eq_force_x.append(point.direction.x)
		eq_force_y.append(point.direction.y)
	A.append(eq_force_x)
	b.append(total_thrust * target_dir.x)
	A.append(eq_force_y)
	b.append(total_thrust * target_dir.y)
	
	# 2. 扭矩平衡方程
	var eq_torque = []
	for point in thrust_points:
		var r = point.position - com
		var torque_coeff = r.x * point.direction.y - r.y * point.direction.x
		eq_torque.append(torque_coeff)
	A.append(eq_torque)
	b.append(0.0)  # 目标扭矩为零
	
	# 3. 添加最小能量约束 (防止过度分配)
	for i in range(num_points):
		var eq_energy = array_zero(num_points)
		eq_energy[i] = 1.0
		A.append(eq_energy)
		b.append(0.0)  # 偏好小出力
	
	# 4. 解最小二乘问题 (使用伪逆)
	var x = least_squares_solve(A, b)
	
	# 5. 收集结果并标准化
	var results = {}
	var total = 0.0
	for i in range(num_points):
		var thrust = max(x[i], 0.0)  # 确保非负
		results[thrust_points[i].track] = thrust
		total += thrust
	
	# 标准化到总功率
	if total > 0:
		var scale = total_thrust / total
		for track in results:
			results[track] *= scale
	
	return results

# 辅助函数：最小二乘求解
func least_squares_solve(A: Array, b: Array) -> Array:
	# 这里简化实现，实际项目建议使用性能更好的库
	var At = transpose(A)
	var AtA = multiply(At, A)
	var Atb = multiply_vector(At, b)
	return solve(AtA, Atb)

# 矩阵转置
func transpose(m: Array) -> Array:
	var result = []
	for j in range(m[0].size()):
		result.append([])
		for i in range(m.size()):
			result[j].append(m[i][j])
	return result

# 矩阵乘法
func multiply(a: Array, b: Array) -> Array:
	var result = []
	for i in range(a.size()):
		result.append([])
		for j in range(b[0].size()):
			var sum = 0.0
			for k in range(a[0].size()):
				sum += a[i][k] * b[k][j]
			result[i].append(sum)
	return result

# 矩阵向量乘法
func multiply_vector(m: Array, v: Array) -> Array:
	var result = []
	for i in range(m.size()):
		var sum = 0.0
		for j in range(m[i].size()):
			sum += m[i][j] * v[j]
		result.append(sum)
	return result

func solve(A: Array, b: Array) -> Array:
	# 这里应该使用更稳健的线性求解器
	# 简化版仅用于演示
	var n = A.size()
	for i in range(n):
		# 部分主元选择
		var max_row = i
		for k in range(i+1, n):
			if abs(A[k][i]) > abs(A[max_row][i]):
				max_row = k
		
		# 交换 A[i] 和 A[max_row]
		var tmp_row = A[i] # 临时保存 A[i]
		A[i] = A[max_row]
		A[max_row] = tmp_row
		
		# 交换 b[i] 和 b[max_row]
		var tmp_b = b[i]  # 临时保存 b[i]
		b[i] = b[max_row]
		b[max_row] = tmp_b
		
		# 消元
		for k in range(i+1, n):
			var factor = A[k][i] / A[i][i]
			for j in range(i, n):
				A[k][j] -= factor * A[i][j]
			b[k] -= factor * b[i]
	
	# 回代
	var x = array_zero(n)
	for i in range(n-1, -1, -1):
		x[i] = b[i]
		for j in range(i+1, n):
			x[i] -= A[i][j] * x[j]
		x[i] /= A[i][i]
	return x

func array_zero(size: int) -> Array:
	var arr = []
	arr.resize(size)
	for i in range(size):
		arr[i] = 0.0
	return arr

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
	for block in blocks:
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
		weighted_sum += global_com * body.mass * body.linear_damp
		total_mass += body.mass * body.linear_damp
		has_calculated[body.get_instance_id()] = true
		print(body,body.mass,'   ', body.linear_damp)
	return weighted_sum / total_mass if total_mass > 0 else Vector2.ZERO

func get_total_engine_power() -> float:
	var total_power := 0.0
	for engine in powerpacks:
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
