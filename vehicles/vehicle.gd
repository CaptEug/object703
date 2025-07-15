class_name Vehicle
extends Node2D

const GRID_SIZE:int = 16
const FORCE_CHANGE_RATE := 50.0
const MAX_ROTING_POWER := 0.1

var vehicle_size:Vector2i
var vehicle_name:String
var move_state:String
var max_engine_power:float
var current_engine_power:float
var total_weight:int
var total_ammo:float
var total_ammo_cap:float
var total_fuel:float
var total_fuel_cap:float
var total_store:int
var blueprint:Variant
var blueprint_grid:= {}
var grid:= {}
var blocks:= []
var powerpacks:= []
var tracks:= []
var ammoracks:= []
var fueltanks := []
var commands := []
var speed_of_increase = 0.05
var direction = Vector2(0, -1)
var track_target_forces := {}  # 存储每个履带的目标力
var track_current_forces := {} # 存储当前实际施加的力
var balanced_forces := {} # 存储直线行驶时的理想出力分布
var rotation_forces := {} # 存储纯旋转时的理想出力分布
var control:Callable
var controls:= []
var is_assembled := false
var block_scenes := {}
var selected:bool


func _ready():
	if blueprint:
		Get_ready_again()


func Get_ready_again():
	if blueprint is String:
		load_from_file(blueprint)
	elif blueprint is Dictionary:
		load_from_blueprint(blueprint)
	else:
		push_error("Invalid blueprint format")
	update_vehicle()
	print(grid)


func _process(delta):
	if control:
		update_tracks_state(control.call(), delta)


func update_vehicle():
	#Check block connectivity
	for block in blocks:
		block.get_neighors()
	#Get all total parameters
	get_max_engine_power()
	get_current_engine_power()
	get_ammo_cap()
	update_current_ammo()
	get_fuel_cap()
	update_current_fuel()
	update_vehicle_size()
	# 重新计算物理属性
	calculate_center_of_mass()
	calculate_balanced_forces()
	calculate_rotation_forces()
	# 重新获取控制方法
	if not check_control(control.get_method()):
		if not check_control("AI_control"):
			if not check_control("remote_control"):
				if not check_control("manual_control"):
					control = Callable()

###################### BLOCK MANAGEMENT ######################

func _add_block(block: Block, grid_positions):
	if block not in blocks:
		# 添加方块到车辆
		add_child(block)
		blocks.append(block)
		
		if block is Track:
			tracks.append(block)
			track_target_forces[block] = 0.0
			track_current_forces[block] = 0.0
		elif block is Powerpack:
			powerpacks.append(block)
		elif block is Command:
			commands.append(block)
		elif block is Ammorack:
			ammoracks.append(block)
		elif block is Fueltank:
			fueltanks.append(block)
		for pos in grid_positions:
			grid[pos] = block
		block.position = Vector2(grid_positions[0]*GRID_SIZE) + Vector2(block.size * GRID_SIZE / 2)
		block.global_rotation = rotation
		connect_to_adjacent_blocks(block)
	update_vehicle()

func remove_block(block: Block):
	if block in blocks:
		blocks.erase(block)
	if block in grid:
		grid.erase(block)
	if block in tracks:
		tracks.erase(block)
	if block in powerpacks:
		powerpacks.erase(block)
	if block in commands:
		commands.erase(block)
	if block in ammoracks:
		ammoracks.erase(block)
	if block in fueltanks:
		fueltanks.erase(block)
	update_vehicle()

func has_block(block_name:String):
	for block in blocks:
		if block.block_name == block_name:
			return block

func find_pos(Dic: Dictionary, block:Block) -> Vector2i:
	for pos in Dic:
		if Dic[pos] == block:
			return pos
	return Vector2i.ZERO


##################### VEHICLE PARAMETER MANAGEMENT #####################

func check_control(control_name:String):
	for block in commands:
		if block.has_method(control_name):
			control = Callable(block, control_name)
			return true
	return false

func get_max_engine_power() -> float:
	var max_power := 0.0
	for engine in powerpacks:
		if engine.is_inside_tree() and is_instance_valid(engine):
			max_power += engine.max_power
	current_engine_power = max_power
	return max_power

func get_current_engine_power() -> float:
	var currunt_power := 0.0
	for engine in powerpacks:
		if engine.is_inside_tree() and is_instance_valid(engine):
			currunt_power += engine.power
	current_engine_power = currunt_power
	return currunt_power

func get_ammo_cap():
	var ammo_cap := 0.0
	for ammorack in ammoracks:
		if ammorack.is_inside_tree() and is_instance_valid(ammorack):
			ammo_cap += ammorack.ammo_storage_cap
	total_ammo_cap = ammo_cap
	return ammo_cap

func update_current_ammo():
	var currunt_ammo := 0.0
	for ammorack in ammoracks:
		if ammorack.is_inside_tree() and is_instance_valid(ammorack):
			currunt_ammo += ammorack.ammo_storage
	total_ammo = currunt_ammo
	return currunt_ammo

