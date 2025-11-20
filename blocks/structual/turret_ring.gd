class_name TurretRing
extends Block

var load:float
var turret_basket:RigidBody2D
var joint:PinJoint2D
var traverse:Array
var rotation_speed:float
var relative_rot:float = 0.0

# 炮塔专用的grid系统
var turret_grid := {}
var turret_blocks := []
var turret_size: Vector2i
var total_mass:= 0.0
var block_mass:= 0.0
var old_t_v

# 扭矩控制参数
var rotation_stiffness: float = 200.0    
var rotation_damping: float = 30.0     
var max_torque: float = 36000.0      
var torque_ramp_up_speed: float = 5000.0   
var torque_ramp_down_speed: float = 8000.0
var current_torque: float = 0.0      
var last_angle_diff: float = 0.0    
var angular_acceleration: float = 0.0    


# 炮塔旋转控制
var is_turret_rotation_enabled: bool = true

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

func _physics_process(delta):
	## 只有在启用时才进行瞄准
	if parent_vehicle and is_turret_rotation_enabled:
		#aim(delta, get_global_mouse_position())
		calculate_turret_target_torque(delta)
	else:
		if turret_basket:
			# 禁用时停止所有旋转
			turret_basket.angular_velocity = 0
			turret_basket.rotation = rotation
	pass

func aim(delta, target_pos):
	var target_angle = (target_pos - global_position).angle() + deg_to_rad(90)
	var angle_diff = wrapf(target_angle - turret_basket.rotation, -PI, PI)
	
	# 计算需要的扭矩
	var torque = 0.0
	
	# 只在需要旋转时施加力
	if abs(angle_diff) > deg_to_rad(1):
		var base_torque = angle_diff * rotation_stiffness
		var damping_torque = -turret_basket.angular_velocity * rotation_damping
		torque = base_torque + damping_torque
	
	# 应用扭矩
	if abs(torque) > 0.01:
		turret_basket.apply_torque(torque)
	
	# 返回是否瞄准
	return abs(angle_diff) < deg_to_rad(1)

func calculate_turret_target_torque(delta: float) -> float:
	var now_t_v = angular_velocity
	
	# 计算角加速度 (rad/s²)
	var angular_acceleration = (now_t_v - old_t_v) / delta
	
	var body_rid = turret_basket.get_rid()
	if body_rid.is_valid():
		var body_state = PhysicsServer2D.body_get_direct_state(body_rid)
		if body_state:
			var inverse_inertia = body_state.inverse_inertia
			if inverse_inertia > 0:
				var moment_of_inertia = 1.0 / inverse_inertia
				
				# 扭矩 = 角加速度 × 转动惯量
				var torque = angular_acceleration * moment_of_inertia
				
				print("角速度差: ", angular_acceleration)
				print("转动惯量: ", moment_of_inertia)
				print("需要扭矩: ", torque)

				
				# 保存当前角速度供下一帧使用
				old_t_v = now_t_v
				
				return torque
	
	old_t_v = now_t_v
	return 0.0

# 计算目标角速度
func calculate_target_angular_velocity(angle_diff: float, delta: float) -> float:
	if abs(angle_diff) < deg_to_rad(0.5):
		return 0.0
	
	# 基于角度差计算理想角速度（带平滑）
	var max_allowed_speed = rotation_speed
	var speed_factor = clamp(abs(angle_diff) / deg_to_rad(30), 0.1, 1.0)
	var ideal_speed = rotation_speed * speed_factor * sign(angle_diff)
	
	# 考虑角加速度限制
	var max_acceleration = max_torque / get_effective_inertia()
	var speed_change_limit = max_acceleration * delta
	
	return clamp(ideal_speed, 
		turret_basket.angular_velocity - speed_change_limit, 
		turret_basket.angular_velocity + speed_change_limit)

# 计算理想扭矩
func calculate_ideal_torque(angle_diff: float, angular_velocity_diff: float) -> float:
	# PD控制器：比例项 + 微分项
	var p_term = angle_diff * rotation_stiffness
	var d_term = angular_velocity_diff * rotation_damping
	
	var ideal_torque = p_term + d_term
	
	# 非线性刚度（小角度时降低刚度避免振荡）
	if abs(angle_diff) < deg_to_rad(5):
		var factor = abs(angle_diff) / deg_to_rad(5)
		ideal_torque *= factor * factor  # 二次曲线平滑
	
	# 扭矩限制
	return clamp(ideal_torque, -max_torque, max_torque)

# 应用扭矩平滑
func apply_torque_smoothing(target_torque: float, current_torque: float, delta: float) -> float:
	var torque_diff = target_torque - current_torque
	var ramp_speed = torque_ramp_up_speed if abs(torque_diff) > 0 else torque_ramp_down_speed
	var max_change = ramp_speed * delta
	
	if abs(torque_diff) <= max_change:
		return target_torque
	else:
		return current_torque + clamp(torque_diff, -max_change, max_change)

