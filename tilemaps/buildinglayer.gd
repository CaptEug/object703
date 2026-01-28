class_name buildinglayer
extends TileMapLayer

var layerdata: Dictionary[Vector2i, Dictionary]

const BLUEPRINT_LOAD_PATH = "res://buildings/blueprint/"

func _ready():
	# 初始化时清除所有格子
	clear()

func update_from_layerdata():
	"""根据layerdata字典更新TileMap的显示"""
	var processed_blocks = {}
	
	for cell in layerdata:
		var data = layerdata[cell]
		
		# 检查这个格子是否属于一个方块的基准位置
		if "base_grid_pos" in data and "block_size" in data:
			var base_key = Vector2i(data["base_grid_pos"][0], data["base_grid_pos"][1])
			# 如果这个方块还没有被处理过，显示它的所有格子
			if not processed_blocks.has(base_key):
				processed_blocks[base_key] = true
				
				# 根据方块大小和旋转计算所有格子的位置
				var block_size = Vector2i(data["block_size"][0], data["block_size"][1])
				var rotation = data.get("rotation", 0)
				
				# 为方块的每个格子设置显示
				for x in range(block_size.x):
					for y in range(block_size.y):
						# 根据旋转计算偏移
						var offset = calculate_offset_by_rotation(Vector2i(x, y), rotation)
						var base_pos = Vector2i(data["base_grid_pos"][0], data["base_grid_pos"][1])
						var grid_pos = base_pos + offset
						
						# 找到这个网格位置对应的TileMap格子
						# 这里需要根据原始建筑位置和旋转计算实际的世界位置
						# 这是一个简化版本，实际需要更复杂的计算
						set_cell(cell, get_tile_for_block_path(data["block_path"]), Vector2i(0, 0))
		# 如果没有基准位置信息，直接显示
		else:
			set_cell(cell, 0, Vector2i(0, 0))
	print("224", layerdata)

func calculate_offset_by_rotation(local_pos: Vector2i, rotation: int) -> Vector2i:
	"""根据旋转计算偏移"""
	match rotation:
		0:
			return local_pos
		90:
			return Vector2i(-local_pos.y, local_pos.x)
		-90:
			return Vector2i(local_pos.y, -local_pos.x)
		180, -180:
			return -local_pos
		_:
			return local_pos

func get_tile_for_block_path(path: String) -> int:
	"""根据方块路径判断类型，设置不同的图块"""
	if path.contains("/auxiliary/"):
		return 1
	elif path.contains("/command/"):
		return 2
	elif path.contains("/firepower/"):
		return 3
	elif path.contains("/industrial/"):
		return 4
	elif path.contains("/structual/"):
		return 5
	elif path.contains("/turret/"):
		return 6
	else:
		return 0

func get_data_at_position(cell: Vector2i) -> Dictionary:
	"""获取指定位置的数据"""
	return layerdata.get(cell, {})

func remove_data_at_position(cell: Vector2i):
	"""移除指定位置的数据"""
	if layerdata.has(cell):
		layerdata.erase(cell)
		erase_cell(cell)

func has_building_at(cell: Vector2i) -> bool:
	"""检查指定位置是否有建筑"""
	return layerdata.has(cell)

func get_building_name_at(cell: Vector2i) -> String:
	"""获取指定位置的建筑名称"""
	var data = layerdata.get(cell, {})
	return data.get("building_name", "")

func get_all_building_cells() -> Array:
	"""获取所有有建筑的位置"""
	return layerdata.keys()

func get_building_cells_by_name(building_name: String) -> Array:
	"""根据建筑名称获取所有相关位置"""
	var cells = []
	for cell in layerdata:
		var data = layerdata[cell]
		if data.get("building_name") == building_name:
			cells.append(cell)
	return cells

func remove_building(building_name: String):
	"""移除指定建筑的所有数据"""
	var cells_to_remove = []
	
	for cell in layerdata:
		var data = layerdata[cell]
		if data.get("building_name") == building_name:
			cells_to_remove.append(cell)
	
	for cell in cells_to_remove:
		layerdata.erase(cell)
	
	update_from_layerdata()

func clear_all_buildings():
	"""清除所有建筑数据"""
	layerdata.clear()
	clear()