func get_fuel_cap():
	var fuel_cap := 0.0
	for fueltank in fueltanks:
		if fueltank.is_inside_tree() and is_instance_valid(fueltank):
			fuel_cap += fueltank.FUEL_CAPACITY
	total_fuel_cap = fuel_cap
	return fuel_cap

func update_current_fuel():
	var currunt_fuel := 0.0
	for fueltank in fueltanks:
		if fueltank.is_inside_tree() and is_instance_valid(fueltank):
			currunt_fuel += fueltank.fuel_storage
	total_fuel = currunt_fuel
	return currunt_fuel



########################## VEHICLE LOADING ###########################

func load_from_file(identifier):  # 允许接收多种类型参数
	var path: String
	if identifier is String:
		if not identifier.ends_with(".json"):
			path = "res://vehicles/blueprint/%s.json" % identifier
		else:
			path = identifier
	elif identifier is int:
		path = "res://vehicles/blueprint/%d.json" % identifier
	else:
		push_error("Invalid file identifier type: ", typeof(identifier))
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		if error == OK:
			load_from_blueprint(json.data)
		else:
			push_error("JSON parse error: ", json.get_error_message())
	else:
		push_error("Failed to load file: ", path)

func load_from_blueprint(bp: Dictionary):
	clear_existing_blocks()
	# 按数字键排序以保证加载顺序一致
	var block_ids = bp["blocks"].keys()
	var _name = bp["name"]
	vehicle_name = _name
	block_ids.sort()
	vehicle_size = Vector2i(bp["vehicle_size"][0], bp["vehicle_size"][1])
	
	for block_id in block_ids:
		var block_data = bp["blocks"][block_id]
		var block_scene = load(block_data["path"])  # 使用完整路径加载
		
		if block_scene:
			var block = block_scene.instantiate()
			var size = Vector2(block_data["size"][0], block_data["size"][1])
			var base_pos = Vector2(block_data["base_pos"][0], block_data["base_pos"][1])
			block.rotation = get_rotation_angle(block_data["rotation"])
			block.size = size
			var target_grid = []
			# 记录所有网格位置
			for x in size.x:
				for y in size.y:
					var grid_pos = Vector2i(base_pos) + Vector2i(x, y)
					target_grid.append(grid_pos)
			_add_block(block, target_grid)

func get_rotation_angle(dir: String) -> float:
	match dir:
		"left":    return PI/2
		"up": return 0
		"right":  return -PI/2
		"down":  return PI
		_:       return PI/2

func clear_existing_blocks():
	for block in blocks:
		block.queue_free()
	blocks.clear()
	grid.clear()
	tracks.clear()
	powerpacks.clear()
	track_target_forces.clear()
	track_current_forces.clear()

func get_blueprint_path() -> String:
	if blueprint is String:
		return blueprint
	elif blueprint is Dictionary:
		return "res://vehicles/blueprint/%s.json" % vehicle_name
	return ""

func connect_to_adjacent_blocks(block: Block):
	# 找到方块在网格中的基准位置
	var base_pos: Vector2i = Vector2i.ZERO
	for pos in grid:
		if grid[pos] == block:
			base_pos = pos
			break
	
	# 检查四个方向的相邻方块
	var directions = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for x in block.size.x:
		for y in block.size.y:
			for dir in directions:
				var neighbor_pos = base_pos + dir + Vector2i(x, y)
				if grid.has(neighbor_pos):
					var neighbor = grid[neighbor_pos]
					if neighbor != block:
						var global_base_pos = block.position - Vector2(block.size * GRID_SIZE)/2 + Vector2(8.0,8.0)
						var global_joint_pos = Vector2(global_base_pos) + Vector2(x, y) * GRID_SIZE + Vector2(8* dir)
						var joint_pos = Vector2(global_joint_pos) - block.position
						connect_with_joint(block, neighbor, joint_pos)

func connect_with_joint(a:Block, b:Block, joint_pos:Vector2):
	var joint = PinJoint2D.new()
	joint.node_a = a.get_path()
	joint.node_b = b.get_path()
	joint.global_position = joint_pos
	joint.disable_collision = false
	a.add_child(joint)
	


########################## VEHICLE PHYSICS PROCESSING #######################

func calculate_center_of_mass() -> Vector2:
	var total_mass := 0.0
	var weighted_sum := Vector2.ZERO
	var has_calculated := {}
	for grid_pos in grid:
		if  grid[grid_pos] != null:
			var body: RigidBody2D = grid[grid_pos]
			if blocks.has(body):
				if has_calculated.get(body.get_instance_id(), false):
					continue
				var rid = body.get_rid()
				var local_com = PhysicsServer2D.body_get_param(rid, PhysicsServer2D.BODY_PARAM_CENTER_OF_MASS)
				var global_com: Vector2 = body.to_global(local_com)
				weighted_sum += global_com * body.mass
				total_mass += body.mass
				has_calculated[body.get_instance_id()] = true
	return weighted_sum / total_mass if total_mass > 0 else Vector2.ZERO


