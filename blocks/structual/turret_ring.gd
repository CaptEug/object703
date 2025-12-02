class_name TurretRing
extends Block

var load:float
var turret_basket:RigidBody2D
var joint:PinJoint2D
var traverse:Array
var max_torque:float
var damping_ratio:float = 1
var turret_inertia:float

# 炮塔专用的grid系统
var turret_grid := {}
var turret_blocks := []
var turret_size: Vector2i
var total_mass:= 0.0
var old_t_v:float

# 炮塔旋转控制
var is_turret_rotation_enabled: bool = true

# 缓存优化
var cached_turret_bounds: Dictionary
var bounds_dirty: bool = true


func _ready():
	super._ready()
	turret_basket = find_child("TurretBasket") as RigidBody2D
	joint = find_child("PinJoint2D") as PinJoint2D
	total_mass = mass
	initialize_turret_grid()
	old_t_v = angular_velocity

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
		turret_basket.turret_ring = self

func _physics_process(delta):
	if not parent_vehicle:
		return
	
	turret_inertia = 1.0 / PhysicsServer2D.body_get_direct_state(turret_basket.get_rid()).inverse_inertia
	
	if is_finite(turret_inertia):
		if is_turret_rotation_enabled:
			apply_aim_torque(delta, get_global_mouse_position())
		apply_sync_torque(delta)

func apply_aim_torque(delta, target_pos):
	var target_angle = (target_pos - global_position).angle() - parent_vehicle.global_rotation + deg_to_rad(90)
	var angle_diff = wrapf(target_angle - turret_basket.rotation, -PI, PI)
	var rev_angvel = turret_basket.angular_velocity - angular_velocity
	
	var torque = angle_diff * max_torque
	if abs(angle_diff) > deg_to_rad(1):
		var damping_factor = 2 * sqrt(turret_inertia * max_torque)
		torque -= rev_angvel * damping_factor
		turret_basket.apply_torque(torque)
	return torque

func apply_sync_torque(delta: float):
	var now_t_v = angular_velocity
	var angular_acceleration = (now_t_v - old_t_v) / delta
	var torque = angular_acceleration * turret_inertia
	turret_basket.apply_torque(torque)
	old_t_v = now_t_v
	return torque

###################### 炮塔Grid系统 ######################

func initialize_turret_grid():
	"""初始化炮塔的grid系统"""
	turret_grid.clear()
	turret_blocks.clear()
	
	for child in turret_basket.get_children():
		if child is Block and child != self:
			add_block_to_turret(child)

func add_block_to_turret(block: Block, grid_positions: Array = []) -> bool:
	"""添加block到炮塔grid系统"""
	if not block:
		return false
	block.parent_vehicle = parent_vehicle
	# 检查所有网格位置是否可用
	if not grid_positions.is_empty():
		for pos in grid_positions:
			if not is_position_available(pos):
				print("错误: 位置 ", pos, " 已被占用，当前占用块: ", turret_grid.get(pos))
				return false
	else:
		# 如果没有提供网格位置，计算它们
		grid_positions = calculate_block_grid_positions(block)
		# 验证计算出的位置
		for pos in grid_positions:
			if not is_position_available(pos):
				print("错误: 计算出的位置 ", pos, " 已被占用，当前占用块: ", turret_grid.get(pos))
				return false
	
	if parent_vehicle:
		update_parent_vehicle_blocks(block, true)
	
	if block not in turret_blocks:
		turret_blocks.append(block)
		block.z_index = 50  # 确保实际块的 z-index 低于虚影块
		
		if grid_positions.is_empty():
			grid_positions = calculate_block_grid_positions(block)
		
		for pos in grid_positions:
			turret_grid[pos] = block
		
		if block.get_parent() != turret_basket:
			reparent_block_to_turret(block, grid_positions)
		
		if block is CollisionObject2D:
			block.collision_layer = 2
			block.collision_mask = 2
		
		update_turret_properties()
		print("成功添加块到炮塔，网格位置: ", grid_positions)
		return true
	
	return false