# ==================== 新增功能：从layerdata生成建筑实体 ====================

func generate_buildings_from_data(parent_node: Node2D = null):
	"""根据layerdata生成实际的建筑和方块实体"""
	print("=== BuildingLayer: 从layerdata生成建筑 ===")
	
	if layerdata.size() == 0:
		print("layerdata为空，无需生成")
		return
	
	# 如果未指定父节点，使用当前场景
	var target_parent = parent_node if parent_node else get_tree().current_scene
	
	# 按建筑名称分组数据
	var buildings_data = _group_data_by_buildings()
	
	# 为每个建筑生成实体
	for building_name in buildings_data:
		_generate_single_building(building_name, buildings_data[building_name], target_parent)
	
	print("建筑生成完成，共生成", buildings_data.size(), "个建筑")

func _group_data_by_buildings() -> Dictionary:
	"""将layerdata按建筑名称分组"""
	var buildings = {}
	
	for tilemap_cell in layerdata:
		var data = layerdata[tilemap_cell]
		var building_name = data["building_name"]
		
		if not buildings.has(building_name):
			buildings[building_name] = []
		
		buildings[building_name].append({
			"tilemap_cell": tilemap_cell,
			"data": data
		})
	
	return buildings

func _generate_single_building(building_name: String, blocks_data: Array, parent_node: Node2D):
	"""生成单个建筑实体"""
	print("生成建筑: ", building_name)
	
	# 创建建筑节点
	var building_node = Building.new()
	building_node.building_name = building_name
	
	# 计算建筑的位置
	# 使用第一个方块的位置作为参考
	var first_block_data = blocks_data[0]["data"]
	var first_tilemap_cell = blocks_data[0]["tilemap_cell"]
	
	# 将TileMap网格坐标转换为世界坐标
	var world_pos = map_to_local(first_tilemap_cell)
	building_node.global_position = world_pos
	
	parent_node.add_child(building_node)
	print("  建筑位置: ", world_pos)
	
	# 处理建筑中的所有方块（去重处理）
	var processed_blocks = {}
	
	for block_info in blocks_data:
		var data = block_info["data"]
		var tilemap_cell = block_info["tilemap_cell"]
		
		# 获取方块信息
		var block_path = data["block_path"]
		var rotation = data.get("rotation", 0)
		var block_size = Vector2i(data["block_size"][0], data["block_size"][1])
		var building_grid_pos = Vector2i(data["grid_pos"][0], data["grid_pos"][1])
		var hp = data.get("hp", 100.0)
		
		# 计算方块的基准位置（左上角）
		var base_pos = _calculate_block_base_position(building_grid_pos, block_size, rotation)
		var block_id = "%s_%d_%d_%d" % [block_path, rotation, base_pos.x, base_pos.y]
		
		# 如果这个方块已经处理过，跳过
		if processed_blocks.has(block_id):
			continue
		
		# 标记为已处理
		processed_blocks[block_id] = true
		
		print("  生成方块: ", data["block_name"], " 大小: ", block_size, " 旋转: ", rotation)
		
		# 加载并实例化方块
		var scene = load(block_path)
		if not scene:
			print("    错误: 无法加载方块场景: ", block_path)
			continue
		
		var block_instance = scene.instantiate()
		if not block_instance is Block:
			print("    错误: 场景不是Block类型: ", block_path)
			block_instance.queue_free()
			continue
		
		# 设置方块属性
		block_instance.base_rotation_degree = rotation
		block_instance.rotation = deg_to_rad(rotation)
		block_instance.current_hp = hp
		
		# 计算方块的世界位置
		# 使用方块的基准位置（建筑网格坐标）来计算
		var block_world_pos = _calculate_block_world_position(base_pos, building_node)
		block_instance.global_position = block_world_pos
		
		# 添加到建筑节点
		building_node.add_child(block_instance)
		
		# 收集方块占据的所有建筑网格位置
		var block_grid_positions = []
		for x in range(block_size.x):
			for y in range(block_size.y):
				var local_pos = Vector2i(x, y)
				var rotated_offset = calculate_offset_by_rotation(local_pos, rotation)
				var current_building_grid = base_pos + rotated_offset
				block_grid_positions.append([current_building_grid.x, current_building_grid.y])
		
		# 将方块添加到建筑的网格系统中
		if building_node.has_method("_add_block"):
			var block_local_pos = Vector2(base_pos) * 16.0
			building_node._add_block(block_instance, block_local_pos, block_grid_positions)
			print("    方块已添加到建筑网格系统")
		else:
			print("    警告: 建筑节点没有 _add_block 方法")
	
	print("  建筑", building_name, "生成完成，包含", processed_blocks.size(), "个方块")


