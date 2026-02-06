class_name Vehicle
extends Node2D

signal cargo_changed()

const GRID_SIZE:int = 16

# 车辆基本属性
var vehicle_size:Vector2i
var vehicle_name:String
var move_state:String
var max_engine_power:float
var current_engine_power:float
var total_weight:int
var total_store:int
var blueprint:Variant
var blueprint_grid:= {}
var grid:= {} 
var blocks:= [] 
var total_blocks:= []  
var powerpacks:= []
var tracks:= []
var cargos:= []
var commands:= []
var vehicle_panel:Panel
var speed_of_increase = 0.05
var direction = Vector2(0, -1)
var track_forces:= {}  
var balanced_forces:= {} 
var rotation_forces:= {} 
var control:Callable
var controls:= []
var targets:= []
var is_assembled:= false
var block_scenes:= {}
var selected:bool
var destroyed:bool
var center_of_mass:Vector2 = Vector2(0,0)
var ready_connect = true

# 缓存优化
var cached_center_of_mass: Vector2
var cached_center_of_mass_dirty: bool = true
var targets_dirty: bool = true

# 承重系统相关
var total_mass: float = 0.0  # 车辆总质量
var track_load_distribution: Dictionary = {}  # 履带承重分布
var load_check_timer: float = 0.0  # 承重检查计时器

# ==================== 生命周期方法 ====================
func _ready():
	if blueprint:
		load_blueprint()
	else:
		initialize_empty_vehicle()

func _process(delta):
	handle_delayed_connections()
	
	if control:
		update_mobility_state(control.call(), delta)
	
	update_targets_if_needed()
	
	# 更新承重检查
	update_load_check(delta)

# ==================== 初始化方法 ====================
func load_blueprint():
	if blueprint is String:
		load_from_file(blueprint)
	elif blueprint is Dictionary:
		load_from_blueprint(blueprint)
	else:
		push_error("Invalid blueprint format")
	update_vehicle()

func initialize_empty_vehicle():
	vehicle_name = "Unnamed_Vehicle"
	blocks = []
	total_blocks = []
	grid = {}
	tracks = []
	powerpacks = []
	commands = []

# ==================== 块管理方法 ====================
func _add_block(block: Block, local_pos = null, grid_positions = null):
	if block not in blocks:
		blocks.append(block)
		total_blocks.append(block)
		block.global_grid_pos = get_rectangle_corners(grid_positions)
		
		if block is Track:
			tracks.append(block)
		elif block is Powerpack:
			powerpacks.append(block)
		elif block is Command:
			commands.append(block)
		elif block is Cargo:
			cargos.append(block)
			emit_signal("cargo_changed")
	
	if not local_pos == null and not grid_positions == null:
		if block.parent_vehicle == null:
			add_child(block)
			block.parent_vehicle = self
		block.position = local_pos
		
		# 安全等待块准备好
		if is_inside_tree() and get_tree() != null:
			if block.has_method("connect_aready"):
				await block.connect_aready()
		
		# 预计算块的连接点位置到方向的映射
		var connection_map = {}
		for point in block.connection_points:
			if point is Connector:
				var local_pos_key = point.location
				if not connection_map.has(local_pos_key):
					connection_map[local_pos_key] = []
				
				var total_rotation = point.rotation_degrees + block.base_rotation_degree
				var dir = block.get_direction_from_rotation(total_rotation)
				connection_map[local_pos_key].append(dir)
		
		# 计算方块的基准位置（最小网格位置）
		var min_x = grid_positions[0][0]
		var min_y = grid_positions[0][1]
		for pos_array in grid_positions:
			min_x = min(min_x, pos_array[0])
			min_y = min(min_y, pos_array[1])
		var actual_base_pos = Vector2i(min_x, min_y)
		
		# 更新block.base_pos（如果尚未设置）
		if block.base_pos == Vector2i.ZERO:
			block.base_pos = actual_base_pos

		# 预计算局部位置到全局位置的映射
		var local_to_global_map = {}
		for x in range(block.size.x):
			for y in range(block.size.y):
				var local_pos_key = Vector2i(x, y)
				var global_pos = calculate_global_grid_position(local_pos_key, block, actual_base_pos)
				local_to_global_map[local_pos_key] = global_pos

		# 构建反向映射：全局位置 -> 局部位置
		var global_to_local_map = {}
		for local_pos_key in local_to_global_map:
			var global_pos = local_to_global_map[local_pos_key]
			global_to_local_map[global_pos] = local_pos_key
		
		for pos_array in grid_positions:
			var global_grid_pos = Vector2i(pos_array[0], pos_array[1])
			var local_grid_pos = global_to_local_map.get(global_grid_pos, Vector2i(-1, -1))
			
			if local_grid_pos == Vector2i(-1, -1):
				continue
			
			# 创建连接状态数组 [右, 下, 左, 上]
			var connections = [false, false, false, false]
			
			# 获取该局部位置的所有连接点
			var connectors_at_position = []
			for point in block.connection_points:
				if point is Connector and point.location == local_grid_pos:
					connectors_at_position.append(point)
			
			# 标记连接方向
			for connector in connectors_at_position:
				var total_rotation = connector.rotation_degrees + block.base_rotation_degree
				var dir = block.get_direction_from_rotation(total_rotation)
				
				if dir >= 0 and dir < connections.size():
					if connector.connected_to != null:
						connections[dir] = false
					else:
						connections[dir] = true
			
			# 使用新的grid数据结构
			grid[global_grid_pos] = {
				"block": block,
				"connections": connections
			}
		
		block.set_connection_enabled(true)
	
	cached_center_of_mass_dirty = true
	targets_dirty = true
	update_vehicle()

