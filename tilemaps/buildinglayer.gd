class_name buildinglayer
extends TileMapLayer

var layerdata: Dictionary[Vector2i, Dictionary]

func _ready():
	# 初始化时清除所有格子
	clear()

func update_from_layerdata():
	"""根据layerdata字典更新TileMap的显示"""
	# 首先清除所有格子
	clear()
	
	print("=== 开始更新TileMap显示 ===")
	print("layerdata 数量: ", layerdata.size())
	
	# 使用字典来记录已经处理过的方块，避免重复处理
	var processed_blocks = {}
	
	# 第一步：为每个TileMap格子设置对应的Tile
	for tilemap_cell in layerdata:
		var data = layerdata[tilemap_cell]
		
		# 获取方块路径，确定Tile类型
		var block_path = data.get("block_path", "")
		var tile_type = get_tile_for_block_path(block_path)
		
		# 获取建筑网格位置
		var building_grid_pos = Vector2i(data["grid_pos"][0], data["grid_pos"][1])
		
		# 获取方块信息
		var block_size = Vector2i(data["block_size"][0], data["block_size"][1])
		var rotation = data.get("rotation", 0)
		
		# 创建方块唯一标识符
		var block_id = create_block_identifier(data)
		
		# 如果这个方块已经处理过，跳过
		if processed_blocks.has(block_id):
			continue
		
		# 标记为已处理
		processed_blocks[block_id] = true
		
		print("处理方块: ", block_path, " 大小: ", block_size, " 旋转: ", rotation)
		
		# 根据方块大小和旋转计算所有格子的位置
		for x in range(block_size.x):
			for y in range(block_size.y):
				# 根据旋转计算偏移
				var offset = calculate_offset_by_rotation(Vector2i(x, y), rotation)
				
				# 计算基准位置（当前格子的建筑网格位置减去它在方块中的偏移）
				# 我们需要找到方块的基准位置
				var base_pos = find_base_position(building_grid_pos, Vector2i(x, y), rotation, block_size)
				
				# 计算当前小格的建筑网格位置
				var current_building_grid = base_pos + offset
				
				print("  小格 (", x, ",", y, ") -> 旋转偏移 ", offset, " -> 建筑网格 ", current_building_grid)
				
				# 查找这个建筑网格位置对应的TileMap格子
				var target_tilemap_cell = find_tilemap_cell_by_building_grid(current_building_grid, data["building_name"])
				
				if target_tilemap_cell != null:
					# 设置Tile
					set_cell(target_tilemap_cell, tile_type, Vector2i(0, 0))
					print("    设置TileMap格子 ", target_tilemap_cell, " -> Tile类型 ", tile_type)
				else:
					print("    警告: 未找到建筑网格位置 ", current_building_grid, " 对应的TileMap格子")
	
	print("=== 完成更新TileMap显示 ===")
	print("224", layerdata)

func create_block_identifier(data: Dictionary) -> String:
	"""创建方块的唯一标识符"""
	var building_name = data["building_name"]
	var block_path = data["block_path"]
	var rotation = data.get("rotation", 0)
	var block_size = Vector2i(data["block_size"][0], data["block_size"][1])
	var building_grid_pos = Vector2i(data["grid_pos"][0], data["grid_pos"][1])
	
	# 找到方块的基准位置
	var base_pos = find_base_position(building_grid_pos, Vector2i(0, 0), rotation, block_size)
	
	# 使用建筑名称、方块路径、旋转和基准位置创建唯一标识符
	return "%s_%s_%d_%d_%d" % [building_name, block_path, rotation, base_pos.x, base_pos.y]

func find_base_position(current_building_grid: Vector2i, local_offset: Vector2i, rotation: int, block_size: Vector2i) -> Vector2i:
	"""根据当前格子的建筑网格位置、局部偏移和旋转，计算方块的基准位置"""
	
	# 计算局部偏移在给定旋转下的实际偏移
	var rotated_offset = calculate_offset_by_rotation(local_offset, rotation)
	
	# 基准位置 = 当前建筑网格位置 - 旋转后的偏移
	var base_pos = current_building_grid - rotated_offset
	
	# 验证基准位置是否合理
	# 对于不同旋转，基准位置的定义可能不同
	match rotation:
		0:
			# 0度旋转，基准位置在左上角
			# 基准位置的x和y应该是当前建筑网格位置减去局部偏移
			return base_pos
		90:
			# 90度旋转，基准位置在右上角
			# 需要调整基准位置到方块的左上角
			return Vector2i(base_pos.x, base_pos.y - (block_size.x - 1))
		-90:
			# -90度旋转，基准位置在左下角
			# 需要调整基准位置到方块的左上角
			return Vector2i(base_pos.x - (block_size.y - 1), base_pos.y)
		180, -180:
			# 180度旋转，基准位置在右下角
			# 需要调整基准位置到方块的左上角
			return Vector2i(base_pos.x - (block_size.x - 1), base_pos.y - (block_size.y - 1))
		_:
			return base_pos

func find_tilemap_cell_by_building_grid(building_grid_pos: Vector2i, building_name: String) -> Vector2i:
	"""根据建筑网格位置和建筑名称查找对应的TileMap格子"""
	for tilemap_cell in layerdata:
		var data = layerdata[tilemap_cell]
		var data_building_name = data["building_name"]
		var data_grid_pos = Vector2i(data["grid_pos"][0], data["grid_pos"][1])
		
		# 检查建筑名称和网格位置是否匹配
		if data_building_name == building_name and data_grid_pos == building_grid_pos:
			return tilemap_cell
	
	return Vector2i(-1, -1)  # 返回无效位置表示未找到

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