# ==================== 新增功能：加载和保存到文件 ====================

func save_to_file(file_path: String):
	"""将layerdata保存到文件"""
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		# 转换为JSON格式
		var json_data = {}
		for key in layerdata:
			# 将Vector2i键转换为字符串
			var key_str = "%d,%d" % [key.x, key.y]
			json_data[key_str] = layerdata[key]
		
		var json_string = JSON.stringify(json_data, "\t")
		file.store_string(json_string)
		file.close()
		print("layerdata已保存到: ", file_path)
	else:
		print("错误: 无法保存文件: ", file_path)

func load_from_file(file_path: String, parent_node: Node2D = null):
	"""从文件加载layerdata并生成建筑"""
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var parse_result = json.parse(json_string)
		
		if parse_result == OK:
			# 清空当前数据
			layerdata.clear()
			
			# 解析JSON数据
			var json_data = json.data
			for key_str in json_data:
				# 将字符串键转换回Vector2i
				var parts = key_str.split(",")
				if parts.size() == 2:
					var key = Vector2i(int(parts[0]), int(parts[1]))
					layerdata[key] = json_data[key_str]
			
			print("layerdata已从文件加载: ", file_path)
			
			# 更新TileMap显示
			update_from_layerdata()
			
			# 生成建筑实体
			generate_buildings_from_data(parent_node)
		else:
			print("错误: 无法解析JSON文件")
	else:
		print("错误: 无法加载文件: ", file_path)

func load_all_blueprints():
	"""加载所有蓝图文件到layerdata"""
	print("=== 开始加载蓝图文件 ===")
	
	# 确保蓝图目录存在
	_ensure_blueprint_directory()
	
	# 清空当前layerdata
	layerdata.clear()
	
	# 获取所有蓝图文件
	var dir = DirAccess.open(BLUEPRINT_LOAD_PATH)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		var loaded_count = 0
		
		while file_name != "":
			if not file_name.begins_with(".") and file_name.ends_with(".json"):
				var file_path = BLUEPRINT_LOAD_PATH + file_name
				print("加载蓝图文件: ", file_path)
				
				if _load_blueprint_file(file_path):
					loaded_count += 1
			
			file_name = dir.get_next()
		
		dir.list_dir_end()
		
		print("共加载 ", loaded_count, " 个蓝图文件")
		
		# 更新TileMap显示
		update_from_layerdata()
		print("TileMap显示已更新")
	else:
		print("错误: 无法访问蓝图目录: ", BLUEPRINT_LOAD_PATH)

func _ensure_blueprint_directory():
	"""确保蓝图目录存在"""
	var dir = DirAccess.open("res://")
	if dir:
		if not dir.dir_exists("buildings"):
			dir.make_dir("buildings")
			print("创建目录: res://buildings/")
		
		var buildings_dir = DirAccess.open("res://buildings/")
		if buildings_dir:
			if not buildings_dir.dir_exists("blueprint"):
				buildings_dir.make_dir("blueprint")
				print("创建蓝图目录: res://buildings/blueprint/")
		else:
			print("无法访问 buildings 目录")
	else:
		print("无法访问 res:// 目录")

func _load_blueprint_file(file_path: String) -> bool:
	"""加载单个蓝图文件"""
	if not FileAccess.file_exists(file_path):
		print("文件不存在: ", file_path)
		return false
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var parse_result = json.parse(json_string)
		
		if parse_result == OK:
			var blueprint_data = json.data
			print("成功解析蓝图: ", blueprint_data.get("name", "未知"))
			return _process_blueprint_data(blueprint_data, file_path.get_file())
		else:
			print("错误: 无法解析JSON文件: ", file_path)
			print("解析错误: ", json.get_error_message(), " 在第 ", json.get_error_line(), " 行")
			return false
	else:
		print("错误: 无法读取蓝图文件: ", file_path)
		print("错误代码: ", FileAccess.get_open_error())
		return false