func remove_block(block: Block, imd: bool = false, _disconnected:bool = false):
	blocks.erase(block)
	if imd:
		if block is TurretRing:
			for turret_block in block.turret_basket.get_children():
				if turret_block is Block:
					block.remove_block_from_turret(turret_block)
				else:
					turret_block.queue_free()
		total_blocks.erase(block)
		block.queue_free()
	
	# 修改：遍历grid查找要删除的块
	var keys_to_erase = []
	for pos in grid:
		if grid[pos]["block"] == block:
			keys_to_erase.append(pos)
	for pos in keys_to_erase:
		grid.erase(pos)
	
	if block in tracks:
		tracks.erase(block)
	if block in powerpacks:
		powerpacks.erase(block)
	if block in commands:
		commands.erase(block)
	if block in cargos:
		cargos.erase(block)
		emit_signal("cargo_changed")
	
	cached_center_of_mass_dirty = true
	targets_dirty = true
	update_vehicle()

func calculate_global_grid_position(local_pos: Vector2i, block: Block, base_pos: Vector2i) -> Vector2i:
	# 根据方块的旋转角度进行变换
	var rotation_deg = int(block.base_rotation_degree)
	
	# 处理负角度
	if rotation_deg < 0:
		rotation_deg = 360 + rotation_deg
	
	match rotation_deg:
		0:
			return base_pos + local_pos
		90:
			return base_pos + Vector2i(-local_pos.y, local_pos.x)
		180:
			return base_pos + Vector2i(-local_pos.x, -local_pos.y)
		270:
			return base_pos + Vector2i(local_pos.y, -local_pos.x)
		_:
			return base_pos + local_pos

# ==================== 车辆加载方法 ====================
func load_from_file(identifier):
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
	
	var _name = bp["name"]
	vehicle_name = _name
	vehicle_size = Vector2i(bp["vehicle_size"][0], bp["vehicle_size"][1])
	
	# 按数字键排序以保证加载顺序一致
	var block_ids = bp["blocks"].keys()
	block_ids.sort_custom(func(a, b):
		var pos_a = Vector2i(bp["blocks"][a]["base_pos"][0], bp["blocks"][a]["base_pos"][1])
		var pos_b = Vector2i(bp["blocks"][b]["base_pos"][0], bp["blocks"][b]["base_pos"][1])
		if pos_a.x != pos_b.x:
			return pos_a.x < pos_b.x
		return pos_a.y < pos_b.y
	)
	
	# 第一遍：加载所有主块（包括炮塔座圈）
	var loaded_blocks = {}
	for block_id in block_ids:
		var block_data = bp["blocks"][block_id]
		# 使用VehicleManager获取路径
		var block_path = VehicleManager.get_block_scene_path_by_name(block_data["name"])
		var block_scene = load(block_path)
		
		if block_scene:
			var block:Block = block_scene.instantiate()
			var base_pos = Vector2(block_data["base_pos"][0], block_data["base_pos"][1])
			block.rotation = deg_to_rad(block_data["rotation"][0])
			block.base_rotation_degree = block_data["rotation"][0]
			
			# 设置血量
			block.current_hp = block_data.get("current_hp", block.max_hp)
			block.max_hp = block_data.get("max_hp", block.max_hp)
			
			var target_grid = calculate_block_grid_positions(block, base_pos)
			var local_pos = get_rectangle_corners(target_grid)
			
			await _add_block(block, local_pos, target_grid)
			loaded_blocks[block_id] = block
	
	# 第二遍：加载炮塔上的块
	for block_id in block_ids:
		var block_data = bp["blocks"][block_id]
		if block_data.has("turret_grid"):
			var turret_block = loaded_blocks[block_id]
			if turret_block is TurretRing:
				await turret_block.lock_turret_rotation()
				for point in turret_block.turret_basket.get_children():
					if point is TurretConnector and point.connected_to == null:
						point.is_connection_enabled = true
				
				await load_turret_blocks(turret_block, block_data["turret_grid"], loaded_blocks)
				turret_block.unlock_turret_rotation()
	
	# 应用车辆旋转
	if bp.has("rotation") and bp["rotation"].size() > 0:
		var vehicle_rotation = bp["rotation"][0]
		apply_saved_rotation(vehicle_rotation)
	
	update_vehicle()

