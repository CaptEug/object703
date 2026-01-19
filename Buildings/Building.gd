extends Node2D
class_name Building

# 建筑网格和块管理
const GRID_SIZE:int = 16

@export var building_name:String = "未命名建筑"
@export var blueprint:Variant = null
@export var is_constructed:bool = true  # 是否已建造完成
@export var construction_progress:float = 0.0  # 建造进度
@export var construction_time:float = 5.0  # 建造时间（秒）
@export var can_be_demolished:bool = true  # 是否可拆除
@export var building_type:String = "structure"  # 建筑类型：structure, defense, production等

var grid:Dictionary = {}  # 网格位置 -> 建筑块
var blocks:Array[Block] = []  # 所有建筑块
var total_blocks:Array[Block] = []  # 包括子节点中的所有块
var building_size:Vector2i = Vector2i.ZERO
var total_mass:float = 0.0
var total_cost:Dictionary = {}  # 建筑总成本
var destroyed:bool = false
var selected:bool = false
var building_editor_panel:Panel = null

# 信号
signal construction_started(building: Building)
signal construction_progress_updated(progress: float)
signal construction_completed(building: Building)
signal building_damaged(building: Building, damage: float)
signal building_destroyed(building: Building)
signal block_added(block: Block)
signal block_removed(block: Block)

func _ready():
	if blueprint:
		load_blueprint()
	else:
		initialize_empty_building()
	
	# 如果是已建造的建筑，冻结所有块
	if is_constructed:
		freeze_all_blocks(true)

func load_blueprint():
	if blueprint is String:
		load_from_file(blueprint)
	elif blueprint is Dictionary:
		load_from_blueprint(blueprint)
	else:
		push_error("Invalid blueprint format")
	update_building()

func initialize_empty_building():
	building_name = "未命名建筑"
	blocks = []
	total_blocks = []
	grid = {}

func _process(delta):
	pass

func update_building():
	"""更新建筑状态"""
	calculate_total_mass()
	calculate_building_size()
	calculate_total_cost()
	
	# 检查建筑是否被摧毁
	var has_functioning_block = false
	for block in blocks:
		if is_instance_valid(block) and block.functioning:
			has_functioning_block = true
			break
	
	destroyed = not has_functioning_block

###################### 建筑块管理 ######################

func add_block(block: Block, local_pos: Vector2 = Vector2.ZERO, grid_positions: Array = []):
	"""添加一个建筑块"""
	if block not in blocks:
		blocks.append(block)
		total_blocks.append(block)
		
		# 设置块的父节点
		if block.parent_vehicle == null:
			add_child(block)
			block.parent_vehicle = null
		
		# 设置位置
		if local_pos != Vector2.ZERO:
			block.position = local_pos
		
		# 添加到网格
		if not grid_positions.is_empty():
			for pos in grid_positions:
				grid[pos] = block
		
		# 设置建筑块属性
		block.do_connect = false  # 建筑块不自动连接
		block.collision_layer = 4  # 建筑层
		block.collision_mask = 4
		
		# 冻结建筑块（静态）
		block.freeze = true
		block.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		
		# 禁用连接点
		block.enable_all_connectors(false)
		
		# 等待一帧后连接（如果需要）
		await get_tree().process_frame
		if block.has_method("connect_aready"):
			await block.connect_aready()
		
		block_added.emit(block)
		update_building()

func remove_block(block: Block, immediate: bool = false):
	"""移除一个建筑块"""
	blocks.erase(block)
	total_blocks.erase(block)
	
	# 从网格中移除
	var keys_to_erase = []
	for pos in grid:
		if grid[pos] == block:
			keys_to_erase.append(pos)
	for pos in keys_to_erase:
		grid.erase(pos)
	
	if immediate:
		block.queue_free()
	
	block_removed.emit(block)
	update_building()

func freeze_all_blocks(freeze: bool):
	"""冻结或解冻所有建筑块"""
	for block in blocks:
		if is_instance_valid(block):
			block.freeze = freeze
			#block.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC if freeze else RigidBody2D.FREEZE_MODE_DYNAMIC

###################### 建造系统 ######################