func _process_blueprint_data(blueprint_data: Dictionary, filename: String) -> bool:
	"""处理蓝图数据，将其添加到layerdata"""
	var building_name = blueprint_data.get("name", filename.replace(".json", ""))
	var blocks_data = blueprint_data.get("blocks", {})
	
	print("处理蓝图: ", building_name, " 包含 ", blocks_data.size(), " 个方块")
	
	# 临时存储方块的TileMap坐标，用于计算建筑位置
	var temp_tilemap_cells = []
	
	# 处理每个方块
	for block_key in blocks_data:
		var block_data = blocks_data[block_key]
		
		var block_path = block_data.get("path", "")
		if block_path.is_empty():
			print("警告: 方块缺少路径信息")
			continue
		
		var block_name = block_data.get("name", "未知方块")
		var rotation = block_data.get("rotation", 0)
		var block_size_array = block_data.get("size", [1, 1])
		var block_size = Vector2i(block_size_array[0], block_size_array[1])
		var base_pos_array = block_data.get("base_pos", [0, 0])
		var base_pos = Vector2i(base_pos_array[0], base_pos_array[1])
		var hp = block_data.get("hp", 100.0)
		var grid_positions = block_data.get("grid_positions", [])
		
		print("  处理方块: ", block_name, " 大小: ", block_size, " 旋转: ", rotation)
		
		# 处理方块的每个小格
		for grid_pos_array in grid_positions:
			var grid_pos = Vector2i(grid_pos_array[0], grid_pos_array[1])
			
			# 计算当前小格相对于基准位置的偏移
			var local_offset = Vector2i(grid_pos.x - base_pos.x, grid_pos.y - base_pos.y)
			
			# 根据旋转计算偏移
			var rotated_offset = calculate_offset_by_rotation(local_offset, rotation)
			
			# 计算当前小格在建筑网格中的位置
			var current_building_grid = base_pos + rotated_offset
			
			# 将建筑网格坐标转换为TileMap网格坐标
			# 这里我们假设建筑的中心在TileMap的某个位置
			# 为了简化，我们将所有建筑放在TileMap的原点附近
			var tilemap_offset = Vector2i(50, 50)  # 偏移量，避免重叠
			var tilemap_grid_pos = current_building_grid + tilemap_offset
			
			# 存储到临时列表
			temp_tilemap_cells.append(tilemap_grid_pos)
			
			# 添加到layerdata
			layerdata[tilemap_grid_pos] = {
				"building_name": building_name,
				"block_name": block_name,
				"block_path": block_path,
				"rotation": rotation,
				"hp": hp,
				"block_size": [block_size.x, block_size.y],
				"grid_pos": [current_building_grid.x, current_building_grid.y]
			}
			
			print("    小格 ", current_building_grid, " -> TileMap格子 ", tilemap_grid_pos)
	
	print("  蓝图 ", building_name, " 处理完成，添加了 ", temp_tilemap_cells.size(), " 个TileMap格子")
	return true

func generate_buildings_from_layerdata(parent_node: Node2D = null):
	"""从layerdata生成实际的建筑和方块实体"""
	print("=== BuildingLayer: 从layerdata生成建筑实体 ===")
	
	if layerdata.size() == 0:
		print("layerdata为空，无需生成")
		return
	
	# 如果未指定父节点，使用当前场景
	var target_parent = parent_node if parent_node else get_tree().current_scene
	
	# 按建筑名称分组数据
	var buildings_data = _group_layerdata_by_buildings()
	
	# 为每个建筑生成实体
	for building_name in buildings_data:
		_generate_building_from_layerdata(building_name, buildings_data[building_name], target_parent)
	
	print("建筑生成完成，共生成", buildings_data.size(), "个建筑")

func _group_layerdata_by_buildings() -> Dictionary:
	"""将layerdata按建筑名称分组"""
	var buildings = {}
	
	for tilemap_cell in layerdata:
		var data = layerdata[tilemap_cell]
		var building_name = data["building_name"]
		
		if not buildings.has(building_name):
			buildings[building_name] = []
		
		buildings[building_name].append({
			"tilemap_cell": tilemap_cell,
			"data": data
		})
	
	return buildings