func calculate_block_grid_positions(block: Block, base_pos: Vector2) -> Array:
	var target_grid = []
	
	# 根据块的旋转计算网格位置
	for x in range(block.size.x):
		for y in range(block.size.y):
			var grid_pos: Vector2i
			var rotation_deg = int(block.base_rotation_degree)
			
			# 标准化旋转角度
			rotation_deg = int(fmod(rotation_deg, 360))
			if rotation_deg < 0:
				rotation_deg += 360
			
			# 根据旋转计算实际位置
			match rotation_deg:
				0:
					grid_pos = Vector2i(base_pos) + Vector2i(x, y)
				90:
					grid_pos = Vector2i(base_pos) + Vector2i(-y, x)
				180:
					grid_pos = Vector2i(base_pos) + Vector2i(-x, -y)
				270:
					grid_pos = Vector2i(base_pos) + Vector2i(y, -x)
				_:
					# 非90度倍数的旋转，使用近似
					var rotated_x = round(x * cos(deg_to_rad(rotation_deg)) - y * sin(deg_to_rad(rotation_deg)))
					var rotated_y = round(x * sin(deg_to_rad(rotation_deg)) + y * cos(deg_to_rad(rotation_deg)))
					grid_pos = Vector2i(base_pos) + Vector2i(rotated_x, rotated_y)
			
			target_grid.append(grid_pos)
	
	return target_grid

func load_turret_blocks(turret: TurretRing, turret_grid_data: Dictionary, loaded_blocks: Dictionary):
	if not turret_grid_data.has("blocks"):
		return
	
	for block_id in turret_grid_data["blocks"]:
		var block_data = turret_grid_data["blocks"][block_id]
		# 使用VehicleManager获取路径
		var block_path = VehicleManager.get_block_scene_path_by_name(block_data["name"])
		var block_scene = load(block_path)
		
		if block_scene:
			var block:Block = block_scene.instantiate()
			var local_base_pos = Vector2i(block_data["base_pos"][0], block_data["base_pos"][1])
			block.base_rotation_degree = block_data["rotation"][0]
			block.collision_layer = 2
			block.collision_mask = 2
			
			# 设置血量
			block.current_hp = block_data.get("current_hp", block.max_hp)
			block.max_hp = block_data.get("max_hp", block.max_hp)
			
			var turret_local_positions = calculate_block_grid_positions(block, local_base_pos)
			var turretblock_pos = get_rectangle_corners(turret_local_positions) - 0.5 * turret.size * GRID_SIZE
			
			var world_pos = turret.to_global(turretblock_pos)
			block.global_position = world_pos
			turret.add_block_to_turret(block, turret_local_positions)
			block.rotation_degrees = block.base_rotation_degree
			
			if block not in total_blocks:
				total_blocks.append(block)
			await block.connect_aready()
	
	update_vehicle()

func clear_existing_blocks():
	for block in blocks:
		block.queue_free()
	blocks.clear()
	grid.clear()
	tracks.clear()
	powerpacks.clear()

# ==================== 车辆物理计算方法 ====================
func get_max_engine_power() -> float:
	var max_power := 0.0
	for engine in powerpacks:
		if engine.is_inside_tree() and is_instance_valid(engine):
			max_power += engine.max_power
	return max_power

func get_current_engine_power() -> float:
	var current_power := 0.0
	for engine in powerpacks:
		if engine.is_inside_tree() and is_instance_valid(engine):
			current_power += engine.power
	current_engine_power = current_power
	return current_power

func calculate_center_of_mass() -> Vector2:
	if not cached_center_of_mass_dirty:
		return cached_center_of_mass
	
	var total_mass := 0.0
	var weighted_sum := Vector2.ZERO
	var has_calculated := {}
	
	for grid_pos in grid:
		if grid[grid_pos] != null:
			var body: Block = grid[grid_pos]["block"]
			if blocks.has(body):
				if has_calculated.get(body.get_instance_id(), false):
					continue
				
				var rid = get_block_grid(body)
				var geometric_center: Vector2 = get_rectangle_corners(rid)
				
				# 使用块的实际重心（考虑偏移）
				var actual_com: Vector2 = body.get_actual_center_of_mass(geometric_center)
				
				# 使用块的实际质量
				var mass = body.mass
				
				weighted_sum += actual_com * mass
				total_mass += mass
				has_calculated[body.get_instance_id()] = true
	
	# 还要考虑炮塔上的块
	for block in blocks:
		if not blocks.has(block) and block is Block and block.functioning:
			if has_calculated.get(block.get_instance_id(), false):
				continue
			var actual_com = Vector2.ZERO
			# 对于炮塔上的块，需要获取其在车辆坐标系中的位置
			if block.on_turret:
				var turret_pos = block.on_turret.global_position - global_position
				var block_local_pos = block.position - block.on_turret.position
				actual_com = turret_pos + block_local_pos
				
				# 考虑块的旋转和偏移
				var rotation_rad = deg_to_rad(block.base_rotation_degree)
				var rotated_offset = block.center_of_mass_offset.rotated(rotation_rad)
				actual_com += rotated_offset
			
			var mass = block.get_actual_mass()
			weighted_sum += actual_com * mass
			total_mass += mass
			has_calculated[block.get_instance_id()] = true
	
	cached_center_of_mass = weighted_sum / total_mass if total_mass > 0 else Vector2.ZERO
	cached_center_of_mass_dirty = false
	return cached_center_of_mass