func start_construction():
	"""开始建造过程"""
	if is_constructed:
		return
	
	is_constructed = false
	construction_progress = 0.0
	
	# 将所有块设置为半透明
	for block in blocks:
		if is_instance_valid(block):
			block.modulate = Color(0.7, 0.7, 1.0, 0.6)
			block.collision_layer = 0  # 建造中禁用碰撞
			block.collision_mask = 0
	
	construction_started.emit(self)
	
	# 开始建造计时器
	if construction_time > 0:
		var timer = get_tree().create_timer(construction_time)
		timer.timeout.connect(finish_construction)
		
		# 每秒更新进度（如果需要显示进度条）
		var progress_timer = get_tree().create_timer(1.0)
		progress_timer.timeout.connect(update_construction_progress)

func update_construction_progress():
	"""更新建造进度"""
	if is_constructed:
		return
	
	construction_progress += 1.0 / construction_time
	construction_progress = clamp(construction_progress, 0.0, 1.0)
	
	construction_progress_updated.emit(construction_progress)
	
	# 如果还没完成，继续更新
	if construction_progress < 1.0:
		var progress_timer = get_tree().create_timer(1.0)
		progress_timer.timeout.connect(update_construction_progress)

func finish_construction():
	"""完成建造"""
	is_constructed = true
	construction_progress = 1.0
	
	# 恢复所有块的正常状态
	for block in blocks:
		if is_instance_valid(block):
			block.modulate = Color.WHITE
			block.collision_layer = 4
			block.collision_mask = 4
	
	# 冻结所有块
	freeze_all_blocks(true)
	
	construction_completed.emit(self)

func demolish():
	"""拆除建筑"""
	if not can_be_demolished:
		return
	
	# 按顺序移除所有块
	var blocks_to_remove = blocks.duplicate()
	for block in blocks_to_remove:
		if is_instance_valid(block):
			remove_block(block, true)
	
	building_destroyed.emit(self)
	queue_free()

func damage(damage_amount: float):
	"""对建筑造成伤害"""
	building_damaged.emit(self, damage_amount)
	
	# 简单实现：对所有块造成平均伤害
	var blocks_damaged = 0
	for block in blocks:
		if is_instance_valid(block) and block.has_method("damage"):
			block.damage(damage_amount / blocks.size())
			blocks_damaged += 1
	
	if blocks_damaged == 0:
		destroyed = true
		building_destroyed.emit(self)

###################### 建筑属性计算 ######################

func calculate_total_mass():
	"""计算建筑总质量"""
	total_mass = 0.0
	for block in blocks:
		if is_instance_valid(block):
			total_mass += block.mass
	return total_mass

func calculate_building_size():
	"""计算建筑尺寸"""
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

func calculate_total_cost():
	"""计算建筑总成本"""
	total_cost = {}
	for block in blocks:
		if is_instance_valid(block):
			for resource in block.cost:
				if not total_cost.has(resource):
					total_cost[resource] = 0
				total_cost[resource] += block.cost[resource]
	return total_cost

func get_center_position() -> Vector2:
	"""获取建筑中心位置"""
	if grid.is_empty():
		return global_position
	
	var x_coords = []
	var y_coords = []
	
	for grid_pos in grid:
		x_coords.append(grid_pos.x)
		y_coords.append(grid_pos.y)
	
	x_coords.sort()
	y_coords.sort()
	
	var min_x = x_coords[0]
	var max_x = x_coords[x_coords.size() - 1]
	var min_y = y_coords[0]
	var max_y = y_coords[y_coords.size() - 1]
	
	var center_x = (min_x + max_x) * 0.5 * GRID_SIZE
	var center_y = (min_y + max_y) * 0.5 * GRID_SIZE
	
	return Vector2(center_x, center_y)

###################### 蓝图系统 ######################

func load_from_file(identifier: String):
	"""从文件加载蓝图"""
	var path: String
	if not identifier.ends_with(".json"):
		path = "res://buildings/blueprint/%s.json" % identifier
	else:
		path = identifier
	
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
	"""从蓝图数据加载"""
	initialize_empty_building()
	
	building_name = bp.get("name", "未命名建筑")
	building_type = bp.get("building_type", "structure")
	construction_time = bp.get("construction_time", 5.0)
	
	# 按数字键排序以保证加载顺序一致
	var block_ids = bp["blocks"].keys()
	block_ids.sort()
	
	for block_id in block_ids:
		var block_data = bp["blocks"][block_id]
		var block_scene = load(block_data["path"])
		
		if block_scene:
			var block: Block = block_scene.instantiate()
			var base_pos = Vector2(block_data["base_pos"][0], block_data["base_pos"][1])
			block.rotation = deg_to_rad(block_data.get("rotation", [0])[0])
			block.base_rotation_degree = block_data.get("rotation", [0])[0]
			
			var target_grid = calculate_block_grid_positions(block, base_pos)
			var local_pos = get_rectangle_corners(target_grid)
			
			add_block(block, local_pos, target_grid)
	
	update_building()