func _generate_building_from_layerdata(building_name: String, blocks_data: Array, parent_node: Node2D):
	"""从layerdata生成单个建筑实体"""
	print("生成建筑实体: ", building_name)
	
	# 创建建筑节点
	var building_node = Building.new()
	building_node.building_name = building_name
	
	# 计算建筑的位置
	# 使用第一个TileMap格子的位置作为建筑位置
	if blocks_data.size() > 0:
		var first_tilemap_cell = blocks_data[0]["tilemap_cell"]
		var world_pos = map_to_local(first_tilemap_cell)
		building_node.global_position = world_pos
		print("  建筑位置: ", world_pos)
	
	parent_node.add_child(building_node)
	
	# 处理建筑中的所有方块
	var processed_blocks = {}
	
	for block_info in blocks_data:
		var data = block_info["data"]
		
		# 获取方块信息
		var block_path = data["block_path"]
		var block_name = data["block_name"]
		var rotation = data.get("rotation", 0)
		var block_size = Vector2i(data["block_size"][0], data["block_size"][1])
		var building_grid_pos = Vector2i(data["grid_pos"][0], data["grid_pos"][1])
		var hp = data.get("hp", 100.0)
		
		# 计算方块的基准位置（左上角）
		var base_pos = _calculate_block_base_position(building_grid_pos, block_size, rotation)
		var block_id = "%s_%d_%d_%d" % [block_path, rotation, base_pos.x, base_pos.y]
		
		# 如果这个方块已经处理过，跳过
		if processed_blocks.has(block_id):
			continue
		
		# 标记为已处理
		processed_blocks[block_id] = true
		
		print("  生成方块: ", block_name, " 大小: ", block_size, " 旋转: ", rotation)
		
		# 加载并实例化方块
		var scene = load(block_path)
		if not scene:
			print("    错误: 无法加载方块场景: ", block_path)
			continue
		
		var block_instance = scene.instantiate()
		if not block_instance is Block:
			print("    错误: 场景不是Block类型: ", block_path)
			block_instance.queue_free()
			continue
		
		# 设置方块属性
		block_instance.base_rotation_degree = rotation
		block_instance.rotation = deg_to_rad(rotation)
		block_instance.current_hp = hp
		
		# 计算方块的世界位置
		var block_world_pos = _calculate_block_world_position(base_pos, building_node)
		block_instance.global_position = block_world_pos
		
		# 添加到建筑节点
		building_node.add_child(block_instance)
		
		# 收集方块占据的所有建筑网格位置
		var block_grid_positions = []
		for x in range(block_size.x):
			for y in range(block_size.y):
				var local_pos = Vector2i(x, y)
				var rotated_offset = calculate_offset_by_rotation(local_pos, rotation)
				var current_building_grid = base_pos + rotated_offset
				block_grid_positions.append([current_building_grid.x, current_building_grid.y])
		
		# 将方块添加到建筑的网格系统中
		if building_node.has_method("_add_block"):
			var block_local_pos = Vector2(base_pos) * 16.0
			building_node._add_block(block_instance, block_local_pos, block_grid_positions)
			print("    方块已添加到建筑网格系统")
	
	print("  建筑", building_name, "生成完成")

func _calculate_block_base_position(grid_pos: Vector2i, block_size: Vector2i, rotation: int) -> Vector2i:
	"""计算方块的基准位置（左上角）"""
	match rotation:
		0:
			return grid_pos
		90:
			return Vector2i(grid_pos.x, grid_pos.y - (block_size.x - 1))
		-90:
			return Vector2i(grid_pos.x - (block_size.y - 1), grid_pos.y)
		180, -180:
			return Vector2i(grid_pos.x - (block_size.x - 1), grid_pos.y - (block_size.y - 1))
		_:
			return grid_pos

func _calculate_block_world_position(building_grid_pos: Vector2i, building_node: Building) -> Vector2:
	"""根据建筑网格坐标计算世界坐标"""
	var grid_size = 16.0
	var local_pixel_pos = Vector2(building_grid_pos) * grid_size
	var rotated_pos = local_pixel_pos.rotated(building_node.global_rotation)
	return building_node.global_position + rotated_pos