func calculate_balanced_forces():
	var com = calculate_center_of_mass()
	var active_tracks = tracks
	var currunt_total_power = get_current_engine_power()
	
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
		currunt_total_power,
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
		var currunt_scale = total_thrust / total
		for track in results:
			results[track] *= currunt_scale
	
	return results
	
func calculate_rotation_forces():
	var com = calculate_center_of_mass()
	var active_tracks = tracks
	var currunt_total_power = get_current_engine_power()
	
	# 准备推力点数据
	var thrust_points = []
	for track in active_tracks:
		var dir = Vector2.UP.rotated(track.rotation) # 履带前进方向
		thrust_points.append({
			"position": track.global_position - global_position, # 相对位置
			"direction": dir,
			"track": track
		})
	
	# 计算各点出力 - 纯旋转
	var thrusts = calculate_rotation_thrust_distribution(
		thrust_points,
		com - global_position, # 相对质心
		currunt_total_power * MAX_ROTING_POWER # 总功率
	)
	
	# 分配结果
	for point in thrust_points:
		rotation_forces[point.track] = thrusts[point.track]

# 计算纯旋转时的推力分布
func calculate_rotation_thrust_distribution(thrust_points: Array, com: Vector2, total_thrust: float) -> Dictionary:
	var num_points = thrust_points.size()
	if num_points == 0:
		return {}
	
	# 构建矩阵A和向量b
	var A = []
	var b = []
	
	# 1. 扭矩平衡方程 (产生最大扭矩)
	var eq_torque = []
	for point in thrust_points:
		var r = point.position - com
		var torque_coeff = r.x * point.direction.y - r.y * point.direction.x
		eq_torque.append(torque_coeff)
	A.append(eq_torque)
	b.append(total_thrust)  # 目标扭矩最大化
	
	# 2. 合力平衡方程 (x和y方向应该为零)
	var eq_force_x = []
	var eq_force_y = []
	for point in thrust_points:
		eq_force_x.append(point.direction.x)
		eq_force_y.append(point.direction.y)
	A.append(eq_force_x)
	b.append(0.0)
	A.append(eq_force_y)
	b.append(0.0)
	
	# 3. 添加最小能量约束
	for i in range(num_points):
		var eq_energy = array_zero(num_points)
		eq_energy[i] = 1.0
		A.append(eq_energy)
		b.append(0.0)
	
	# 4. 解最小二乘问题
	var x = least_squares_solve(A, b)
	
	# 5. 收集结果并标准化
	var results = {}
	var total = 0.0
	for i in range(num_points):
		results[thrust_points[i].track] = x[i]
		total += abs(x[i])
	
	# 标准化到总功率
	if total > 0:
		var currunt_scale = total_thrust / total
		for track in results:
			results[track] *= currunt_scale
	
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

func update_tracks_state(control_input:Array, delta):
	var forward_input = control_input[0]
	var turn_input = control_input[1]
	var currunt_scale = 0
	
	if forward_input == 0 and turn_input == 0:
		move_state = 'idle'
	else:
		move_state = 'move'
	
	var total_forward = 0
	var total_turn = 0
	for track in balanced_forces:
		track_target_forces[track] = balanced_forces[track] * forward_input + rotation_forces[track] * turn_input
		total_forward += abs(balanced_forces[track] * forward_input)
		total_turn += abs(rotation_forces[track] * turn_input)
	if total_forward > 0:
		currunt_scale = current_engine_power / (total_forward + total_turn)
	else:
		currunt_scale = current_engine_power * MAX_ROTING_POWER / (total_forward + total_turn)
	for track in track_target_forces:
		track_target_forces[track] *= currunt_scale
	
	apply_smooth_track_forces(delta)


func apply_smooth_track_forces(delta):
	for track in track_target_forces:
		var target = track_target_forces[track]
		var current = track_current_forces[track]
		# 使用lerp平滑过渡
		var new_force = lerp(current, target, FORCE_CHANGE_RATE * delta)
		
		if tracks.has(track) and current_engine_power != 0:
			if abs(new_force) > 0:
				track.set_state_force(move_state, new_force)
				track_current_forces[track] = new_force
			else:
				track.set_state_force('idle', 0)
				track_current_forces[track] = 0.0

func update_vehicle_size():
	var min_x:int
	var min_y:int
	var max_x:int
	var max_y:int
	
	for grid_pos in grid:
		min_x = grid_pos.x
		min_y = grid_pos.y
		max_x = grid_pos.x
		max_y = grid_pos.y
		break
	
	for grid_pos in grid:
		if min_x > grid_pos.x:
			min_x = grid_pos.x
		if min_y > grid_pos.y:
			min_y = grid_pos.y
		if max_x < grid_pos.x:
			max_x = grid_pos.x
		if max_y < grid_pos.y:
			max_y = grid_pos.y
	
	vehicle_size = Vector2i(max_x - min_x + 1, max_y - min_y + 1)