func calculate_balanced_forces():
	var com = calculate_center_of_mass()
	var active_tracks = tracks
	
	var thrust_points = []
	for track:Track in active_tracks:
		if track.functioning and track.parent_vehicle == self:
			var dir = Vector2.UP.rotated(deg_to_rad(track.base_rotation_degree))
			var positions_grid = get_block_grid(track)
			thrust_points.append({
				"position": get_rectangle_corners(positions_grid),
				"direction": dir,
				"track": track
			})
	
	var thrusts = calculate_thrust_distribution(
		thrust_points,
		com, 
		1,
		direction
	)
	
	balanced_forces = thrusts
	return balanced_forces

func calculate_thrust_distribution(thrust_points: Array, com: Vector2, total_thrust: float, target_dir: Vector2) -> Dictionary:
	var num_points = thrust_points.size()
	if num_points == 0:
		return {}
	
	var A = []
	var b = []
	
	# 合力方程
	var eq_force_x = []
	var eq_force_y = []
	for point in thrust_points:
		eq_force_x.append(point.direction.x)
		eq_force_y.append(point.direction.y)
	A.append(eq_force_x)
	b.append(total_thrust * target_dir.x)
	A.append(eq_force_y)
	b.append(total_thrust * target_dir.y)
	
	# 扭矩平衡方程
	var eq_torque = []
	for point in thrust_points:
		var r = point.position - com
		var torque_coeff = r.x * point.direction.y - r.y * point.direction.x
		eq_torque.append(torque_coeff)
	A.append(eq_torque)
	b.append(0.0)
	
	# 最小能量约束
	for i in range(num_points):
		var eq_energy = []
		eq_energy.resize(num_points)
		for j in range(num_points):
			eq_energy[j] = 0.0
		eq_energy[i] = 1.0
		A.append(eq_energy)
		b.append(0.0)
	
	var x = least_squares_solve(A, b)
	
	var results = {}
	var total = 0.0
	for i in range(num_points):
		var thrust = x[i]
		results[thrust_points[i].track] = thrust
		total += abs(thrust)
	
	if total > 0:
		var current_scale = total_thrust / total
		for track in results:
			results[track] *= current_scale
	
	return results

func calculate_rotation_forces():
	var com = calculate_center_of_mass()
	var active_tracks = tracks
	
	var thrust_points = []
	for track:Track in active_tracks:
		if track.functioning and track.parent_vehicle == self:
			var dir = Vector2.UP.rotated(deg_to_rad(track.base_rotation_degree))
			var positions_grid = get_block_grid(track)
			thrust_points.append({
				"position": get_rectangle_corners(positions_grid),
				"direction": dir,
				"track": track
			})
	
	var thrusts = calculate_rotation_thrust_distribution(thrust_points, com, 1)
	
	for point in thrust_points:
		if direction.y > 0:
			rotation_forces[point.track] = -thrusts[point.track]
		else:
			rotation_forces[point.track] = thrusts[point.track]
	return rotation_forces

func calculate_rotation_thrust_distribution(thrust_points: Array, com: Vector2, total_thrust: float) -> Dictionary:
	var num_points = thrust_points.size()
	if num_points == 0:
		return {}
	
	var A = []
	var b = []
	
	# 扭矩平衡方程
	var eq_torque = []
	for point in thrust_points:
		var r = point.position - com
		var torque_coeff = r.x * point.direction.y - r.y * point.direction.x
		eq_torque.append(torque_coeff)
	A.append(eq_torque)
	b.append(total_thrust)
	
	# 合力平衡方程
	var eq_force_x = []
	var eq_force_y = []
	for point in thrust_points:
		eq_force_x.append(point.direction.x)
		eq_force_y.append(point.direction.y)
	A.append(eq_force_x)
	b.append(0.0)
	A.append(eq_force_y)
	b.append(0.0)
	
	# 最小能量约束
	for i in range(num_points):
		var eq_energy = []
		eq_energy.resize(num_points)
		for j in range(num_points):
			eq_energy[j] = 0.0
		eq_energy[i] = 1.0
		A.append(eq_energy)
		b.append(0.0)
	
	var x = least_squares_solve(A, b)
	
	var results = {}
	var total = 0.0
	for i in range(num_points):
		results[thrust_points[i].track] = x[i]
		total += abs(x[i])
	
	if total > 0:
		var current_scale = total_thrust / total
		for track in results:
			results[track] *= current_scale
	
	return results

func least_squares_solve(A: Array, b: Array) -> Array:
	var At = transpose(A)
	var AtA = multiply(At, A)
	
	var lambda = 0.01
	var n = AtA.size()
	for i in range(n):
		AtA[i][i] += lambda
	
	var Atb = multiply_vector(At, b)
	return solve(AtA, Atb)

