class_name Vehicle
extends Node2D

const GRID_SIZE:int = 16

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
var fueltanks:= []
var commands:= []
var vehicle_panel:Panel
var speed_of_increase = 0.05
var direction = Vector2(0, -1)
var track_target_forces:= {}  # 存储每个履带的目标力
var track_current_forces:= {} # 存储当前实际施加的力
var balanced_forces:= {} # 存储直线行驶时的理想出力分布
var rotation_forces:= {} # 存储纯旋转时的理想出力分布
var control:Callable
var controls:= []
var targets:= []
var is_assembled:= false
var block_scenes:= {}
var selected:bool
var destroyed:bool
var center_of_mass:Vector2 = Vector2(0,0)
var ready_connect = true


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


func _process(delta):
	if ready_connect == false:
		for block:Block in blocks:
			if block.joint_connected_blocks.size() != 0:
				block.set_connection_enabled(false)
				ready_connect = true
	center_of_mass = calculate_center_of_mass()
	if control:
		update_tracks_state(control.call(), delta)
	#updating targets
	var current_targets = []
	for block in commands:
		current_targets += block.targets
	targets = current_targets


func update_vehicle():
	#Check block connectivity
	for block:Block in blocks:
		block.get_neighbors()
		block.get_all_connected_blocks()
	
	#Get all total parameters
	get_max_engine_power()
	get_current_engine_power()
	get_ammo_cap()
	get_current_ammo()
	get_fuel_cap()
	get_current_fuel()
	update_vehicle_size()
	# 重新计算物理属性
	calculate_center_of_mass()
	calculate_balanced_forces()
	calculate_rotation_forces()
	# 重新获取控制方法
	if not check_control(control.get_method()):
		if not check_control("AI_control"):
			if not check_control("remote_control"):
				control = Callable()
			else: control = check_control("remote_control")
		else: control = check_control("AI_control")
	
	#check vehicle destroyed
	var has_command:= false
	for blk in commands:
		if blk.functioning:
			has_command = true
	destroyed = not has_command

###################### BLOCK MANAGEMENT ######################

func _add_block(block: Block,local_pos, grid_positions):
	if block not in blocks:
		# 添加方块到车辆
		add_child(block)
		blocks.append(block)
		block.position = local_pos
		block.global_grid_pos = get_rectangle_corners(grid_positions)
		
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
		block.set_connection_enabled(true)
	update_vehicle()

func remove_block(block: Block, imd: bool):
	blocks.erase(block)
	if imd:
		block.queue_free()

	var keys_to_erase = []
	for pos in grid:
		if grid[pos] == block:
			keys_to_erase.append(pos)
	for pos in keys_to_erase:
		grid.erase(pos)
	
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
	for blk:Block in blocks:
		blk.check_connectivity()

func has_block(block_name:String):
	for block in blocks:
		if block.block_name == block_name:
			return block

func find_pos(Dic: Dictionary, block:Block):
	var positions = []
	for pos in Dic:
		if Dic[pos] == block:
			positions.append(pos)
	var top_left = positions[0]
	for v in positions:
		if v.x < top_left.x or (v.x == top_left.x and v.y < top_left.y):
			top_left = v
	return top_left


##################### VEHICLE PARAMETER MANAGEMENT #####################

func check_control(control_name:String):
	for block in commands:
		if block.has_method(control_name) and block.functioning:
			return Callable(block, control_name)
	return false

func get_max_engine_power() -> float:
	var max_power := 0.0
	for engine in powerpacks:
		if engine.is_inside_tree() and is_instance_valid(engine):
			max_power += engine.max_power
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

func get_current_ammo():
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

func get_current_fuel():
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
	ready_connect = false
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
			var block:Block = block_scene.instantiate()
			var base_pos = Vector2(block_data["base_pos"][0], block_data["base_pos"][1])
			block.rotation = deg_to_rad(block_data["rotation"][0])
			block.base_rotation_degree = block_data["rotation"][0]
			var target_grid = []
			# 记录所有网格位置
			for x in block.size.x:
				for y in block.size.y:
					var grid_pos
					if block.base_rotation_degree == 0:
						grid_pos = Vector2i(base_pos) + Vector2i(x, y)
					elif block.base_rotation_degree == 90:
						grid_pos = Vector2i(base_pos) + Vector2i(-y, x)
					elif block.base_rotation_degree == -90:
						grid_pos = Vector2i(base_pos) + Vector2i(y, -x)
					else:
						grid_pos = Vector2i(base_pos) + Vector2i(-x, -y)
					target_grid.append(grid_pos)
			var local_pos = get_rectangle_corners(target_grid)
			_add_block(block, local_pos, target_grid)