# 计算有效扭矩（考虑转动惯量）
func calculate_effective_torque(torque: float) -> float:
	var inertia = get_effective_inertia()
	
	# 如果转动惯量很小，限制最小扭矩以避免过度敏感
	var min_effective_torque = 0.1
	if abs(torque) < min_effective_torque and inertia < 1.0:
		return 0.0
	
	return torque

# 获取有效转动惯量
func get_effective_inertia() -> float:
	# 尝试从物理服务器获取真实的转动惯量
	var body_rid = turret_basket.get_rid()
	if body_rid.is_valid():
		var body_state = PhysicsServer2D.body_get_direct_state(body_rid)
		if body_state:
			var inverse_inertia = body_state.inverse_inertia
			if inverse_inertia > 0:
				return 1.0 / inverse_inertia
	
	# 备用方案：使用质量估算
	return turret_basket.mass * 2.0  # 简化估算

# 更新旋转状态
func update_rotation_state(delta: float):
	# 基于实际物理模拟更新相对旋转
	var actual_angular_velocity = turret_basket.angular_velocity
	
	# 积分得到相对旋转（考虑角加速度）
	angular_acceleration = actual_angular_velocity - (relative_rot - turret_basket.rotation + rotation) / delta
	relative_rot += actual_angular_velocity * delta + 0.5 * angular_acceleration * delta * delta
	
	# 更新炮塔篮子的旋转
	turret_basket.rotation = relative_rot + rotation

# 应用旋转限制
func apply_rotation_limits(delta: float):
	if not traverse:
		return
	
	var min_angle = deg_to_rad(traverse[0])
	var max_angle = deg_to_rad(traverse[1])
	
	# 检查是否接近限制
	var near_min = relative_rot < min_angle + deg_to_rad(5)
	var near_max = relative_rot > max_angle - deg_to_rad(5)
	
	if near_min or near_max:
		# 计算限制扭矩
		var limit_torque = calculate_limit_torque(min_angle, max_angle, delta)
		if abs(limit_torque) > 0.001:
			turret_basket.apply_torque(limit_torque)
		
		# 硬限制
		relative_rot = clamp(relative_rot, min_angle, max_angle)

# 计算限制区域扭矩
func calculate_limit_torque(min_angle: float, max_angle: float, delta: float) -> float:
	var limit_torque = 0.0
	var overshoot = 0.0
	
	if relative_rot < min_angle:
		overshoot = min_angle - relative_rot
		# 强恢复力 + 阻尼
		limit_torque = overshoot * rotation_stiffness * 5.0 - turret_basket.angular_velocity * rotation_damping * 3.0
	elif relative_rot > max_angle:
		overshoot = relative_rot - max_angle
		limit_torque = -overshoot * rotation_stiffness * 5.0 - turret_basket.angular_velocity * rotation_damping * 3.0
	
	return clamp(limit_torque, -max_torque * 2.0, max_torque * 2.0)

# 检查是否已瞄准
func is_aimed(angle_diff: float) -> bool:
	# 考虑角速度的瞄准判断
	var angular_velocity_threshold = deg_to_rad(0.5)
	var is_slow_enough = abs(turret_basket.angular_velocity) < angular_velocity_threshold
	var is_close_enough = abs(angle_diff) < deg_to_rad(1)
	
	return is_close_enough and is_slow_enough

# 更新调试信息
func update_debug_info(angle_diff: float, torque: float, delta: float):
	if Input.is_action_pressed("ui_accept"):
		print("=== 炮塔控制系统 ===")
		print("角度差: %.2f°" % rad_to_deg(angle_diff))
		print("角速度: %.2f rad/s" % turret_basket.angular_velocity)
		print("当前扭矩: %.2f N·m" % torque)
		print("相对旋转: %.2f°" % rad_to_deg(relative_rot))
		print("转动惯量: %.2f" % get_effective_inertia())
		print("角加速度: %.2f rad/s²" % angular_acceleration)
		print("==================")

# 重置控制系统
func reset_control_system():
	current_torque = 0.0
	last_angle_diff = 0.0
	angular_acceleration = 0.0

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
		
		# 更新炮塔物理属性
		update_turret_physics()
		parent_vehicle.update_vehicle()
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
		parent_vehicle.update_vehicle()
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
	block_mass = mass
	for block:Block in turret_blocks:
		if is_instance_valid(block):
			total_mass += block.mass

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
	
	# 停止所有旋转力
	if turret_basket:
		turret_basket.angular_velocity = 0
		turret_basket.rotation = rotation

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