func transpose(m: Array) -> Array:
	var result = []
	for j in range(m[0].size()):
		result.append([])
		for i in range(m.size()):
			result[j].append(m[i][j])
	return result

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
	
	var A_copy = []
	var b_copy = []
	for i in range(n):
		A_copy.append(A[i].duplicate())
		b_copy.append(b[i])
	
	for i in range(n):
		var max_row = i
		var max_val = abs(A_copy[i][i])
		for k in range(i+1, n):
			if abs(A_copy[k][i]) > max_val:
				max_val = abs(A_copy[k][i])
				max_row = k
		
		if abs(A_copy[max_row][i]) < 1e-10:
			return array_zero(n)
		
		if max_row != i:
			var tmp_row = A_copy[i]
			A_copy[i] = A_copy[max_row]
			A_copy[max_row] = tmp_row
			
			var tmp_b = b_copy[i]
			b_copy[i] = b_copy[max_row]
			b_copy[max_row] = tmp_b
		
		var pivot = A_copy[i][i]
		for k in range(i+1, n):
			var factor = A_copy[k][i] / pivot
			for j in range(i, n):
				A_copy[k][j] -= factor * A_copy[i][j]
			b_copy[k] -= factor * b_copy[i]
	
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

# ==================== 移动控制方法 ====================
func update_mobility_state(control_input:Array, delta):
	var forward_input = control_input[0]
	var turn_input = control_input[1]
	
	if forward_input == 0 and turn_input == 0:
		move_state = 'idle'
	else:
		move_state = 'move'
	
	track_forces = calculate_track_forces(forward_input, turn_input)
	for track in tracks:
		var force = track_forces[track]
		var track_status = track.get_load_status()
		if track_status["functioning"]:
			if force != 0:
				track.set_state_force(move_state, force)
			else:
				track.set_state_force('idle', 0)
		else:
			track.set_state_force('idle', 0)

func calculate_track_forces(forward_input:int, turn_input:int) -> Dictionary:
	var track_forces:Dictionary = {}
	var total_power = get_current_engine_power()
	for track in tracks:
		var forward_power_ratio = 0.0
		var rotate_power_ratio = 0.0
		if (forward_input != 0) and (turn_input != 0):
			forward_power_ratio = 0.5
			rotate_power_ratio = 0.5
		elif forward_input != 0:
			forward_power_ratio = 1.0
		elif turn_input != 0:
			rotate_power_ratio = 1
		
		var move_component = balanced_forces[track] * total_power * forward_power_ratio * forward_input
		var rotate_component = rotation_forces[track] * total_power * rotate_power_ratio * turn_input
		track_forces[track] = move_component + rotate_component
	return track_forces

# ==================== 承重系统方法 ====================
func update_load_check(delta: float):
	load_check_timer += delta
	
	if load_check_timer >= 0.5:
		calculate_track_load_distribution()
		load_check_timer = 0.0
		check_track_overload_status()

func calculate_track_load_distribution():
	total_mass = 0.0
	for block in blocks:
		if block is Block and block.functioning:
			total_mass += block.mass
	
	if tracks.is_empty() or total_mass <= 0:
		return
	
	var average_load = total_mass / tracks.size()
	
	for track in tracks:
		if track is Track and track.functioning:
			track.set_current_load(average_load)
			track_load_distribution[track] = average_load

func check_track_overload_status():
	var any_track_overloaded = false
	
	for track in tracks:
		if track is Track:
			var status = track.get_load_status()
			if status["overloaded"]:
				any_track_overloaded = true
	
	if any_track_overloaded:
		calculate_balanced_forces()
		calculate_rotation_forces()

# ==================== 内部辅助方法 ====================
func handle_delayed_connections():
	if not ready_connect:
		for block:Block in blocks:
			if block.joint_connected_blocks.size() != 0:
				block.set_connection_enabled(false)
		ready_connect = true

func update_targets_if_needed():
	if targets_dirty:
		var current_targets = []
		for block in commands:
			current_targets += block.targets
		targets = current_targets
		targets_dirty = false

func update_vehicle():
	# 检查块连接性
	for block:Block in blocks:
		block.get_all_connected_blocks()
	
	# 获取所有总参数
	get_max_engine_power()
	get_current_engine_power()
	update_vehicle_size()
	
	# 重新计算物理属性
	calculate_center_of_mass()
	calculate_balanced_forces()
	calculate_rotation_forces()
	
	calculate_track_load_distribution()
	
	# 重新获取控制方法
	if not check_control(control.get_method()):
		if not check_control("AI_control"):
			if not check_control("remote_control"):
				control = Callable()
			else: control = check_control("remote_control")
		else: control = check_control("AI_control")
	
	# 检查车辆是否被摧毁
	var has_command:= false
	for blk in commands:
		if blk.functioning:
			has_command = true
	destroyed = not has_command

func check_control(control_name:String):
	if control_name.is_empty():
		return true
	for block in commands:
		if block.has_method(control_name) and block.functioning:
			return Callable(block, control_name)
	return false

