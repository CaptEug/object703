class_name TurretRing
extends Block

var load:float
var turret_basket:RigidBody2D
var joint:PinJoint2D
var traverse:Array
var max_torque:float
var damping:float = 1
var angvel_diff_old:= 0
var couple_torque_old:= 0

# 炮塔专用的grid系统-*0+
var turret_grid := {}
var turret_blocks := []
var turret_size: Vector2i
var total_mass:= 0.0

# 炮塔旋转控制
var is_turret_rotation_enabled: bool = true

func _ready():
	super._ready()
	turret_basket = find_child("TurretBasket") as RigidBody2D
	joint = find_child("PinJoint2D") as PinJoint2D
	total_mass = mass
	initialize_turret_grid()

func connect_aready():
	super.connect_aready()
	if parent_vehicle:
		remove_child(turret_basket)
		turret_basket.position = position
		turret_basket.rotation = rotation
		parent_vehicle.add_child(turret_basket)
		joint.node_a = get_path()
		joint.node_b = turret_basket.get_path()
		turret_basket.joint = joint

func _physics_process(_delta):
	# 只有在启用时才进行瞄准
	if is_turret_rotation_enabled:
		aim(get_global_mouse_position())
	else:
		if turret_basket:
			turret_basket.rotation = 0
		


func aim(target_pos):
	if not is_turret_rotation_enabled:
		return
	var target_angle = (target_pos - global_position).angle() - parent_vehicle.global_rotation + deg_to_rad(90)
	var angle_diff = wrapf(target_angle - turret_basket.rotation, -PI, PI)
	var angvel_diff = turret_basket.angular_velocity - angular_velocity
	var I = 1.0 / PhysicsServer2D.body_get_direct_state(turret_basket.get_rid()).inverse_inertia
	print("inertia:", I)
	var Kp
	if not is_nan(I) and not is_inf(I):
		Kp = 100 * I
	else:
		Kp = 0
	
	var couple_torque = couple_torque_old - Kp * (angvel_diff - angvel_diff_old)
	couple_torque = - Kp * angvel_diff
	
	if traverse:
		var min_angle = deg_to_rad(traverse[0])
		var max_angle = deg_to_rad(traverse[1])
		turret_basket.rotation = clamp(turret_basket.rotation, min_angle, max_angle)
	
	var torque = angle_diff/abs(angle_diff) * max_torque 
	
	if abs(angle_diff) > deg_to_rad(1): 
		if abs(angle_diff) < deg_to_rad(15):
			torque = angle_diff/deg_to_rad(15) * max_torque
		turret_basket.apply_torque(torque + couple_torque)
	
	angvel_diff_old = angvel_diff
	couple_torque_old = couple_torque
	
	print("toraue:",torque)
	print("C torque:", couple_torque)
	
	# return true if aimed
	return abs(angle_diff) < deg_to_rad(1)

###################### 炮塔Grid系统 ######################

func initialize_turret_grid():
	"""初始化炮塔的grid系统"""
	turret_grid.clear()
	turret_blocks.clear()
	
	# 查找炮塔上已有的block（比如装甲块）
	for child in turret_basket.get_children():
		if child is Block and child != self:
			add_block_to_turret(child)

func add_block_to_turret(block: Block, grid_positions: Array = []):
	"""添加block到炮塔grid系统"""
	if parent_vehicle:
		parent_vehicle.blocks.append(block)
		if block is Powerpack and block not in parent_vehicle.powerpacks:
			parent_vehicle.powerpacks.append(block)
		elif block is Command and block not in parent_vehicle.commands:
			parent_vehicle.commands.append(block)
		elif block is Ammorack and block not in parent_vehicle.ammoracks:
			parent_vehicle.ammoracks.append(block)
		elif block is Fueltank and block not in parent_vehicle.fueltanks:
			parent_vehicle.fueltanks.append(block)
	if block not in turret_blocks:
		turret_blocks.append(block)
		block.z_index = 100
		# 如果没有指定grid位置，自动计算
		if grid_positions.is_empty():
			grid_positions = calculate_block_grid_positions(block)
		
		# 添加到grid
		for pos in grid_positions:
			turret_grid[pos] = block
		
		# 设置block为炮塔的子节点
		if block.get_parent() != turret_basket:
			var old_parent = block.get_parent()
			if old_parent and old_parent.has_method("remove_block"):
				old_parent.remove_block(block, false)
			
			# 在添加到炮塔之前，需要将全局坐标转换为炮塔局部坐标
			var global_pos = block.global_position
			var global_rot = block.global_rotation
			parent_vehicle._add_block(block, global_pos, grid_positions)
			print(block.get_parent())
			block.global_position = global_pos  # 保持全局位置不变
			block.global_rotation = global_rot  # 保持全局旋转不变
			
		# 确保块的碰撞层设置为2
		if block is CollisionObject2D:
			block.collision_layer = 2
			block.collision_mask = 2
		
		block.get_parent_vehicle()
		# 更新炮塔物理属性
		update_turret_physics()
		
		# 更新炮塔大小
		update_turret_size()
		

