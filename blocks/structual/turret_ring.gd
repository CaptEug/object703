class_name TurretRing
extends Block

var load:float
var turret:RigidBody2D
var traverse:Array
var max_torque:float = 10000
var damping:float = 3000

# 炮塔专用的grid系统
var turret_grid := {}
var turret_blocks := []
var turret_size: Vector2i

# 炮塔旋转控制
var is_turret_rotation_enabled: bool = true

func _ready():
	super._ready()
	turret = find_child("Turret") as RigidBody2D
	initialize_turret_grid()

func _physics_process(_delta):
	# 只有在启用时才进行瞄准
	if is_turret_rotation_enabled:
		aim(get_global_mouse_position())
	else:
		if turret:
			turret.rotation = 0

func aim(target_pos):
	if not is_turret_rotation_enabled:
		return
		
	var target_angle = (target_pos - global_position).angle() - global_rotation + deg_to_rad(90)
	var angle_diff = wrapf(target_angle - turret.rotation, -PI, PI)
	
	if traverse:
		var min_angle = deg_to_rad(traverse[0])
		var max_angle = deg_to_rad(traverse[1])
		turret.rotation = clamp(turret.rotation, min_angle, max_angle)
	
	var torque = angle_diff * max_torque - turret.angular_velocity * damping
	
	if abs(angle_diff) > deg_to_rad(1): 
		turret.apply_torque(torque)
	
	# return true if aimed
	return abs(angle_diff) < deg_to_rad(1)

###################### 炮塔Grid系统 ######################

func initialize_turret_grid():
	"""初始化炮塔的grid系统"""
	turret_grid.clear()
	turret_blocks.clear()
	
	# 查找炮塔上已有的block（比如装甲块）
	for child in turret.get_children():
		if child is Block and child != self:
			add_block_to_turret(child)

func add_block_to_turret(block: Block, grid_positions: Array = []):
	"""添加block到炮塔grid系统"""
	if block not in turret_blocks:
		turret_blocks.append(block)
		
		# 如果没有指定grid位置，自动计算
		if grid_positions.is_empty():
			grid_positions = calculate_block_grid_positions(block)
		
		# 添加到grid
		for pos in grid_positions:
			turret_grid[pos] = block
		
		# 设置block为炮塔的子节点
		if block.get_parent() != turret:
			var old_parent = block.get_parent()
			if old_parent and old_parent.has_method("remove_block"):
				old_parent.remove_block(block, false)
			
			# 在添加到炮塔之前，需要将全局坐标转换为炮塔局部坐标
			var global_pos = block.global_position
			var global_rot = block.global_rotation
			turret.add_child(block)
			block.global_position = global_pos  # 保持全局位置不变
			block.global_rotation = global_rot  # 保持全局旋转不变
			
		# 确保块的碰撞层设置为2
		if block is CollisionObject2D:
			block.collision_layer = 2
			block.collision_mask = 2
		
		# 更新炮塔物理属性
		update_turret_physics()
		
		# 更新炮塔大小
		update_turret_size()
		
		print("添加block到炮塔: ", block.block_name, " 位置: ", grid_positions)

func remove_block_from_turret(block: Block):
	"""从炮塔grid系统移除block"""
	if block in turret_blocks:
		turret_blocks.erase(block)
		
		# 从grid中移除
		var keys_to_erase = []
		for pos in turret_grid:
			if turret_grid[pos] == block:
				keys_to_erase.append(pos)
		for pos in keys_to_erase:
			turret_grid.erase(pos)
		
		# 从场景中移除
		if block.get_parent() == turret:
			turret.remove_child(block)
		block.queue_free()
		# 更新炮塔物理属性
		update_turret_physics()
		
		# 更新炮塔大小
		update_turret_size()
		
		print("从炮塔移除block: ", block.block_name)