func reparent_block_to_turret(block: Block, grid_positions: Array):
	"""将块重新父级到炮塔"""
	print("重新父级块: ", block.name, " 到炮塔篮筐，网格位置: ", grid_positions)
	
	var old_parent = block.get_parent()
	if old_parent and old_parent.has_method("remove_block"):
		old_parent.remove_block(block, false)
	
	var global_pos = block.global_position
	var global_rot = block.global_rotation
	
	# 将块添加到炮塔篮筐
	turret_basket.add_child(block)
	block.on_turret = self
	block.global_position = global_pos
	block.global_rotation = global_rot
	
	print("重新父级完成，新父级: ", block.get_parent())

func update_parent_vehicle_blocks(block: Block, add: bool):
	"""更新父车辆中的块列表"""
	if not parent_vehicle:
		return
	
	if add:
		if block not in parent_vehicle.blocks:
			parent_vehicle.blocks.append(block)
		
		if block is Powerpack and block not in parent_vehicle.powerpacks:
			parent_vehicle.powerpacks.append(block)
		elif block is Command and block not in parent_vehicle.commands:
			parent_vehicle.commands.append(block)
		elif block is Ammorack and block not in parent_vehicle.ammoracks:
			parent_vehicle.ammoracks.append(block)
		elif block is Fueltank and block not in parent_vehicle.fueltanks:
			parent_vehicle.fueltanks.append(block)
	else:
		parent_vehicle.blocks.erase(block)
		if block is Powerpack:
			parent_vehicle.powerpacks.erase(block)
		elif block is Command:
			parent_vehicle.commands.erase(block)
		elif block is Ammorack:
			parent_vehicle.ammoracks.erase(block)
		elif block is Fueltank:
			parent_vehicle.fueltanks.erase(block)
	print(turret_grid)

func remove_block_from_turret(block: Block):
	"""从炮塔grid系统移除block"""
	if not block:
		return
	
	if parent_vehicle:
		update_parent_vehicle_blocks(block, false)
	
	if block in turret_blocks:
		turret_blocks.erase(block)
		
		var keys_to_erase = []
		for pos in turret_grid:
			if turret_grid[pos] == block:
				keys_to_erase.append(pos)
		for pos in keys_to_erase:
			turret_grid.erase(pos)
			for body in turret_basket.get_children():
				if body is StaticBody2D:
					for connector in body.get_children():
						if connector is TurretConnector:
							if connector.location == pos:
								connector.connected_to = null
								connector.is_connection_enabled = true
								if is_instance_valid(connector.joint):
									connector.joint.queue_free()
		
		for block_1:Block in turret_blocks:
			for point in block_1.get_children():
				if point is Connector:
					if point.connected_to == null:
						point.is_connection_enabled = true
					else:
						if point.connected_to.find_parent_block() == block:
							point.connected_to = null
							point.is_connection_enabled = true
							
		
		# 从炮塔篮筐中移除
		if block.get_parent() == turret_basket:
			turret_basket.remove_child(block)
		
		block.on_turret = null
		
		update_turret_properties()
		print("从炮塔移除块")

func calculate_block_grid_positions(block: Block) -> Array:
	"""计算block在炮塔grid中的位置"""
	var positions = []
	
	# 使用块的全局位置来计算网格位置，确保准确性
	var global_block_pos = block.global_position
	var turret_global_pos = global_position
	
	# 计算相对于炮塔的局部位置
	var relative_pos = global_block_pos - turret_global_pos
	
	var base_pos = Vector2i(
		floor(relative_pos.x / 16),
		floor(relative_pos.y / 16)
	)
	
	print("计算块网格位置: 全局位置=", global_block_pos, " 炮塔位置=", turret_global_pos, " 相对位置=", relative_pos, " 基准位置=", base_pos)
	
	for x in range(block.size.x):
		for y in range(block.size.y):
			var grid_pos: Vector2i
			
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
	
	print("计算出的网格位置: ", positions)
	return positions

func update_turret_properties():
	"""更新炮塔所有属性"""
	update_turret_physics()
	update_turret_size()
	if parent_vehicle:
		parent_vehicle.update_vehicle()
	bounds_dirty = true

func update_turret_size():
	"""更新炮塔的尺寸"""
	if turret_grid.is_empty():
		turret_size = Vector2i.ZERO
		return
	
	var bounds = get_turret_grid_bounds()
	turret_size = Vector2i(bounds.width, bounds.height)

