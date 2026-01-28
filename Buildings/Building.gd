class_name Building
extends Node2D

signal cargo_changed()
signal structure_changed()

const GRID_SIZE:int = 16

var building_size:Vector2i
var building_name:String
var blueprint:Variant
var blueprint_grid:= {}
var grid:= {}
var blocks:= []
var total_blocks:= []
var cargos:= []
var storage_blocks:= []
var production_blocks:= []
var commands:= []
var is_assembled:= false
var block_scenes:= {}
var selected:bool
var destroyed:bool
var center_of_mass:Vector2 = Vector2(0,0)

# 缓存优化
var cached_center_of_mass: Vector2
var cached_center_of_mass_dirty: bool = true
var ready_connect = true

func _ready():
	if blueprint:
		load_blueprint()
	else:
		initialize_empty_building()

func load_blueprint():
	if blueprint is String:
		load_from_file(blueprint)
	elif blueprint is Dictionary:
		load_from_blueprint(blueprint)
	else:
		push_error("Invalid blueprint format")
	update_building()

func initialize_empty_building():
	building_name = "Unnamed_Building"
	blocks = []
	total_blocks = []
	grid = {}
	storage_blocks = []
	production_blocks = []
	commands = []

func update_building():
	# Check block connectivity
	for block:Block in blocks:
		block.get_all_connected_blocks()
	
	# Update building parameters
	update_building_size()
	calculate_center_of_mass()
	
	# Check building destroyed (has command block)
	var has_command:= false
	for blk in commands:
		if blk.functioning:
			has_command = true
	destroyed = not has_command
	
	emit_signal("structure_changed")

###################### BLOCK MANAGEMENT ######################

func _add_block(block: Block, local_pos = null, grid_positions = null):
	if block not in blocks:
		blocks.append(block)
		total_blocks.append(block)
		block.global_grid_pos = get_rectangle_corners(grid_positions)
		
		if block is Cargo:
			cargos.append(block)
			emit_signal("cargo_changed")
		elif block is Command:
			commands.append(block)
	
	if not local_pos == null and not grid_positions == null:
		if block.parent_building == null:
			add_child(block)
			block.parent_building = self
		block.position = local_pos
		await block.connect_aready()
		
		for pos in grid_positions:
			grid[pos] = block
		
		block.set_connection_enabled(true)
	
	cached_center_of_mass_dirty = true
	update_building()

func remove_block(block: Block, imd: bool = false, _disconnected:bool = false):
	blocks.erase(block)
	if imd:
		total_blocks.erase(block)
		block.queue_free()
	
	var keys_to_erase = []
	for pos in grid:
		if grid[pos] == block:
			keys_to_erase.append(pos)
	for pos in keys_to_erase:
		grid.erase(pos)
	
	if block in storage_blocks:
		storage_blocks.erase(block)
	if block in production_blocks:
		production_blocks.erase(block)
	if block in commands:
		commands.erase(block)
	if block in cargos:
		cargos.erase(block)
		emit_signal("cargo_changed")
	
	cached_center_of_mass_dirty = true
	update_building()

func has_block(block_name:String):
	for block in blocks:
		if block.block_name == block_name:
			return block
	return null

##################### BUILDING PARAMETER MANAGEMENT #####################

func get_total_storage_capacity() -> int:
	var capacity := 0
	for storage in storage_blocks:
		if storage.is_inside_tree() and is_instance_valid(storage):
			capacity += storage.capacity
	return capacity

func get_used_storage() -> int:
	var used := 0
	for storage in storage_blocks:
		if storage.is_inside_tree() and is_instance_valid(storage):
			used += storage.current_amount
	return used

########################## BUILDING LOADING ###########################

func load_from_file(identifier):
	var path: String
	if identifier is String:
		if not identifier.ends_with(".json"):
			path = "res://buildings/blueprint/%s.json" % identifier
		else:
			path = identifier
	elif identifier is int:
		path = "res://buildings/blueprint/%d.json" % identifier
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
	building_name = _name
	building_size = Vector2i(bp["building_size"][0], bp["building_size"][1])
	
	# 按数字键排序以保证加载顺序一致
	var block_ids = bp["blocks"].keys()
	block_ids.sort_custom(func(a, b):
		var pos_a = Vector2i(bp["blocks"][a]["base_pos"][0], bp["blocks"][a]["base_pos"][1])
		var pos_b = Vector2i(bp["blocks"][b]["base_pos"][0], bp["blocks"][b]["base_pos"][1])
		if pos_a.x != pos_b.x:
			return pos_a.x < pos_b.x
		return pos_a.y < pos_b.y
	)
	
	# 加载所有块
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
	
	update_building()

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

func get_blueprint_path() -> String:
	if blueprint is String:
		return blueprint
	elif blueprint is Dictionary:
		return "res://buildings/blueprint/%s.json" % building_name
	return ""

########################## BUILDING PHYSICS PROCESSING #######################

func get_block_grid(block:Block) -> Array:
	var positions:Array
	for pos in grid.keys():
		if grid[pos] == block and not positions.has(pos):
			positions.append(pos)
	return positions

func calculate_center_of_mass() -> Vector2:
	if not cached_center_of_mass_dirty:
		return cached_center_of_mass
	
	var total_mass := 0.0
	var weighted_sum := Vector2.ZERO
	var has_calculated := {}
	
	for grid_pos in grid:
		if grid[grid_pos] != null:
			var body: Block = grid[grid_pos]
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
	
	cached_center_of_mass = weighted_sum / total_mass if total_mass > 0 else Vector2.ZERO
	cached_center_of_mass_dirty = false
	return cached_center_of_mass

func update_building_size():
	if grid.is_empty():
		building_size = Vector2i.ZERO
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
	
	building_size = Vector2i(max_x - min_x + 1, max_y - min_y + 1)

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

########################## BUILDING FUNCTIONALITY ##########################

func is_operational() -> bool:
	"""检查建筑是否可运行（有至少一个可用的命令块）"""
	for command in commands:
		if command.functioning:
			return true
	return false

func get_building_stats() -> Dictionary:
	"""获取建筑统计信息"""
	return {
		"name": building_name,
		"size": building_size,
		"block_count": blocks.size(),
		"storage_capacity": get_total_storage_capacity(),
		"used_storage": get_used_storage(),
		"is_operational": is_operational(),
		"is_destroyed": destroyed
	}

func can_place_block_at(block: Block, position: Vector2) -> bool:
	"""检查指定位置是否可以放置块"""
	var target_grid = calculate_block_grid_positions(block, position)
	
	for pos in target_grid:
		if grid.has(pos):
			return false
		# 可以添加其他检查，如地形限制等
	
	return true

func get_neighbors_for_block(block: Block) -> Array:
	"""获取指定块的所有相邻块"""
	var neighbors = []
	var block_grid_positions = get_block_grid(block)
	
	for pos in block_grid_positions:
		# 检查上下左右四个方向
		var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		for dir in directions:
			var neighbor_pos = pos + dir
			if grid.has(neighbor_pos):
				var neighbor = grid[neighbor_pos]
				if neighbor != block and neighbor not in neighbors:
					neighbors.append(neighbor)
	
	return neighbors