func calculate_block_grid_positions(block: Block) -> Array:
	"""计算block在炮塔grid中的位置 - 使用连接点location"""
	var positions = []
	
	# 这里需要获取块是通过哪个连接点连接的
	# 暂时使用块的局部位置，但理想情况下应该从连接信息中获取
	var block_position = block.position
	
	# 从块的本地位置计算基础网格位置
	var base_pos = Vector2i(
		floor(block_position.x / 16),
		floor(block_position.y / 16)
	)
	
	print("炮塔网格计算:")
	print("  块局部位置: ", block_position)
	print("  基础网格位置: ", base_pos)
	print("  块大小: ", block.size)
	print("  块基础旋转: ", block.base_rotation_degree)
	
	# 根据block的大小和旋转计算所有网格位置
	for x in range(block.size.x):
		for y in range(block.size.y):
			var grid_pos: Vector2i
			
			# 考虑block的旋转
			match int(block.base_rotation_degree):
				0:
					grid_pos = base_pos + Vector2i(x, y)
				90:
					grid_pos = base_pos + Vector2i(-y, x)
				-90:
					grid_pos = base_pos + Vector2i(y, -x)
				180, -180:
					grid_pos = base_pos + Vector2i(-x, -y)
				_:
					grid_pos = base_pos + Vector2i(x, y)
			
			positions.append(grid_pos)
	
	print("  最终网格位置: ", positions)
	return positions

func update_turret_size():
	"""更新炮塔的尺寸"""
	if turret_grid.is_empty():
		turret_size = Vector2i.ZERO
		return
	
	var min_x: int = turret_grid.keys()[0].x
	var min_y: int = turret_grid.keys()[0].y
	var max_x: int = turret_grid.keys()[0].x
	var max_y: int = turret_grid.keys()[0].y
	
	for grid_pos in turret_grid:
		min_x = min(min_x, grid_pos.x)
		min_y = min(min_y, grid_pos.y)
		max_x = max(max_x, grid_pos.x)
		max_y = max(max_y, grid_pos.y)
	
	turret_size = Vector2i(max_x - min_x + 1, max_y - min_y + 1)

func update_turret_physics():
	"""更新炮塔的物理属性（质量、质心等）"""
	var total_mass = 0.0
	var center_of_mass = Vector2.ZERO
	
	for block in turret_blocks:
		if is_instance_valid(block):
			total_mass += block.mass
			var block_positions = get_turret_block_grid(block)
			if not block_positions.is_empty():
				var block_center = calculate_block_center(block_positions)
				center_of_mass += block_center * block.mass
	
	if total_mass > 0:
		center_of_mass /= total_mass
		# 更新炮塔的质量和质心
		turret.mass = total_mass

func get_turret_block_at_position(grid_pos: Vector2i) -> Block:
	"""获取指定grid位置的block"""
	return turret_grid.get(grid_pos)

func get_turret_block_grid(block: Block) -> Array:
	"""获取block在炮塔grid中的所有位置"""
	var positions = []
	for pos in turret_grid:
		if turret_grid[pos] == block:
			positions.append(pos)
	return positions

func is_position_available(grid_pos: Vector2i) -> bool:
	"""检查指定grid位置是否可用"""
	return turret_grid.get(grid_pos) == null

func get_available_connection_points() -> Array[ConnectionPoint]:
	"""获取炮塔上可用的连接点"""
	var points: Array[ConnectionPoint] = []
	
	# 获取炮塔底座上的连接点
	var base_points = find_children("*", "ConnectionPoint")
	for point in base_points:
		if point is ConnectionPoint and not point.connected_to:
			points.append(point)
	
	# 获取炮塔上已有块的连接点
	for block in turret_blocks:
		if is_instance_valid(block):
			var block_points = block.find_children("*", "ConnectionPoint")
			for point in block_points:
				if point is ConnectionPoint and not point.connected_to:
					points.append(point)
	
	return points

###################### 新增方法 - 修复编辑器错误 ######################

func get_attached_blocks() -> Array:
	"""获取炮塔上附加的所有块 - 用于编辑器"""
	return turret_blocks.duplicate()

func get_turret_blocks() -> Array:
	"""获取炮塔上所有块的别名方法"""
	return get_attached_blocks()

func get_all_blocks() -> Array:
	"""获取所有块（包括炮塔本身）"""
	var all_blocks = [self]  # 包括炮塔本身
	all_blocks.append_array(turret_blocks)
	return all_blocks

func get_turret_connectors() -> Array[RigidBodyConnector]:
	"""获取炮塔上的所有RigidBodyConnector"""
	var connectors: Array[RigidBodyConnector] = []
	
	# 获取炮塔底座上的连接器
	var base_connectors = find_children("*", "RigidBodyConnector")
	for connector in base_connectors:
		if connector is RigidBodyConnector and connector.is_connection_enabled and connector.connected_to == null:
			connectors.append(connector)
	
	# 获取炮塔上已有块的连接器
	for block in turret_blocks:
		if is_instance_valid(block):
			var block_connectors = block.find_children("*", "RigidBodyConnector")
			for connector in block_connectors:
				if connector is RigidBodyConnector and connector.is_connection_enabled and connector.connected_to == null:
					connectors.append(connector)
	
	return connectors