func update_turret_physics():
	"""更新炮塔的物理属性"""
	total_mass = mass
	for block:Block in turret_blocks:
		if is_instance_valid(block):
			total_mass += block.mass
			block.linear_damp = 0
			block.angular_damp = 0

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
	var existing_block = turret_grid.get(grid_pos)
	if existing_block:
		print("位置 ", grid_pos, " 已被块占用: ", existing_block.name if existing_block else "未知块")
		return false
	return true

func get_available_connection_points() -> Array[Connector]:
	"""获取炮塔上可用的连接点"""
	var points: Array[Connector] = []
	
	var base_points = find_children("*", "Connector")
	for point in base_points:
		if point is Connector and not point.connected_to:
			points.append(point)
	
	for block in turret_blocks:
		if is_instance_valid(block):
			var block_points = block.find_children("*", "Connector")
			for point in block_points:
				if point is Connector and not point.connected_to:
					points.append(point)
	
	return points

###################### 炮塔块管理方法 ######################

func get_attached_blocks() -> Array:
	"""获取炮塔上附加的所有块 - 用于编辑器"""
	return turret_blocks.duplicate()

func get_turret_blocks() -> Array:
	"""获取炮塔上所有块的别名方法"""
	return get_attached_blocks()

func get_all_blocks() -> Array:
	"""获取所有块（包括炮塔本身）"""
	var all_blocks = [self]
	all_blocks.append_array(turret_blocks)
	return all_blocks

func get_turret_connectors() -> Array[TurretConnector]:
	"""获取炮塔上的所有TurretConnector"""
	return get_connectors_of_type("TurretConnector")

func get_available_turret_connectors() -> Array[TurretConnector]:
	"""获取可用的炮塔连接器"""
	var connectors: Array[TurretConnector] = []
	
	for connector in get_turret_connectors():
		if connector.is_connection_enabled and connector.connected_to == null:
			connectors.append(connector)
	
	return connectors

func get_connectors_of_type(connector_type: String) -> Array:
	"""通用方法：获取指定类型的连接器"""
	var connectors = []
	
	var base_connectors = find_children("*", connector_type)
	for connector in base_connectors:
		if connector.is_connection_enabled and connector.connected_to == null:
			connectors.append(connector)
	
	for block in turret_blocks:
		if is_instance_valid(block):
			var block_connectors = block.find_children("*", connector_type)
			for connector in block_connectors:
				if connector.is_connection_enabled and connector.connected_to == null:
					connectors.append(connector)
	
	return connectors

###################### 炮塔编辑模式相关方法 ######################

func lock_turret_rotation():
	"""锁定炮塔旋转（完全停止）"""
	is_turret_rotation_enabled = false
	turret_basket.angular_velocity = angular_velocity
	turret_basket.global_rotation = global_rotation

func unlock_turret_rotation():
	"""解锁炮塔旋转"""
	is_turret_rotation_enabled = true

func get_turret_grid_bounds() -> Dictionary:
	"""获取炮塔网格的边界"""
	if not bounds_dirty and not cached_turret_bounds.is_empty():
		return cached_turret_bounds
	
	if turret_grid.is_empty():
		cached_turret_bounds = {"min_x": 0, "min_y": 0, "max_x": 0, "max_y": 0, "width": 0, "height": 0}
		return cached_turret_bounds
	
	var min_x: int = turret_grid.keys()[0].x
	var min_y: int = turret_grid.keys()[0].y
	var max_x: int = turret_grid.keys()[0].x
	var max_y: int = turret_grid.keys()[0].y
	
	for grid_pos in turret_grid:
		min_x = min(min_x, grid_pos.x)
		min_y = min(min_y, grid_pos.y)
		max_x = max(max_x, grid_pos.x)
		max_y = max(max_y, grid_pos.y)
	
	cached_turret_bounds = {
		"min_x": min_x,
		"min_y": min_y,
		"max_x": max_x,
		"max_y": max_y,
		"width": max_x - min_x + 1,
		"height": max_y - min_y + 1
	}
	bounds_dirty = false
	return cached_turret_bounds

func calculate_block_center(positions: Array) -> Vector2:
	"""计算一组grid位置的中心点"""
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
	
	var center_x = (min_x + max_x + 1) * 8
	var center_y = (min_y + max_y + 1) * 8
	return Vector2(center_x, center_y)