func update_vehicle_size():
	if grid.is_empty():
		vehicle_size = Vector2i.ZERO
		return
	
	var min_x = grid.keys()[0].x
	var min_y = grid.keys()[0].y
	var max_x = min_x
	var max_y = min_y
	
	for grid_pos in grid:
		min_x = min(min_x, grid_pos.x)
		min_y = min(min_y, grid_pos.y)
		max_x = max(max_x, grid_pos.x)
		max_y = max(max_y, grid_pos.y)
	
	vehicle_size = Vector2i(max_x - min_x + 1, max_y - min_y + 1)

func get_rectangle_corners(grid_data):
	if grid_data.is_empty():
		return Vector2.ZERO
	
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
	
	return (vc_1 + vc_2) / 2

func get_block_grid(block:Block) -> Array:
	var positions:Array
	for pos in grid:
		if grid[pos]["block"] == block and not positions.has(pos):
			positions.append(pos)
	return positions

func get_block_at_grid_position(pos: Vector2i) -> Block:
	if grid.has(pos):
		return grid[pos]["block"]
	return null

func get_connections_at_grid_position(pos: Vector2i) -> Array[bool]:
	if grid.has(pos):
		return grid[pos]["connections"]
	return [false, false, false, false]

func apply_saved_rotation(saved_rotation_degrees: float) -> void:
	if grid.is_empty():
		return
	
	# 获取第一个块作为旋转参考
	var first_grid_pos = grid.keys()[0]
	var first_block_data = grid[first_grid_pos]
	var first_block = first_block_data["block"]
	
	if not is_instance_valid(first_block):
		return
	
	# 计算第一个块应该具有的全局旋转
	var first_block_base_rotation = first_block.base_rotation_degree
	var target_global_rotation_degrees = first_block_base_rotation + saved_rotation_degrees
	
	# 计算需要应用的旋转差值
	var rotation_difference = target_global_rotation_degrees - first_block.global_rotation_degrees
	
	# 应用旋转到整个车辆
	rotation_degrees += rotation_difference
	
	# 确保旋转在 0-360 度范围内
	rotation_degrees = fmod(rotation_degrees, 360)
	if rotation_degrees < 0:
		rotation_degrees += 360

# ==================== 保存和加载方法 ====================
func get_save_data() -> Dictionary:
	if destroyed:
		return {}
	
	# 计算车辆的基准点：不考虑旋转的原始网格坐标系原点
	var reference_point = Vector2i.ZERO
	if not grid.is_empty():
		var min_x = INF
		var min_y = INF
		for grid_pos in grid.keys():
			min_x = min(min_x, grid_pos.x)
			min_y = min(min_y, grid_pos.y)
		reference_point = Vector2i(min_x, min_y)
	
	var save_data := {
		"name": vehicle_name,
		"position": [global_position.x, global_position.y],
		"reference_point": [reference_point.x, reference_point.y],
		"vehicle_size": [vehicle_size.x, vehicle_size.y],
		"global_rotation": [rotation_degrees],  # 车辆全局旋转
		"blocks": {}
	}
	
	var block_counter = 1
	for block in blocks:
		if not is_instance_valid(block):
			continue
		
		var block_data = get_block_save_data(block, reference_point)
		if block_data:
			save_data["blocks"][str(block_counter)] = block_data
			block_counter += 1
	
	return save_data

func get_save_rotation() -> float:
	if grid.is_empty():
		return 0.0
	
	var first_grid_pos = grid.keys()[0]
	var first_block_data = grid[first_grid_pos]
	var first_block = first_block_data["block"]
	
	if not is_instance_valid(first_block):
		return 0.0
	
	var relative_rotation = rad_to_deg(first_block.global_rotation) - first_block.base_rotation_degree
	return fmod(relative_rotation + 360, 360)

func get_block_save_data(block: Block, reference_point: Vector2i) -> Dictionary:
	var grid_positions = get_block_grid(block)
	if grid_positions.is_empty():
		return {}
	
	# 计算块相对于基准点的局部网格坐标
	var min_x = INF
	var min_y = INF
	for pos in grid_positions:
		min_x = min(min_x, pos.x)
		min_y = min(min_y, pos.y)
	
	var local_grid_pos = Vector2i(min_x - reference_point.x, min_y - reference_point.y)
	
	# 使用VehicleManager获取块的路径
	var block_path = VehicleManager.get_block_scene_path_by_name(block.block_name)
	
	var block_data = {
		"local_grid_pos": [local_grid_pos.x, local_grid_pos.y],
		"name": block.block_name,
		"path": block_path,
		"base_rotation": [block.base_rotation_degree],  # 块的局部旋转
		"current_hp": block.current_hp,
		"max_hp": block.max_hp
	}
	
	if block is TurretRing:
		var turret_grid = get_turret_save_data(block)
		if turret_grid:
			block_data["turret_grid"] = turret_grid
	
	return block_data

