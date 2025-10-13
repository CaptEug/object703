class_name TurretRing
extends Block

var load:float
var turret:RigidBody2D
var traverse:Array
var max_torque:float = 1000
var damping:float = 100

# 炮塔专用的grid系统
var turret_grid := {}
var turret_blocks := []
var turret_size: Vector2i

func _ready():
	super._ready()
	turret = find_child("Turret") as RigidBody2D
	initialize_turret_grid()

func _physics_process(_delta):
	aim(get_global_mouse_position())

func aim(target_pos):
	var target_angle = (target_pos - global_position).angle() - rotation + deg_to_rad(90)
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
		
		# 设置block为炮塔的子节点（如果还不是的话）
		if block.get_parent() != turret:
			var old_parent = block.get_parent()
			if old_parent:
				old_parent.remove_child(block)
			turret.add_child(block)
		
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
		
		# 更新炮塔大小
		update_turret_size()
		
		print("从炮塔移除block: ", block.block_name)

func calculate_block_grid_positions(block: Block) -> Array:
	"""计算block在炮塔grid中的位置"""
	var positions = []
	var base_pos = Vector2i(0, 0)  # 以炮塔中心为原点
	
	# 根据block的大小和旋转计算所有网格位置
	for x in block.size.x:
		for y in block.size.y:
			var grid_pos: Vector2i
			
			# 考虑block的旋转
			if block.base_rotation_degree == 0:
				grid_pos = base_pos + Vector2i(x, y)
			elif block.base_rotation_degree == 90:
				grid_pos = base_pos + Vector2i(-y, x)
			elif block.base_rotation_degree == -90:
				grid_pos = base_pos + Vector2i(y, -x)
			else:  # 180度
				grid_pos = base_pos + Vector2i(-x, -y)
			
			positions.append(grid_pos)
	
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

func find_turret_block_position(block: Block) -> Vector2i:
	"""查找block在炮塔grid中的主要位置"""
	var positions = get_turret_block_grid(block)
	if positions.is_empty():
		return Vector2i.ZERO
	
	# 返回左上角的位置
	var top_left = positions[0]
	for pos in positions:
		if pos.x < top_left.x or (pos.x == top_left.x and pos.y < top_left.y):
			top_left = pos
	return top_left

func get_turret_center_of_mass() -> Vector2:
	"""计算炮塔上所有block的质心"""
	var total_mass := 0.0
	var weighted_sum := Vector2.ZERO
	
	for block in turret_blocks:
		if is_instance_valid(block):
			var block_positions = get_turret_block_grid(block)
			if not block_positions.is_empty():
				# 计算block的中心位置（相对于炮塔局部坐标）
				var block_center = calculate_block_center(block_positions)
				weighted_sum += block_center * block.mass
				total_mass += block.mass
	
	return weighted_sum / total_mass if total_mass > 0 else Vector2.ZERO

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

func get_turret_block_neighbors(block: Block) -> Dictionary:
	"""获取block在炮塔grid中的邻居"""
	var neighbors = {}
	var block_positions = get_turret_block_grid(block)
	
	for pos in block_positions:
		var directions = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
		for dir in directions:
			var neighbor_pos = pos + dir
			var neighbor = turret_grid.get(neighbor_pos)
			if neighbor and neighbor != block:
				neighbors[neighbor_pos - pos] = neighbor
	
	return neighbors

###################### 炮塔管理方法 ######################

func get_all_turret_blocks() -> Array:
	"""获取炮塔上所有block"""
	return turret_blocks.duplicate()

func clear_turret_blocks():
	"""清空炮塔上所有block"""
	for block in turret_blocks.duplicate():
		remove_block_from_turret(block)

func is_position_available(grid_pos: Vector2i) -> bool:
	"""检查指定grid位置是否可用"""
	return turret_grid.get(grid_pos) == null

func get_available_positions_near(position: Vector2i, radius: int = 2) -> Array:
	"""获取指定位置附近可用的grid位置"""
	var available = []
	
	for x in range(position.x - radius, position.x + radius + 1):
		for y in range(position.y - radius, position.y + radius + 1):
			var check_pos = Vector2i(x, y)
			if is_position_available(check_pos):
				available.append(check_pos)
	
	return available