func get_rectangle_corners(grid_data):
	if grid_data.is_empty():
		return []
	
	var x_coords = []
	var y_coords = []
	
	for coord in grid_data:
		x_coords.append(coord[0])
		y_coords.append(coord[1])
	
	x_coords.sort()
	y_coords.sort()
	
	var min_x = x_coords[0]
	var max_x = x_coords[x_coords.size() - 1]
	var min_y = y_coords[0]
	var max_y = y_coords[y_coords.size() - 1]

	
	var vc_1 = Vector2(min_x * GRID_SIZE, min_y * GRID_SIZE)
	var vc_2 = Vector2(max_x * GRID_SIZE + GRID_SIZE, max_y * GRID_SIZE + GRID_SIZE)
	
	var pos = (vc_1 + vc_2)/2
	
	return pos


func get_rotation_angle(dir: String) -> float:
	match dir:
		"left":    return -PI/2
		"up": return 0
		"right":  return PI/2
		"down":  return PI
		_:       return 0

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

########################## VEHICLE PHYSICS PROCESSING #######################

func get_block_grid(block:Block) -> Array:
	var getpositions:Array
	for pos in grid.keys():
		if grid[pos] == block and not getpositions.has(pos):
			getpositions.append(pos)
	return getpositions

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
				var rid = get_block_grid(body)
				var global_com:Vector2 = get_rectangle_corners(rid)
				weighted_sum += global_com * body.mass
				total_mass += body.mass
				has_calculated[body.get_instance_id()] = true
	return weighted_sum / total_mass if total_mass > 0 else Vector2.ZERO


func calculate_balanced_forces():
	var com = calculate_center_of_mass()
	var active_tracks = tracks
	
	# 准备推力点数据
	var thrust_points = []
	for track:Track in active_tracks:
		if track.functioning == true:
			var dir = Vector2.UP.rotated(deg_to_rad(track.base_rotation_degree))
			var positions_grid = get_block_grid(track)
			thrust_points.append({
				"position": get_rectangle_corners(positions_grid), # 相对位置
				"direction": dir,
				"track": track
			})
	# 计算各点出力
	var thrusts = calculate_thrust_distribution(
		thrust_points,
		com, 
		1,
		direction # 目标方向
	)
	balanced_forces = {}
	# 分配结果
	for point in thrust_points:
		balanced_forces[point.track] = thrusts[point.track]
	return balanced_forces

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
		var thrust = x[i] # 确保非负
		results[thrust_points[i].track] = thrust
		total += abs(thrust)
	
	# 标准化到总功率
	if total > 0:
		var currunt_scale = total_thrust / total
		for track in results:
			results[track] *= currunt_scale
	
	return results
	