func get_turret_save_data(turret_ring: TurretRing) -> Dictionary:
	if not is_instance_valid(turret_ring.turret_basket):
		return {"blocks": {}}
	
	var turret_grid = {"blocks": {}}
	
	# 直接遍历所有块，找到属于这个炮塔的块
	var turret_blocks = []
	for block in total_blocks:
		if block != turret_ring and block.on_turret == turret_ring:
			turret_blocks.append(block)
	
	if turret_blocks.is_empty():
		return {"blocks": {}}
	
	var min_x = INF
	var min_y = INF
	var max_x = -INF
	var max_y = -INF
	var block_counter = 1
	
	for block in turret_blocks:
		if not is_instance_valid(block):
			continue
		
		# 计算块相对于炮塔的局部坐标（以网格为单位）
		var local_pos = block.position - turret_ring.position
		var grid_x = int(round(local_pos.x / GRID_SIZE))
		var grid_y = int(round(local_pos.y / GRID_SIZE))
		
		min_x = min(min_x, grid_x)
		min_y = min(min_y, grid_y)
		max_x = max(max_x, grid_x)
		max_y = max(max_y, grid_y)
		
		# 使用VehicleManager获取块的路径
		var block_path = VehicleManager.get_block_scene_path_by_name(block.block_name)
		
		turret_grid["blocks"][str(block_counter)] = {
			"base_pos": [grid_x, grid_y],
			"name": block.block_name,
			"path": block_path,
			"rotation": [block.base_rotation_degree],
			"current_hp": block.current_hp,
			"max_hp": block.max_hp
		}
		
		block_counter += 1
	
	if min_x != INF and max_x != -INF:
		var width = int(max_x - min_x + 1)
		var height = int(max_y - min_y + 1)
		turret_grid["grid_size"] = [width, height]
		
		# 归一化坐标，使最小坐标为(0,0)
		if min_x != 0 or min_y != 0:
			for block_id in turret_grid["blocks"]:
				var block_data = turret_grid["blocks"][block_id]
				var pos = block_data["base_pos"]
				block_data["base_pos"] = [pos[0] - min_x, pos[1] - min_y]
	
	return turret_grid

func load_from_save_data(save_data: Dictionary) -> void:
	ready_connect = false
	clear_existing_blocks()
	
	vehicle_name = save_data.get("name", "Unnamed_Vehicle")
	
	if save_data.has("vehicle_size"):
		vehicle_size = Vector2i(save_data["vehicle_size"][0], save_data["vehicle_size"][1])
	
	# 获取基准点
	var reference_point = Vector2i.ZERO
	if save_data.has("reference_point"):
		reference_point = Vector2i(save_data["reference_point"][0], save_data["reference_point"][1])
	
	# 获取车辆全局旋转
	var global_rotation = 0.0
	if save_data.has("global_rotation") and save_data["global_rotation"].size() > 0:
		global_rotation = save_data["global_rotation"][0]
	
	# 获取块数据
	var blocks_data = save_data.get("blocks", {})
	var loaded_blocks = {}
	
	# 按位置排序以确保正确的加载顺序
	var block_ids = blocks_data.keys()
	block_ids.sort_custom(func(a, b):
		var pos_a = blocks_data[a].get("local_grid_pos", [0, 0])
		var pos_b = blocks_data[b].get("local_grid_pos", [0, 0])
		if pos_a[0] != pos_b[0]:
			return pos_a[0] < pos_b[0]
		return pos_a[1] < pos_b[1]
	)
	
	# 第一遍：加载所有主块（包括炮塔座圈）
	for block_id in block_ids:
		var block_data = blocks_data[block_id]
		await load_block_from_save_data(block_data, loaded_blocks, block_id, reference_point)
	
	# 第二遍：处理炮塔上的块
	for block_id in block_ids:
		var block_data = blocks_data[block_id]
		if block_data.has("turret_grid") and loaded_blocks.has(block_id):
			var turret_block = loaded_blocks[block_id]
			if turret_block is TurretRing:
				await turret_block.lock_turret_rotation()
				for point in turret_block.turret_basket.get_children():
					if point is TurretConnector and point.connected_to == null:
						point.is_connection_enabled = true
				
				await load_turret_blocks_from_save_data(turret_block, block_data["turret_grid"])
				turret_block.unlock_turret_rotation()
	
	# 应用车辆全局旋转
	rotation_degrees = global_rotation
	
	ready_connect = true
	update_vehicle()