func calculate_block_grid_positions(block: Block, base_pos: Vector2) -> Array:
	"""计算块占据的网格位置"""
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

func get_rectangle_corners(grid_data: Array) -> Vector2:
	"""获取一组网格位置的矩形中心"""
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

###################### 编辑器支持 ######################

func get_available_points_near_position(position: Vector2, max_distance: float = 30.0) -> Array[Connector]:
	"""获取指定位置附近的可用连接点"""
	var temp_points = []
	var max_distance_squared = max_distance * max_distance
	
	for block in blocks:
		if is_instance_valid(block):
			for point in block.get_available_connection_points():
				var point_global_pos = block.global_position + point.position.rotated(block.global_rotation)
				var distance_squared = point_global_pos.distance_squared_to(position)
				
				if distance_squared <= max_distance_squared:
					temp_points.append(point)
	
	var available_points: Array[Connector] = []
	for point in temp_points:
		if point is Connector:
			available_points.append(point)
	
	return available_points

func open_building_panel():
	"""打开建筑面板"""
	if building_editor_panel:
		building_editor_panel.visible = true
		building_editor_panel.move_to_front()
	else:
		var UI = get_tree().current_scene.find_child("CanvasLayer") as CanvasLayer
		var panel = load("res://ui/building_panel.tscn").instantiate()
		panel.selected_building = self
		building_editor_panel = panel
		UI.add_child(panel)
		while panel.any_overlap():
			panel.position += Vector2(32, 32)

###################### 辅助函数 ######################

func get_block_at_position(position: Vector2) -> Block:
	"""获取指定位置的建筑块"""
	var space_state = get_tree().root.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = position
	query.collision_mask = 4  # 建筑层
	
	var result = space_state.intersect_point(query)
	for collision in result:
		var block = collision.collider
		if block is Block and block.get_parent() == self:
			return block
	return null

func is_position_available(grid_positions: Array) -> bool:
	"""检查一组网格位置是否可用"""
	for pos in grid_positions:
		if grid.has(pos):
			return false
	return true

func save_blueprint(save_name: String) -> bool:
	"""保存建筑蓝图"""
	var blueprint_data = {
		"name": save_name,
		"building_type": building_type,
		"construction_time": construction_time,
		"blocks": {},
		"building_size": [building_size.x, building_size.y]
	}
	
	var block_counter = 1
	var processed_blocks = {}
	
	# 计算建筑网格范围
	var min_x = INF
	var min_y = INF
	var max_x = -INF
	var max_y = -INF
	
	for grid_pos in grid:
		min_x = min(min_x, grid_pos.x)
		min_y = min(min_y, grid_pos.y)
		max_x = max(max_x, grid_pos.x)
		max_y = max(max_y, grid_pos.y)
	
	# 存储所有块
	for grid_pos in grid:
		var block = grid[grid_pos]
		if not processed_blocks.has(block):
			var relative_pos = Vector2i(grid_pos.x - min_x, grid_pos.y - min_y)
			
			var block_data = {
				"name": block.block_name,
				"path": block.scene_file_path,
				"base_pos": [relative_pos.x, relative_pos.y],
				"rotation": [block.base_rotation_degree],
			}
			
			blueprint_data["blocks"][str(block_counter)] = block_data
			block_counter += 1
			processed_blocks[block] = true
	
	# 保存到文件
	var save_path = "res://buildings/blueprint/%s.json" % save_name
	var dir = DirAccess.open("res://buildings/blueprint/")
	if not dir:
		DirAccess.make_dir_absolute("res://buildings/blueprint/")
	
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(blueprint_data, "\t"))
		file.close()
		return true
	else:
		push_error("Failed to save file:", FileAccess.get_open_error())
		return false