func calculate_rotation_forces():
	var com = calculate_center_of_mass()
	var active_tracks = tracks
	
	# 准备推力点数据
	var thrust_points = []
	for track:Track in active_tracks:
		if track.functioning == true:
			var dir = Vector2.UP.rotated(deg_to_rad(track.base_rotation_degree))
			var positions_grid = get_block_grid(track)
			thrust_points.append({
				"position": get_rectangle_corners(positions_grid),
				"direction": dir,
				"track": track
			})
	
	# 计算各点出力 - 纯旋转
	var thrusts = calculate_rotation_thrust_distribution(
		thrust_points,
		com, # 相对质心
		1 # 总功率
	)
	
	# 分配结果
	for point in thrust_points:
		if direction.y > 0:
			rotation_forces[point.track] = -thrusts[point.track]
		else:
			rotation_forces[point.track] = thrusts[point.track]
	return rotation_forces

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
	var At = transpose(A)
	var AtA = multiply(At, A)
	
	# 添加正则化项 (Tikhonov 正则化)
	var lambda = 0.01  # 正则化参数
	var n = AtA.size()
	for i in range(n):
		AtA[i][i] += lambda
	
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
	var n = A.size()
	if n == 0:
		return []
	
	# 复制矩阵，避免修改原数据
	var A_copy = []
	var b_copy = []
	for i in range(n):
		A_copy.append(A[i].duplicate())
		b_copy.append(b[i])
	
	# 高斯消元
	for i in range(n):
		# 部分主元选择
		var max_row = i
		var max_val = abs(A_copy[i][i])
		for k in range(i+1, n):
			if abs(A_copy[k][i]) > max_val:
				max_val = abs(A_copy[k][i])
				max_row = k
		
		# 如果主元接近0，说明矩阵奇异
		if abs(A_copy[max_row][i]) < 1e-10:
			print("警告: 矩阵接近奇异，主元值: ", A_copy[max_row][i])
			# 返回零解
			return array_zero(n)
		
		# 交换行
		if max_row != i:
			var tmp_row = A_copy[i]
			A_copy[i] = A_copy[max_row]
			A_copy[max_row] = tmp_row
			
			var tmp_b = b_copy[i]
			b_copy[i] = b_copy[max_row]
			b_copy[max_row] = tmp_b
		
		# 消元
		var pivot = A_copy[i][i]
		for k in range(i+1, n):
			var factor = A_copy[k][i] / pivot
			for j in range(i, n):
				A_copy[k][j] -= factor * A_copy[i][j]
			b_copy[k] -= factor * b_copy[i]
	
	# 回代
	var x = array_zero(n)
	for i in range(n-1, -1, -1):
		x[i] = b_copy[i]
		for j in range(i+1, n):
			x[i] -= A_copy[i][j] * x[j]
		x[i] /= A_copy[i][i]
	
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
	
	if forward_input == 0 and turn_input == 0:
		move_state = 'idle'
		for engine:Powerpack in powerpacks:
			engine.Power_reduction(delta)
			engine.state["move"] = false
			engine.state["rotate"] = false
	else:
		move_state = 'move'
		if forward_input != 0:
			for engine:Powerpack in powerpacks:
				engine.state["move"] = true
		else:
			for engine:Powerpack in powerpacks:
				engine.state["move"] = false
		if turn_input != 0:
			for engine:Powerpack in powerpacks:
				engine.state["rotate"] = true
		else:
			for engine:Powerpack in powerpacks:
				engine.state["rotate"] = false
	if get_track_forces(forward_input, turn_input) != null:
		get_current_engine_power()
		track_target_forces = get_track_forces(forward_input, turn_input)
	apply_smooth_track_forces(delta)

func get_track_forces(forward_input, turn_input):
	var most_power = null
	for engine:Powerpack in powerpacks:
		engine.caculate_most_move_power(forward_input, turn_input)
		if most_power == null:
			most_power = engine.track_power_target
		else:
			for track in most_power:
				most_power[track] += engine.track_power_target[track]
	return most_power
	

func apply_smooth_track_forces(_delta):
	for track in track_target_forces:
		var target = track_target_forces[track]
		var new_force = target
		if tracks.has(track) and current_engine_power != 0:
			if abs(new_force) > 0:
				track.set_state_force(move_state, new_force)
				track_current_forces[track] = new_force
			else:
				track.set_state_force('idle', 0)

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

# 获取距离某个位置一定范围内的可用连接点
func get_available_points_near_position(_position: Vector2, max_distance: float = 30.0) -> Array[ConnectionPoint]:
	var temp_points = []
	var max_distance_squared = max_distance * max_distance
	
	for block in blocks:
		if is_instance_valid(block):
			for point in block.get_available_connection_points():
				var point_global_pos = block.global_position + point.position.rotated(block.global_rotation)
				var distance_squared = point_global_pos.distance_squared_to(_position)
				
				if distance_squared <= max_distance_squared:
					temp_points.append(point)
	
	# 显式转换类型
	var available_points: Array[ConnectionPoint] = []
	for point in temp_points:
		if point is ConnectionPoint:
			available_points.append(point)
	
	return available_points


func open_vehicle_panel():
	if vehicle_panel:
		vehicle_panel.visible = true
		vehicle_panel.move_to_front()
	else:
		var HUD = get_tree().current_scene.find_child("CanvasLayer") as CanvasLayer
		var panel = load("res://ui/tankpanel.tscn").instantiate()
		panel.selected_vehicle = self
		vehicle_panel = panel
		HUD.add_child(panel)
		while panel.any_overlap():
			panel.position += Vector2(32, 32)
	