func load_block_from_save_data(block_data: Dictionary, loaded_blocks: Dictionary, block_id: String, reference_point: Vector2i) -> void:
	var block_name = block_data.get("name", "")
	if block_name.is_empty():
		return
	
	# 优先使用保存的路径（如果存在）
	var block_path = block_data.get("path", "")
	if block_path.is_empty():
		# 通过VehicleManager获取路径
		block_path = VehicleManager.get_block_scene_path_by_name(block_name)
	
	var block_scene = load(block_path)
	
	if not block_scene:
		print("错误: 无法加载块场景: ", block_path)
		return
	
	var block: Block = block_scene.instantiate()
	
	# 获取块的局部基点和旋转
	var local_grid_pos = Vector2i(block_data["local_grid_pos"][0], block_data["local_grid_pos"][1])
	var base_rotation = block_data["base_rotation"][0]
	
	# 设置块的属性
	block.base_rotation_degree = base_rotation
	block.rotation = deg_to_rad(base_rotation)
	
	# 设置血量
	block.current_hp = block_data.get("current_hp", block.max_hp)
	block.max_hp = block_data.get("max_hp", block.max_hp)
	
	# 计算全局网格位置
	var global_base_pos = Vector2(local_grid_pos.x + reference_point.x, local_grid_pos.y + reference_point.y)
	
	# 计算旋转后的网格位置
	var target_grid = calculate_block_grid_positions(block, global_base_pos)
	var local_pos = get_rectangle_corners(target_grid)
	
	await _add_block(block, local_pos, target_grid)
	loaded_blocks[block_id] = block

func load_turret_blocks_from_save_data(turret_ring: TurretRing, turret_grid_data: Dictionary) -> void:
	if not turret_grid_data.has("blocks"):
		return
	
	for block_id in turret_grid_data["blocks"]:
		var block_data = turret_grid_data["blocks"][block_id]
		var block_name = block_data.get("name", "")
		
		if block_name.is_empty():
			continue
		
		# 通过VehicleManager的静态方法获取路径
		var block_path = VehicleManager.get_block_scene_path_by_name(block_name)
		var block_scene = load(block_path)
		
		if not block_scene:
			continue
		
		var block: Block = block_scene.instantiate()
		var local_base_pos = Vector2i(block_data["base_pos"][0], block_data["base_pos"][1])
		block.base_rotation_degree = block_data["rotation"][0]
		block.current_hp = block_data.get("current_hp", block.max_hp)
		block.max_hp = block_data.get("max_hp", block.max_hp)
		block.collision_layer = 2
		block.collision_mask = 2
		
		var turret_local_positions = calculate_block_grid_positions(block, local_base_pos)
		var turretblock_pos = get_rectangle_corners(turret_local_positions) - 0.5 * turret_ring.size * GRID_SIZE
		
		var world_pos = turret_ring.to_global(turretblock_pos)
		block.global_position = world_pos
		turret_ring.add_block_to_turret(block, turret_local_positions)
		block.rotation_degrees = block.base_rotation_degree
		
		if block not in total_blocks:
			total_blocks.append(block)
		#await block.connect_aready()

# ==================== 其他公共方法 ====================
func get_available_points_near_position(_position: Vector2, max_distance: float = 30.0) -> Array[Connector]:
	var temp_points = []
	var max_distance_squared = max_distance * max_distance
	
	for block in blocks:
		if is_instance_valid(block):
			for point in block.get_available_connection_points():
				var point_global_pos = block.global_position + point.position.rotated(block.global_rotation)
				var distance_squared = point_global_pos.distance_squared_to(_position)
				
				if distance_squared <= max_distance_squared:
					temp_points.append(point)
	
	var available_points: Array[Connector] = []
	for point in temp_points:
		if point is Connector:
			available_points.append(point)
	
	return available_points

func open_vehicle_panel():
	if vehicle_panel:
		vehicle_panel.visible = true
		vehicle_panel.move_to_front()
	else:
		var UI = get_tree().current_scene.find_child("CanvasLayer") as CanvasLayer
		var panel = load("res://ui/tankpanel.tscn").instantiate()
		panel.selected_vehicle = self
		vehicle_panel = panel
		UI.add_child(panel)
		while panel.any_overlap():
			panel.position += Vector2(32, 32)

func check_and_regroup_disconnected_blocks():
	var valid_blocks = []
	for block in blocks:
		if is_instance_valid(block) and block.get_parent() == self:
			valid_blocks.append(block)
	if valid_blocks.is_empty():
		return false
	
	var components = find_connected_components_dfs(valid_blocks)
	return components.size() > 1

func find_connected_components_dfs(all_blocks: Array) -> Array:
	var visited = {}
	var components = []
	
	for block in all_blocks:
		if block.collision_layer != 1:
			continue
		
		var block_id = block.get_instance_id()
		if not visited.get(block_id, false):
			var component = []
			dfs_traverse(block, visited, component, all_blocks)
			components.append(component)
	
	return components

func dfs_traverse(block, visited: Dictionary, component: Array, all_blocks: Array):
	var block_id = block.get_instance_id()
	visited[block_id] = true
	component.append(block)
	
	for connected_block in block.joint_connected_blocks:
		if is_instance_valid(connected_block) and connected_block.get_parent() == self:
			var connected_id = connected_block.get_instance_id()
			if not visited.get(connected_id, false):
				dfs_traverse(connected_block, visited, component, all_blocks)
	
	for connection_point in block.connection_points:
		if connection_point.connected_to and is_instance_valid(connection_point.connected_to):
			var connected_block = connection_point.connected_to.find_parent_block()
			if connected_block and connected_block.get_parent() == self:
				var connected_id = connected_block.get_instance_id()
				if not visited.get(connected_id, false):
					dfs_traverse(connected_block, visited, component, all_blocks)