func remove_block_from_turret(block: Block):
	"""从炮塔grid系统移除block"""
	if parent_vehicle:
		parent_vehicle.blocks.erase(block)
		if block is Powerpack and block in parent_vehicle.powerpacks:
			parent_vehicle.powerpacks.erase(block)
		elif block is Command and block in parent_vehicle.commands:
			parent_vehicle.commands.erase(block)
		elif block is Ammorack and block in parent_vehicle.ammoracks:
			parent_vehicle.ammoracks.erase(block)
		elif block is Fueltank and block in parent_vehicle.fueltanks:
			parent_vehicle.fueltanks.erase(block)
	
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
		parent_vehicle.remove_block(block, true)
		block.queue_free()
		
		# 更新炮塔物理属性
		update_turret_physics()
		
		# 更新炮塔大小
		update_turret_size()
		

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
	total_mass = mass
	
	for block:Block in turret_blocks:
		if is_instance_valid(block):
			total_mass += block.mass
			block.center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
			block.center_of_mass = position - block.position

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

func get_available_connection_points() -> Array[Connector]:
	"""获取炮塔上可用的连接点"""
	var points: Array[Connector] = []
	
	# 获取炮塔底座上的连接点
	var base_points = find_children("*", "Connector")
	for point in base_points:
		if point is Connector and not point.connected_to:
			points.append(point)
	
	# 获取炮塔上已有块的连接点
	for block in turret_blocks:
		if is_instance_valid(block):
			var block_points = block.find_children("*", "Connector")
			for point in block_points:
				if point is Connector and not point.connected_to:
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

func get_turret_connectors() -> Array[TurretConnector]:
	"""获取炮塔上的所有TurretConnector"""
	var connectors: Array[TurretConnector] = []
	
	# 获取炮塔底座上的连接器
	var base_connectors = find_children("*", "TurretConnector")
	for connector in base_connectors:
		if connector is TurretConnector and connector.is_connection_enabled and connector.connected_to == null:
			connectors.append(connector)
	
	# 获取炮塔上已有块的连接器
	for block in turret_blocks:
		if is_instance_valid(block):
			var block_connectors = block.find_children("*", "TurretConnector")
			for connector in block_connectors:
				if connector is TurretConnector and connector.is_connection_enabled and connector.connected_to == null:
					connectors.append(connector)
	
	return connectors

func get_available_turret_connectors() -> Array[TurretConnector]:
	"""获取可用的炮塔连接器"""
	var connectors: Array[TurretConnector] = []
	
	for connector in get_turret_connectors():
		if connector.is_connection_enabled and connector.connected_to == null:
			connectors.append(connector)
	
	return connectors

###################### 炮塔编辑模式相关方法 ######################

func enable_turret_rotation():
	"""启用炮塔旋转"""
	is_turret_rotation_enabled = true

func disable_turret_rotation():
	"""禁用炮塔旋转"""
	is_turret_rotation_enabled = false
	
	# 停止所有旋转力v
	if turret_basket:
		turret_basket.angular_velocity = 0
		turret_basket.global_rotation = global_rotation
	

func reset_turret_rotation():
	"""炮塔回正"""
	if turret_basket and is_instance_valid(turret_basket):
		# 确保炮塔回正到0度
		if turret_basket:
			turret_basket.rotation = 0
		# 如果有基础旋转角度，也重置
		if has_method("set_base_rotation_degree"):
			turret_basket.base_rotation_degree = 0
		

func lock_turret_rotation():
	"""锁定炮塔旋转（完全停止）"""
	disable_turret_rotation()
	reset_turret_rotation()
	is_turret_rotation_enabled = false
	# 额外确保停止所有物理运动
	if turret_basket:
		turret_basket.angular_velocity = 0
		turret_basket.rotation = 0
		print("锁定炮塔旋转: ", block_name, turret_basket.rotation)
	

func unlock_turret_rotation():
	"""解锁炮塔旋转"""
	if turret_basket:
		turret_basket.freeze = false
	enable_turret_rotation()
	is_turret_rotation_enabled = true

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