func get_available_turret_connectors() -> Array[RigidBodyConnector]:
	"""获取可用的炮塔连接器"""
	var connectors: Array[RigidBodyConnector] = []
	
	for connector in get_turret_connectors():
		if connector.is_connection_enabled and connector.connected_to == null:
			connectors.append(connector)
	
	return connectors

###################### 炮塔编辑模式相关方法 ######################

func enable_turret_rotation():
	"""启用炮塔旋转"""
	is_turret_rotation_enabled = true
	print("启用炮塔旋转: ", block_name)

func disable_turret_rotation():
	"""禁用炮塔旋转"""
	is_turret_rotation_enabled = false
	
	# 停止所有旋转力
	if turret:
		turret.angular_velocity = 0
		turret.rotation = 0
	
	print("禁用炮塔旋转: ", block_name)

func reset_turret_rotation():
	"""炮塔回正"""
	if turret and is_instance_valid(turret):
		# 确保炮塔回正到0度
		if turret:
			turret.rotation = 0
		# 如果有基础旋转角度，也重置
		if has_method("set_base_rotation_degree"):
			turret.base_rotation_degree = 0
		

func lock_turret_rotation():
	"""锁定炮塔旋转（完全停止）"""
	disable_turret_rotation()
	reset_turret_rotation()
	is_turret_rotation_enabled = false
	# 额外确保停止所有物理运动
	if turret:
		turret.angular_velocity = 0
		turret.rotation = 0
		print("锁定炮塔旋转: ", block_name, turret.rotation)
	

func unlock_turret_rotation():
	"""解锁炮塔旋转"""
	if turret:
		turret.freeze = false
	enable_turret_rotation()
	is_turret_rotation_enabled = true
	print("解锁炮塔旋转: ", block_name)

func get_turret_grid_bounds() -> Dictionary:
	"""获取炮塔网格的边界"""
	if turret_grid.is_empty():
		return {"min_x": 0, "min_y": 0, "max_x": 0, "max_y": 0}
	
	var min_x: int = turret_grid.keys()[0].x
	var min_y: int = turret_grid.keys()[0].y
	var max_x: int = turret_grid.keys()[0].x
	var max_y: int = turret_grid.keys()[0].y
	
	for grid_pos in turret_grid:
		min_x = min(min_x, grid_pos.x)
		min_y = min(min_y, grid_pos.y)
		max_x = max(max_x, grid_pos.x)
		max_y = max(max_y, grid_pos.y)
	
	return {
		"min_x": min_x,
		"min_y": min_y,
		"max_x": max_x,
		"max_y": max_y,
		"width": max_x - min_x + 1,
		"height": max_y - min_y + 1
	}

func calculate_block_center(positions: Array) -> Vector2:
	"""计算一组grid位置的中心点（转换为局部坐标）"""
	if positions.is_empty():
		return Vector2.ZERO
	
	var min_x = positions[0].x
	var min_y = positions[0].y
	var max_x = positions[0].x
	var max_y = positions[0].y
	
	for pos in positions:
		min_x = min(min_x, pos.x)
		min_y = min(min_y, pos.y)
		max_x = max(max_x, pos.x)
		max_y = max(max_y, pos.y)
	
	# 转换为局部坐标（假设每个grid单元大小为16）
	var center_x = (min_x + max_x + 1) * 8  # 16/2 = 8
	var center_y = (min_y + max_y + 1) * 8
	return Vector2(center_x, center_y)

###################### 调试方法 ######################

func print_turret_status():
	"""打印炮塔状态信息"""
	print("=== 炮塔状态 ===")
	print("炮塔名称: ", block_name)
	print("炮塔块数量: ", turret_blocks.size())
	print("网格位置数量: ", turret_grid.size())
	print("网格边界: ", get_turret_grid_bounds())
	print("旋转启用: ", is_turret_rotation_enabled)
	
	# 打印所有块信息
	for i in range(turret_blocks.size()):
		var block = turret_blocks[i]
		if is_instance_valid(block):
			var grid_positions = get_turret_block_grid(block)
			print("块 ", i, ": ", block.block_name, " 网格位置: ", grid_positions)
		else:
			print("块 ", i, ": 无效")
