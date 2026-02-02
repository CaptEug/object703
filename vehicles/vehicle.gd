class_name Vehicle
extends Node2D

signal cargo_changed()

const GRID_SIZE:int = 16

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
var track_forces:= {}  # 存储每个履带的目标力
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

# 缓存优化
var cached_center_of_mass: Vector2
var cached_center_of_mass_dirty: bool = true
var targets_dirty: bool = true

# 承重系统相关
var total_mass: float = 0.0  # 车辆总质量
var track_load_distribution: Dictionary = {}  # 履带承重分布
var load_check_timer: float = 0.0  # 承重检查计时器

func _ready():
	if blueprint:
		load_blueprint()
	else:
		initialize_empty_vehicle()

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

func _process(delta):
	handle_delayed_connections()
	
	if control:
		update_mobility_state(control.call(), delta)
	
	update_targets_if_needed()
	
	# 更新承重检查
	update_load_check(delta)

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
	#Check block connectivity
	for block:Block in blocks:
		block.get_all_connected_blocks()
	
	#Get all total parameters
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
	
	#check vehicle destroyed
	var has_command:= false
	for blk in commands:
		if blk.functioning:
			has_command = true
	destroyed = not has_command

###################### BLOCK MANAGEMENT ######################

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
		await block.connect_aready()
		
		# 预计算块的连接点位置到方向的映射
		var connection_map = {}
		for point in block.connection_points:
			if point is Connector:
				var local_pos_key = point.location
				if not connection_map.has(local_pos_key):
					connection_map[local_pos_key] = []
				
				var total_rotation = point.global_rotation_degrees + block.base_rotation_degree
				var dir = block.get_direction_from_rotation(total_rotation)
				connection_map[local_pos_key].append(dir)
		
		for pos in grid_positions:
			# 计算局部网格位置
			var local_grid_pos = pos - block.base_pos
			
			# 获取该位置的连接方向列表
			var dir_list = connection_map.get(local_grid_pos, [])
			
			# 创建连接状态数组
			var connections = [false, false, false, false]
			for dir in dir_list:
				if dir >= 0 and dir < connections.size():
					connections[dir] = true
			
			grid[pos] = {
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

func has_block(block_name:String):
	for block in blocks:
		if block.block_name == block_name:
			return block
	return null

##################### VEHICLE PARAMETER MANAGEMENT #####################

func check_control(control_name:String):
	if control_name.is_empty():
		return true
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
	var current_power := 0.0
	for engine in powerpacks:
		if engine.is_inside_tree() and is_instance_valid(engine):
			current_power += engine.power
	current_engine_power = current_power
	return current_power

########################## VEHICLE LOADING ###########################

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
		var block_scene = load(block_data["path"])
		
		if block_scene:
			var block:Block = block_scene.instantiate()
			var base_pos = Vector2(block_data["base_pos"][0], block_data["base_pos"][1])
			block.rotation = deg_to_rad(block_data["rotation"][0])
			block.base_rotation_degree = block_data["rotation"][0]
			
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

func calculate_block_grid_positions(block: Block, base_pos: Vector2) -> Array:
	var target_grid = []
	for x in block.size.x:
		for y in block.size.y:
			var grid_pos: Vector2i
			match int(block.base_rotation_degree):
				0:
					grid_pos = Vector2i(base_pos) + Vector2i(x, y)
				90:
					grid_pos = Vector2i(base_pos) + Vector2i(-y, x)
				-90:
					grid_pos = Vector2i(base_pos) + Vector2i(y, -x)
				180, -180:
					grid_pos = Vector2i(base_pos) + Vector2i(-x, -y)
				_:
					grid_pos = Vector2i(base_pos) + Vector2i(x, y)
			target_grid.append(grid_pos)
	return target_grid

func load_turret_blocks(turret: TurretRing, turret_grid_data: Dictionary, loaded_blocks: Dictionary):
	if not turret_grid_data.has("blocks"):
		return
	
	for block_id in turret_grid_data["blocks"]:
		var block_data = turret_grid_data["blocks"][block_id]
		var block_scene = load(block_data["path"])
		
		if block_scene:
			var block:Block = block_scene.instantiate()
			var local_base_pos = Vector2i(block_data["base_pos"][0], block_data["base_pos"][1])
			block.base_rotation_degree = block_data["rotation"][0]
			block.collision_layer = 2
			block.collision_mask = 2
			
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

func clear_existing_blocks():
	for block in blocks:
		block.queue_free()
	blocks.clear()
	grid.clear()
	tracks.clear()
	powerpacks.clear()

func get_blueprint_path() -> String:
	if blueprint is String:
		return blueprint
	elif blueprint is Dictionary:
		return "res://vehicles/blueprint/%s.json" % vehicle_name
	return ""

########################## VEHICLE PHYSICS PROCESSING #######################

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

func get_global_mass_center() -> Vector2:
	var com = calculate_center_of_mass()
	if grid.is_empty():
		return Vector2.ZERO
	
	var first_grid_pos = grid.keys()[0]
	var first_block = grid[first_grid_pos]
	var first_grid_positions = get_block_grid(first_block)
	
	if first_block is Block:
		var first_rotation = deg_to_rad(rad_to_deg(first_block.global_rotation) - first_block.base_rotation_degree)
		var first_position = get_rectangle_corners(first_grid_positions)
		var local_offset = com - first_position
		var rotated_offset = local_offset.rotated(first_rotation)
		return first_block.global_position + rotated_offset
	
	return Vector2.ZERO

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
			# 履带停止工作，不提供动力
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
		# 移动功率分量
		var move_component = balanced_forces[track] * total_power * forward_power_ratio * forward_input
		# 旋转功率分量  
		var rotate_component = rotation_forces[track] * total_power * rotate_power_ratio * turn_input
		# 总功率 = 移动功率 + 旋转功率
		track_forces[track] = move_component + rotate_component
	return track_forces 




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

########################## 履带承重系统函数 ##########################

func calculate_total_track_load_capacity() -> float:
	"""计算所有正常工作的履带的总承重能力"""
	var total_capacity := 0.0
	
	for track in tracks:
		if is_instance_valid(track):
			var load_status = track.get_load_status()
			if load_status["functioning"]:
				total_capacity += track.max_load
	
	return total_capacity

func calculate_current_total_load() -> float:
	"""计算当前所有履带承受的总重量"""
	var total_current_load := 0.0
	
	for track in tracks:
		if is_instance_valid(track):
			var load_status = track.get_load_status()
			if load_status["functioning"]:
				total_current_load += load_status["current_load"]
	
	return total_current_load

func get_load_safety_margin() -> float:
	"""获取载重安全余量（正数表示有富余，负数表示超载）"""
	var total_capacity = calculate_total_track_load_capacity()
	var current_load = calculate_current_total_load()
	
	return total_capacity - current_load

func get_overload_percentage() -> float:
	"""获取超载百分比（>0表示超载）"""
	var total_capacity = calculate_total_track_load_capacity()
	var current_load = calculate_current_total_load()
	
	if total_capacity <= 0:
		return 0.0
	
	return max(0.0, (current_load / total_capacity - 1.0) * 100.0)

func is_any_track_overloaded() -> bool:
	"""检查是否有任意履带超载"""
	for track in tracks:
		if is_instance_valid(track):
			var load_status = track.get_load_status()
			if load_status["overloaded"]:
				return true
	return false

func get_overloaded_tracks_count() -> int:
	"""获取超载的履带数量"""
	var count := 0
	
	for track in tracks:
		if is_instance_valid(track):
			var load_status = track.get_load_status()
			if load_status["overloaded"]:
				count += 1
	
	return count

func get_track_load_distribution_summary() -> Dictionary:
	"""获取履带载重分布摘要"""
	var summary := {
		"total_tracks": tracks.size(),
		"functioning_tracks": 0,
		"overloaded_tracks": 0,
		"total_capacity": 0.0,
		"current_load": 0.0,
		"average_load_per_track": 0.0,
		"max_track_load": 0.0,
		"min_track_load": 0.0,
		"track_details": []
	}
	
	for track in tracks:
		if is_instance_valid(track):
			var status = track.get_load_status()
			summary["track_details"].append({
				"name": track.name,
				"max_load": track.max_load,
				"current_load": status["current_load"],
				"overloaded": status["overloaded"],
				"functioning": status["functioning"],
				"load_percentage": (status["current_load"] / track.max_load) * 100 if track.max_load > 0 else 0.0
			})
			
			if status["functioning"]:
				summary["functioning_tracks"] += 1
				summary["total_capacity"] += track.max_load
				summary["current_load"] += status["current_load"]
				
				# 更新最大/最小负载
				if status["current_load"] > summary["max_track_load"]:
					summary["max_track_load"] = status["current_load"]
				if summary["min_track_load"] == 0.0 or status["current_load"] < summary["min_track_load"]:
					summary["min_track_load"] = status["current_load"]
			
			if status["overloaded"]:
				summary["overloaded_tracks"] += 1
	
	if summary["functioning_tracks"] > 0:
		summary["average_load_per_track"] = summary["current_load"] / summary["functioning_tracks"]
	
	return summary

func apply_load_penalties():
	"""根据载重状态应用惩罚效果"""
	var summary = get_track_load_distribution_summary()
	
	# 如果有履带超载，降低车辆性能
	if summary["overloaded_tracks"] > 0:
		var overload_ratio = float(summary["overloaded_tracks"]) / summary["total_tracks"]
		
		# 速度惩罚
		var speed_multiplier = 1.0 - (overload_ratio * 0.5)  # 最多降低50%速度
		
		# 燃料消耗增加
		var fuel_consumption_multiplier = 1.0 + (overload_ratio * 0.3)  # 最多增加30%燃料消耗
		
		# 转向性能降低
		var steering_multiplier = 1.0 - (overload_ratio * 0.4)  # 最多降低40%转向性能
		
		return {
			"speed_multiplier": speed_multiplier,
			"fuel_consumption_multiplier": fuel_consumption_multiplier,
			"steering_multiplier": steering_multiplier,
			"is_overloaded": true,
			"overload_ratio": overload_ratio
		}
	
	return {
		"speed_multiplier": 1.0,
		"fuel_consumption_multiplier": 1.0,
		"steering_multiplier": 1.0,
		"is_overloaded": false,
		"overload_ratio": 0.0
	}

func update_load_check(delta: float):
	"""更新承重检查和伤害系统"""
	load_check_timer += delta
	
	# 每0.5秒更新一次承重分布（避免每帧计算）
	if load_check_timer >= 0.5:
		calculate_track_load_distribution()
		load_check_timer = 0.0
		
		# 检查是否有履带超载停止工作
		check_track_overload_status()

func calculate_track_load_distribution():
	"""计算履带承重分布 - 平均分配"""
	# 计算车辆总质量
	total_mass = 0.0
	for block in blocks:
		if block is Block and block.functioning:
			total_mass += block.mass
	
	# 如果没有履带或者没有质量，直接返回
	if tracks.is_empty() or total_mass <= 0:
		return
	
	# 计算每个履带平均承受的重量
	var average_load = total_mass / tracks.size()
	
	# 应用承重到每个履带
	for track in tracks:
		if track is Track and track.functioning:
			track.set_current_load(average_load)
			track_load_distribution[track] = average_load

func check_track_overload_status():
	"""检查履带超载状态，更新车辆功能"""
	var any_track_overloaded = false
	
	for track in tracks:
		if track is Track:
			var status = track.get_load_status()
			if status["overloaded"]:
				any_track_overloaded = true
	
	# 如果有履带超载停止工作，重新计算力的分布
	if any_track_overloaded:
		calculate_balanced_forces()
		calculate_rotation_forces()

func get_track_load_status() -> Dictionary:
	"""获取所有履带的承重状态"""
	var status = {}
	var total_overload = 0.0
	var overloaded_tracks = 0
	var functioning_tracks = 0
	
	for track in tracks:
		if track is Track:
			var track_status = track.get_load_status()
			status[track.name] = track_status
			
			if track_status["overload_amount"] > 0:
				total_overload += track_status["overload_amount"]
			
			if track_status["overloaded"]:
				overloaded_tracks += 1
			
			if track_status["functioning"]:
				functioning_tracks += 1
	
	return {
		"track_status": status,
		"total_mass": total_mass,
		"total_tracks": tracks.size(),
		"average_load": total_mass / max(1, tracks.size()),
		"total_overload": total_overload,
		"overloaded_tracks": overloaded_tracks,
		"functioning_tracks": functioning_tracks
	}

# 获取车辆的实际总质量（考虑所有块的损坏状态）
func get_actual_total_mass() -> float:
	var total_actual_mass := 0.0
	
	for block in blocks:
		if block is Block and block.functioning:
			total_actual_mass += block.get_actual_mass()
	
	return total_actual_mass
